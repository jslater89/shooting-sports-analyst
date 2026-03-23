import 'dart:math';

import 'package:collection/collection.dart';
import 'package:normal/normal.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("LatentLogRater");

/// A rating system that uses a latent log-ratio model to calculate ratings.
class LatentLogRater extends RatingSystem<LatentLogRating, LatentLogSettings> {
  static const _scoreFloor = 0.01;
  static const _volatilityScaleFactor = 1.0;

  static const oldVarianceKey = "latentLogOldVariance";
  static const oldVolatilityKey = "latentLogOldVolatility";
  static const varianceChangeKey = "latentLogVarianceChange";
  static const volatilityChangeKey = "latentLogVolatilityChange";
  static const stagesKey = "latentLogStages";

  LatentLogRater({required this.settings});

  final LatentLogSettings settings;

  @override
  bool get byStage => settings.byStage;

  @override
  ShooterRating<RatingEvent> copyShooterRating(rating) {
    return LatentLogRating.copy(rating);
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[DbRatingProject.algorithmKey] = DbRatingProject.latentLogValue;
    settings.encodeToJson(json);
  }

  static LatentLogRater fromJson(Map<String, dynamic> json) {
    var settings = LatentLogSettings();
    settings.loadFromJson(json);
    return LatentLogRater(settings: settings);
  }

  @override
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  RatingEvent newEvent({
    required ShootingMatch match,
    MatchStage? stage,
    required ShooterRating<RatingEvent> rating,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  }) {
    rating as LatentLogRating;
    return LatentLogRatingEvent(
      settings: settings,
      ratingChange: 0.0,
      oldRating: rating.rating,
      oldVariance: rating.variance,
      oldVolatility: rating.volatility,
      varianceChange: 0.0,
      volatilityChange: 0.0,
      match: match,
      stage: stage,
      score: score,
      matchScore: matchScore,
      infoLines: infoLines,
      infoData: infoData,
    );
  }

  @override
  ShooterRating<RatingEvent> newShooterRating(
    MatchEntry shooter, {
    required Sport sport,
    required DateTime date,
  }) {
    return LatentLogRating(
      shooter,
      sport: sport,
      date: date,
      initialRating: 0,
      initialVariance: settings.startingVariance,
      initialVolatility: sqrt((0.05 * settings.startingVariance * _volatilityScaleFactor) * settings.startingVariance * _volatilityScaleFactor),
      settings: settings,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating<RatingEvent>> ratings) {
    StringBuffer csv = StringBuffer();
    csv.writeln("Member#,Name,Rating,Variance,Volatility,Matches,Stages");
    for (var r in ratings) {
      r as LatentLogRating;
      csv.writeln(
        '${r.memberNumber},"${r.name}",${r.rating},${r.variance},${r.volatility},${r.lengthInMatches},${r.lengthInStages}',
      );
    }
    return csv.toString();
  }

  @override
  List<JsonShooterRating> ratingsToJson(
    List<ShooterRating<RatingEvent>> ratings,
  ) {
    return ratings.map((e) => JsonShooterRating.fromShooterRating(e)).toList();
  }

  @override
  LatentLogRating wrapDbRating(DbShooterRating rating) {
    return LatentLogRating.wrapDbRatingWithSettings(this, rating);
  }

  @override
  Map<ShooterRating<RatingEvent>, RatingChange> updateShooterRatings({
    required ShootingMatch match,
    bool isMatchOngoing = false,
    required List<ShooterRating<RatingEvent>> shooters,
    required Map<ShooterRating<RatingEvent>, RelativeScore> scores,
    required Map<ShooterRating<RatingEvent>, RelativeMatchScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0,
  }) {
    // This is whole-event mode, so shooters and scores have entries for every
    // competitor. We'll do the baseline calculation first, then iterate over
    // competitors to find their pairwise residuals and find their rating
    // changes.

    Map<ShooterRating, RatingChange> changes = {};

    Map<ShooterRating, double> competitorWeights = {};
    Map<ShooterRating, double> competitorBaselineResiduals = {};
    double baselineResidual = 0.0;
    double totalWeight = 0.0;
    Map<ShooterRating, double> competitorScoreEvidence = {};
    Map<ShooterRating, double> competitorTailNoise = {};
    Map<ShooterRating, double> competitorVariances = {};

    // First pass: gather data and calculate the baseline.
    List<ShooterRating> validShooters = [];
    for (var shooter in shooters) {
      shooter as LatentLogRating;
      var score = scores[shooter];
      if (score == null || score.ratio == 0.0) {
        continue;
      }

      validShooters.add(shooter);

      final scoreEvidence = _scoreEvidence(score.ratio);
      final tailNoise = _tailObservationVariance(score.ratio);
      competitorScoreEvidence[shooter] = scoreEvidence;
      competitorTailNoise[shooter] = tailNoise;
      final shooterVariance = shooter.calculateCurrentVariance(
        asOfDate: match.date,
      );
      competitorVariances[shooter] = shooterVariance;
      final weight =
          1.0 /
          (shooterVariance +
              settings.sportVolatility +
              shooter.volatility +
              tailNoise);
      competitorWeights[shooter] = weight;
      totalWeight += weight;

      final residual = shooter.rating - scoreEvidence;
      competitorBaselineResiduals[shooter] = residual;
      baselineResidual += weight * residual;
    }

    // If baseline robustness is enabled, apply a Huber-style taper to
    // the baseline weights to downweight extreme outliers.
    if (totalWeight > 0 && settings.baselineRobustnessZ > 0) {
      final rawBaseline =
          baselineResidual / (totalWeight + _matchDifficultyPriorPrecision);
      double robustResidualSum = 0.0;
      double robustWeightSum = 0.0;
      for (var shooter in validShooters) {
        final baseWeight = competitorWeights[shooter];
        final residual = competitorBaselineResiduals[shooter];
        if (baseWeight == null || residual == null) {
          continue;
        }

        final residualSigma = sqrt(1.0 / baseWeight);
        final centeredZ = (residual - rawBaseline) / residualSigma;
        final robustWeight = _huberWeight(
          centeredZ.abs(),
          settings.baselineRobustnessZ,
        );
        final effectiveWeight = baseWeight * robustWeight;
        competitorWeights[shooter] = effectiveWeight;
        robustResidualSum += effectiveWeight * residual;
        robustWeightSum += effectiveWeight;
      }
      if (robustWeightSum > 0) {
        baselineResidual = robustResidualSum;
        totalWeight = robustWeightSum;
      }
    }

    // If weak field observation variance is enabled, calculate additional
    // observation noise for small/degenerate fields.
    final weakFieldVariance = _weakFieldObservationVariance(
      validShooters,
      scores,
    );

    for (var shooter in validShooters) {
      shooter as LatentLogRating;
      final shooterVariance = competitorVariances[shooter];
      if (shooterVariance == null) {
        continue;
      }
      var change = _calculateRatingChangeForShooter(
        match: match,
        shooter: shooter,
        shooterVariance: competitorVariances[shooter]!,
        matchDate: match.date,
        baselineResidualSum: baselineResidual,
        totalBaselineWeight: totalWeight,
        weakFieldVariance: weakFieldVariance,
        scores: scores,
        competitorScoreEvidence: competitorScoreEvidence,
        competitorTailNoise: competitorTailNoise,
        competitorWeights: competitorWeights,
      );
      if (change == null) {
        continue;
      }
      changes[shooter] = change;
    }

    return changes;
  }

  RatingChange? _calculateRatingChangeForShooter({
    /// The match being processed.
    required ShootingMatch match,

    /// The shooter being processed.
    required ShooterRating shooter,

    /// The aged variance of the shooter, accounting for time since the last update.
    required double shooterVariance,

    /// The date of the match being processed.
    required DateTime matchDate,

    /// The sum of the baseline residuals.
    required double baselineResidualSum,

    /// The total weight of the baseline.
    required double totalBaselineWeight,

    /// The weak field observation variance.
    required double weakFieldVariance,

    /// The scores of the competitors.
    required Map<ShooterRating, RelativeScore> scores,

    /// The score evidence of the competitors.
    required Map<ShooterRating, double> competitorScoreEvidence,

    /// The tail noise (i.e. additional variance) of the competitors.
    required Map<ShooterRating, double> competitorTailNoise,

    /// The weights of the competitors.
    required Map<ShooterRating, double> competitorWeights,
  }) {
    shooter as LatentLogRating;
    final shooterScore = scores[shooter];
    final shooterScoreEvidence = competitorScoreEvidence[shooter];
    final shooterTailNoise = competitorTailNoise[shooter];
    final shooterWeight = competitorWeights[shooter];
    if (shooterScore == null ||
        shooterScoreEvidence == null ||
        shooterTailNoise == null ||
        shooterWeight == null) {
      return null;
    }
    final shooterRatio = shooterScore.ratio;

    // Leave-one-out baseline: remove this competitor's own contribution
    // to avoid circularity. B_{-i} = (Σ w_j (R_j - L_j) - w_i (R_i - L_i)) / (Σ w_j - w_i).
    final looWeight = totalBaselineWeight - shooterWeight;
    if (looWeight <= 0) {
      return null;
    }
    final baselinePrecision = looWeight + _matchDifficultyPriorPrecision;
    final looBaseline =
        (baselineResidualSum -
            shooterWeight * (shooter.rating - shooterScoreEvidence)) /
        baselinePrecision;
    final baselineVariance = 1.0 / baselinePrecision;

    double pairwiseResidual = 0.0;
    double pairwiseVariance = 0.0;
    int pairwiseOpponentCount = 0;
    if (settings.pairwiseBlendWeight > 0) {
      final pairwiseOpponents = _selectOpponents(shooter, scores, shooterRatio);
      pairwiseOpponentCount = pairwiseOpponents.length;

      double weightedResiduals = 0.0;
      double totalPairwiseWeight = 0.0;
      for (var opponent in pairwiseOpponents) {
        opponent as LatentLogRating;
        final opponentVariance = opponent.calculateCurrentVariance(
          asOfDate: matchDate,
        );
        final opponentScoreEvidence = competitorScoreEvidence[opponent];
        final opponentTailNoise = competitorTailNoise[opponent];
        if (opponentScoreEvidence == null || opponentTailNoise == null) {
          continue;
        }
        final residual =
            (shooterScoreEvidence - opponentScoreEvidence) -
            (shooter.rating - opponent.rating);
        final weight =
            1 /
            (opponentVariance +
                settings.sportVolatility +
                opponent.volatility +
                opponentTailNoise);
        weightedResiduals += residual * weight;
        totalPairwiseWeight += weight;
      }
      if (totalPairwiseWeight > 0) {
        pairwiseResidual = weightedResiduals / totalPairwiseWeight;
        pairwiseVariance = 1.0 / totalPairwiseWeight;
      }
    }

    var pairwiseBlendWeight = settings.pairwiseBlendWeight;
    if (pairwiseOpponentCount < 10) {
      pairwiseBlendWeight = lerpAroundCenter(
        value: pairwiseOpponentCount.toDouble(),
        center: (10 + 2) / 2,
        rangeMin: 2,
        rangeMax: 10,
        minOut: 0,
        centerOut: 1,
        maxOut: 1,
      );
    }

    final observedPerformance =
        shooterScoreEvidence +
        looBaseline +
        pairwiseBlendWeight * pairwiseResidual;
    var innovation = observedPerformance - shooter.rating;

    // Effective observation noise propagates uncertainty from the baseline
    // estimate and pairwise estimate into the Kalman filter, rather than
    // treating them as known quantities.
    final totalObsNoise =
        settings.sportVolatility +
        shooter.volatility +
        shooterTailNoise +
        baselineVariance +
        pairwiseBlendWeight * pairwiseBlendWeight * pairwiseVariance +
        weakFieldVariance;
    final totalNoise = shooterVariance + totalObsNoise;
    final zScore = innovation / sqrt(totalNoise);

    // Student-t robust weight: damp outlier innovations. The z-score is
    // now computed against observation noise only, so this is correctly calibrated.
    const nuMin = 2;
    const nuMax = 30;
    final nu = (nuMin + 0.5 * scores.length).clamp(nuMin, nuMax);
    final weight = min(1.0, (nu + 1) / (nu + zScore * zScore));
    final dampedInnovation = innovation * weight;

    final kalmanGain = shooterVariance / totalNoise;
    final newRating = shooter.rating + kalmanGain * dampedInnovation;

    final denoisedInnovationVariance = max(0, innovation * innovation - shooterVariance - settings.sportVolatility);

    final innovationCorrection =
        settings.surpriseAdaptationRate *
        max(0.0, denoisedInnovationVariance - totalNoise);
    final newVariance = min(
      settings.maximumVariance,
      shooterVariance * (1 - kalmanGain) + innovationCorrection,
    );

    final maxVolatility = settings.maximumVariance * _volatilityScaleFactor;

    // 1% of starting variance (i.e., 'minimal')—we don't want to use 1% of maximum
    // because maximum may be very liberal, and we want this to be more like
    // an epsilon than a meaningful limit.
    final minVolatility = 0.01 * settings.startingVariance * _volatilityScaleFactor;

    // Clamp observations to 3SD
    final maxInstantaneousVariance = max(
      9.0 * shooter.volatility,
      minVolatility
    );

    final clampedInstantaneousVariance = min(
      maxInstantaneousVariance,
      newVariance,
    );

    final certainty =
        1.0 - (shooterVariance / settings.maximumVariance).clamp(0.0, 1.0);
    final effectiveAdaptationRate = settings.volatilityAdaptationRate * max(0.25, certainty);
    final newVolatility =
        (shooter.volatility * (1 - effectiveAdaptationRate) +
                effectiveAdaptationRate * clampedInstantaneousVariance * _volatilityScaleFactor)
            .clamp(
              minVolatility,
              maxVolatility,
            );

    // Change is relative to the _committed_ variance, not the calculated current
    // variance-with-aging.
    final varianceChange = newVariance - shooter.variance;
    final volatilityChange = newVolatility - shooter.volatility;
    final displayVarianceChange = settings.scaleFactor * (sqrt(newVariance) - sqrt(shooter.variance));
    final displayVolatilityChange = settings.scaleFactor * (sqrt(newVolatility) - sqrt(shooter.volatility));
    final displayInnovationCorrection = settings.scaleFactor * (sqrt(newVariance + innovationCorrection) - sqrt(newVariance));

    final stagesForEvent = byStage ? 1.0 : match.stages.length.toDouble();

    return RatingChange(
      change: {
        RatingSystem.ratingChangeKey: newRating - shooter.rating,
        // Committed variance before this match (not time-aged). Matches
        // varianceChange so oldVariance + varianceChange is the new committed
        // variance on the event (charts / history).
        LatentLogRater.oldVarianceKey: shooter.variance,
        LatentLogRater.oldVolatilityKey: shooter.volatility,
        LatentLogRater.varianceChangeKey: varianceChange,
        LatentLogRater.volatilityChangeKey: volatilityChange,
        LatentLogRater.stagesKey: stagesForEvent,
      },
      infoLines: [
        "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
        "Rating ± Change: {{rating}}/{{change}}",
        "Variance ± Change: {{variance}}/{{varianceChange}} (+{{innovationCorrection}} surprise)",
        "Volatility ± Change: {{volatility}}/{{volatilityChange}}",
        "Considered {{opponents}} opponents",
      ],
      infoData: [
        RatingEventInfoElement.int(
          name: "finish",
          intValue: shooterScore.place,
        ),
        RatingEventInfoElement.int(
          name: "competitors",
          intValue: scores.length,
        ),
        RatingEventInfoElement.double(
          name: "finishPercent",
          doubleValue: shooterScore.percentage,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "rating",
          doubleValue: (newRating * settings.scaleFactor) + settings.scaleOffset,
          numberFormat: "%00.0f",
        ),
        RatingEventInfoElement.double(
          name: "change",
          doubleValue: (newRating - shooter.rating) * settings.scaleFactor,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "variance",
          doubleValue: sqrt(newVariance) * settings.scaleFactor,
          numberFormat: "%00.1f",
        ),
        RatingEventInfoElement.double(
          name: "varianceChange",
          doubleValue: displayVarianceChange,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "innovationCorrection",
          doubleValue: displayInnovationCorrection,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "volatility",
          doubleValue: sqrt(newVolatility) * settings.scaleFactor,
          numberFormat: "%00.1f",
        ),
        RatingEventInfoElement.double(
          name: "volatilityChange",
          doubleValue: displayVolatilityChange,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.int(
          name: "opponents",
          intValue: pairwiseOpponentCount,
        ),
      ],
    );
  }

  double _scoreEvidence(double ratio) {
    final boundedRatio = min(1.0, max(_scoreFloor, ratio));
    return log(boundedRatio);
  }

  double _tailObservationVariance(double ratio) {
    if (settings.tailNoiseVariance <= 0) {
      return 0.0;
    }

    final boundedRatio = min(1.0, max(_scoreFloor, ratio));
    final startPercent = min(
      0.999,
      max(_scoreFloor, settings.tailNoiseStartPercent),
    );
    if (boundedRatio >= startPercent) {
      return 0.0;
    }

    final normalizedDeficit = (startPercent - boundedRatio) / startPercent;
    return settings.tailNoiseVariance * normalizedDeficit * normalizedDeficit;
  }

  double _weakFieldObservationVariance(
    List<ShooterRating> shooters,
    Map<ShooterRating, RelativeScore> scores,
  ) {
    if (settings.weakFieldVariance <= 0 || shooters.length < 2) {
      return 0.0;
    }

    final maxSize = max(2.000001, settings.weakFieldMaxSize);
    if (shooters.length >= maxSize) {
      return 0.0;
    }

    final sizeFactor = (maxSize - shooters.length) / (maxSize - 2.0);
    if (sizeFactor <= 0) {
      return 0.0;
    }

    final weakThreshold = min(
      0.999,
      max(_scoreFloor, settings.weakFieldWeakFinishThreshold),
    );
    final weakFractionThreshold = min(
      0.999,
      max(0.0, settings.weakFieldWeakFractionThreshold),
    );
    final nonWinners = shooters
        .map((s) => scores[s])
        .whereType<RelativeScore>()
        .where((score) => score.place > 1)
        .toList();
    if (nonWinners.isEmpty) {
      return 0.0;
    }

    final weakNonWinners = nonWinners
        .where((score) => score.ratio < weakThreshold)
        .toList();
    final weakFraction = weakNonWinners.length / nonWinners.length;
    if (weakFraction < weakFractionThreshold) {
      return 0.0;
    }

    final weakGapThreshold = -log(weakThreshold);
    double meanExcessWeakGap = 0.0;
    for (var weakScore in weakNonWinners) {
      meanExcessWeakGap += max(
        0.0,
        -log(max(_scoreFloor, weakScore.ratio)) - weakGapThreshold,
      );
    }
    meanExcessWeakGap /= weakNonWinners.length;

    final severityFactor = min(1.0, meanExcessWeakGap / weakGapThreshold);
    return settings.weakFieldVariance *
        sizeFactor *
        weakFraction *
        severityFactor;
  }

  double _huberWeight(double absZ, double threshold) {
    if (threshold <= 0 || absZ <= threshold) {
      return 1.0;
    }
    return threshold / absZ;
  }

  double get _matchDifficultyPriorPrecision {
    if (settings.matchDifficultyVariance <= 0) {
      return 0.0;
    }
    return 1.0 / settings.matchDifficultyVariance;
  }

  List<ShooterRating> _selectOpponents(
    LatentLogRating shooter,
    Map<ShooterRating, RelativeScore> scores,
    double shooterRatio,
  ) {
    var opponentsByFinish = scores.keys.toList();
    var opponentsByRating = opponentsByFinish
        .sorted((a, b) => b.rating.compareTo(a.rating))
        .toList();

    // For now, Latent Log Ratio only does top-and-nearby.
    Set<ShooterRating> selected = {};
    selected.addAll(
      _selectTop10PctOpponents(opponentsByFinish, opponentsByRating),
    );
    selected.addAll(
      _selectNearbyOpponents(shooter, scores, opponentsByRating, shooterRatio),
    );
    return selected.toList();
  }

  List<ShooterRating> _selectTop10PctOpponents(
    List<ShooterRating> opponentsByFinish,
    List<ShooterRating> opponentsByRating,
  ) {
    var percentToTake = 0.1;
    if (opponentsByFinish.length < 10) {
      percentToTake = 0.3;
    }
    var top10Pct = (opponentsByFinish.length * percentToTake).ceil();
    var top10PctByMatchFinish = opponentsByFinish.take(top10Pct).toSet();

    var sortedByRating = (opponentsByRating.length * percentToTake).ceil();
    var top10PctByRating = opponentsByRating.take(sortedByRating).toSet();

    top10PctByMatchFinish.addAll(top10PctByRating);
    return top10PctByMatchFinish.toList();
  }

  List<ShooterRating> _selectNearbyOpponents(
    LatentLogRating shooter,
    Map<ShooterRating, RelativeScore> scores,
    List<ShooterRating> opponentsByRating,
    double competitorRatio,
  ) {
    double margin = 0.1;
    if (opponentsByRating.length < 10) {
      margin = 0.25;
    }

    Set<ShooterRating> nearbyOpponents = {};
    final topRatio = competitorRatio * (1 + margin);
    final bottomRatio = competitorRatio * (1 - margin);
    for (var opponent in scores.keys) {
      // Players with no rating history don't have a valid rating yet, so 'nearby' in rating terms
      // isn't meaningful yet.
      if (opponent.length == 0) {
        continue;
      }

      if ((opponent.rating - shooter.rating).abs() <=
          settings.startingVariance) {
        nearbyOpponents.add(opponent);
        continue;
      }

      var opponentScore = scores[opponent];
      if (opponentScore == null) {
        continue;
      }
      var opponentRatio = opponentScore.ratio;
      if (opponentRatio >= bottomRatio && opponentRatio <= topRatio) {
        nearbyOpponents.add(opponent);
      }
    }

    return nearbyOpponents.toList();
  }

  // Below: predictions

  @override
  bool get supportsPrediction => true;

  @override
  PredictionSettings get predictionSettings => PredictionSettings(
    placeSigmaMultiplier: 1,
    percentSigmaMultiplier: 1,
    spreadSigmaMultiplier: 1,
    outputsAreRatios: true,
  );

  @override
  bool get predictionsOutputRatios => true;

  @override
  List<AlgorithmPrediction> predict(List<ShooterRating> ratings, {int? seed, DateTime? matchDate}) {
    List<AlgorithmPrediction> predictions = [];

    List<LatentLogRating> sortedRatings = ratings.cast<LatentLogRating>().sorted((a, b) => b.rating.compareTo(a.rating));

    List<_PresumedWinnerPrediction> presumedWinners = _presumedWinnersClosedForm(sortedRatings);

    for(var rating in sortedRatings) {
      /// We use the probability-weighted log ratio to calculate the median
      /// log ratio, so that we can correctly center the confidence interval.
      ///
      /// It is the expected log difference from the competitor's rating to the
      /// presumed winners' ratings, weighted by the presumed winner's win
      /// probability.
      ///
      /// This is their sum (i.e. their weighted average by win probability).
      double probabilityWeightedLogDifference = 0.0;

      /// The probability-weighted ratios are the expected final scores in ratio
      /// space for the competitor against each presumed winner, weighted by the
      /// presumed winner's win probability.
      ///
      /// This is their sum (i.e. their weighted average by win probability).
      double probabilityWeightedRatio = 0.0;

      /// The probability-weighted winner rating variance, used for the
      /// prediction band.
      double probabilityWeightedWinnerVariance = 0.0;

      /// Probability-weighted sum of presumed winners' behavioral variances
      /// (same weighting as [probabilityWeightedWinnerVariance]).
      double probabilityWeightedWinnerExcessVolatility = 0.0;

      for(var presumedWinner in presumedWinners) {
        final winProbability = presumedWinner.winProbability;

        final logDifference = rating.rating - presumedWinner.shooter.rating;
        probabilityWeightedLogDifference += logDifference * winProbability;

        final winnerVariance =
          matchDate != null ?
            presumedWinner.shooter.variance : //presumedWinner.shooter.calculateCurrentVariance(asOfDate: matchDate) :
            presumedWinner.shooter.variance;

        final correctionTerm = (winnerVariance + settings.sportVolatility) / 2;
        final weightedRatio = exp(logDifference + correctionTerm) * winProbability;
        probabilityWeightedRatio += weightedRatio;
        probabilityWeightedWinnerVariance += winnerVariance * winProbability;
        probabilityWeightedWinnerExcessVolatility +=
            max(0, presumedWinner.shooter.volatility - presumedWinner.shooter.variance) * winProbability;
      }

      final ratingVariance =
        matchDate != null ?
          rating.variance : //rating.calculateCurrentVariance(asOfDate: matchDate) :
          rating.variance;
      final kappa = settings.predictionBehavioralVolatilityKappa;
      final ratingExcessVolatility = max(0, rating.volatility - rating.variance);
      final predictiveVariance =
        ratingVariance
        + 2 * settings.predictionSportVariance
        + probabilityWeightedWinnerVariance
        + (ratingExcessVolatility + probabilityWeightedWinnerExcessVolatility) * kappa;

      final oneSigmaUpper = exp(probabilityWeightedLogDifference + sqrt(predictiveVariance));
      final oneSigma = oneSigmaUpper - probabilityWeightedRatio;

      // We'll fill in places in a second pass
      predictions.add(AlgorithmPrediction(
        shooter: rating,
        mean: probabilityWeightedRatio,
        sigma: oneSigma,
        settings: settings,
        algorithm: this,
        meanRatio: probabilityWeightedRatio,
        oneSigmaRatio: oneSigma,
        shiftRatio: 0.0,
      ));
    }

    var sortedPredictions = predictions.sorted((a, b) => b.mean.compareTo(a.mean));
    for(var (centerPlace, prediction) in sortedPredictions.indexed) {
      prediction.medianPlace = centerPlace + 1;
      bool hasBestPlace = false;
      bool hasWorstPlace = false;
      for(var (i, other) in sortedPredictions.indexed) {
        if(prediction == other) {
          continue;
        }

        if(other.mean > prediction.highPrediction) {
          prediction.highPlace = i + 1;
          hasBestPlace = true;
        }
        if(other.mean > prediction.lowPrediction) {
          prediction.lowPlace = i + 1;
          hasWorstPlace = true;
        }
      }
      if(!hasBestPlace) {
        prediction.highPlace = centerPlace + 1;
      }
      if(!hasWorstPlace) {
        prediction.lowPlace = centerPlace + 1;
      }
    }

    return predictions;
  }

  List<_PresumedWinnerPrediction> _presumedWinnersClosedForm(List<LatentLogRating> sortedRatings, {DateTime? matchDate}) {
    List<_PresumedWinnerPrediction> predictions = [];
    // Take the top 10% or top 3 if there are fewer than 30 ratings.
    int topN = (sortedRatings.length * 0.25).ceil();
    if (topN < 5) {
      topN = 5;
    }
    List<LatentLogRating> topRatings = sortedRatings.take(topN).toList();

    // For each top rating, calculate the expected percentage.
    for (var rating in topRatings) {
      final ratingVariance =
        matchDate != null ?
          rating.calculateCurrentVariance(asOfDate: matchDate) :
          rating.variance;
      List<double> pairwiseProbabilities = [];
      for (var opponent in sortedRatings) {
        if (opponent == rating) {
          continue;
        }

        final opponentVariance =
          matchDate != null ?
            opponent.calculateCurrentVariance(asOfDate: matchDate) :
            opponent.variance;

        double numerator = rating.rating - opponent.rating;
        // all properties are in variance units

        double denominator = sqrt(
          ratingVariance
          + opponentVariance
          + 2 * settings.predictionSportVariance
        );

        double probability = Normal.cdf(numerator / denominator);
        pairwiseProbabilities.add(probability);
      }
      double winProbability = pairwiseProbabilities.reduce((a, b) => a * b);
      predictions.add(_PresumedWinnerPrediction(shooter: rating, winProbability: winProbability));
    }

    return _PresumedWinnerPrediction.normalize(predictions);
  }

  List<_PresumedWinnerPrediction> _presumedWinnersMonteCarlo(List<ShooterRating> sortedRatings) {
    throw UnimplementedError();
  }

}

/// The probability that a given competitor is the presumed winner of the match, for the purposes
/// of generating a winner mixture for predictions.
class _PresumedWinnerPrediction {
  final LatentLogRating shooter;
  final double winProbability;

  _PresumedWinnerPrediction({
    required this.shooter,
    required this.winProbability,
  });

  /// Normalize so that all probabilities sum to 1.
  static List<_PresumedWinnerPrediction> normalize(List<_PresumedWinnerPrediction> predictions) {
    double totalProbability = predictions.map((p) => p.winProbability).sum;
    _log.v("Total probability before normalization: $totalProbability");
    return predictions.map((p) => _PresumedWinnerPrediction(shooter: p.shooter, winProbability: p.winProbability / totalProbability)).toList();
  }
}