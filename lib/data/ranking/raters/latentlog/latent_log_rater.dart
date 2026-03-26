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
  static const _dispersionScaleFactor = 1.0;
  static const _predictionsUseAgedRatings = true;
  /// A cap on the number of days to age a rating for predictions.
  static const _predictionsAgeCapDays = 90;
  static const _predictionsUseMonteCarlo = true;
  static const _predictionsMonteCarloTrials = 2000;

  static const oldVarianceKey = "latentLogOldVariance";
  static const oldDispersionKey = "latentLogOldDispersion";
  static const varianceChangeKey = "latentLogVarianceChange";
  static const dispersionChangeKey = "latentLogDispersionChange";
  static const momentumChangeKey = "latentLogMomentumChange";
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
  double scaleRating(double rating) {
    return rating * settings.scaleFactor + settings.scaleOffset;
  }

  double unscaleRating(double rating) {
    return (rating - settings.scaleOffset) / settings.scaleFactor;
  }

  @override
  String formatNumericRating(double rating) {
    return (rating * settings.scaleFactor + settings.scaleOffset).round().toString();
  }

  @override
  String formatRating(ShooterRating rating) {
    return formatNumericRating(rating.rating);
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
      oldDispersion: rating.dispersion,
      oldMomentum: rating.momentum,
      varianceChange: 0.0,
      dispersionChange: 0.0,
      momentumChange: 0.0,
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
    double initialRating = 0;

    var ratingMultiplier = sport.initialGenericRatingMultipliers[shooter.classification] ?? 1.0;
    if(ratingMultiplier != 1.0) {
      // LLR ratings are literally just log performance multipliers/ratios, so we can use the
      // multiplier almost directly.
      // Soften it significantly compared to the actual multiplier to better fit observed behavior
      var differenceFromOne = ratingMultiplier - 1.0;
      differenceFromOne /= 3;
      final softMultiplier = 1.0 + differenceFromOne;
      initialRating = log(softMultiplier);
      // initialRating = log(ratingMultiplier);
    }

    return LatentLogRating(
      shooter,
      sport: sport,
      date: date,
      initialRating: initialRating,
      initialVariance: settings.startingVariance,
      initialDispersion: settings.startingDispersion,
      settings: settings,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating<RatingEvent>> ratings) {
    StringBuffer csv = StringBuffer();
    csv.writeln("Member#,Name,Rating,Variance,Dispersion,Matches,Stages");
    for (var r in ratings) {
      r as LatentLogRating;
      csv.writeln(
        '${r.memberNumber},"${r.name}",${r.rating},${r.variance},${r.dispersion},${r.lengthInMatches},${r.lengthInStages}',
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
    double baselineVarianceSum = 0.0;
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
              settings.sportVariance +
              shooter.dispersion +
              tailNoise);

      competitorWeights[shooter] = weight;      baselineVarianceSum += weight * shooterVariance;
      baselineVarianceSum += weight * shooterVariance;
      totalWeight += weight;

      final residual = shooter.rating - scoreEvidence;
      competitorBaselineResiduals[shooter] = residual;
      baselineResidual += weight * residual;
    }

    // If baseline robustness is enabled, apply a Huber-style taper to
    // the baseline weights to downweight extreme outliers.
    if (totalWeight > 0 && settings.baselineRobustnessZ > 0) {
      // Recalculate with robust weights
      baselineVarianceSum = 0.0;

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

        baselineVarianceSum += effectiveWeight * competitorVariances[shooter]!;

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
        baselineVarianceSum: baselineVarianceSum,
        totalBaselineWeight: totalWeight,
        weakFieldVariance: weakFieldVariance,
        validScoresCount: validShooters.length,
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

    /// The weighted sum of the baseline variances.
    required double baselineVarianceSum,

    /// The total weight of the baseline.
    required double totalBaselineWeight,

    /// The weak field observation variance.
    required double weakFieldVariance,

    /// The number of valid scores.
    required int validScoresCount,

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
    final looVariance = baselineVarianceSum - (shooterVariance * shooterWeight);

    final opponentCount = validScoresCount - 1;
    final fieldAverageUncertaintyTaper = (opponentCount - 1) / opponentCount;
    final fieldAverageUncertainty = looVariance / looWeight * fieldAverageUncertaintyTaper;

    final baselinePrecision = looWeight + _matchDifficultyPriorPrecision;
    final looBaseline =
        (baselineResidualSum -
            shooterWeight * (shooter.rating - shooterScoreEvidence)) /
        baselinePrecision;
    final baselineVariance = 1.0 / baselinePrecision + settings.intraclassCorrelation * fieldAverageUncertainty;

    // if(fieldAverageUncertainty > baselineVariance) {
    //   _log.w("Match ${match.name} with $opponentCount opponents has "
    //   "field average uncertainty ${fieldAverageUncertainty.toStringAsPrecision(2)} > "
    //   "baseline variance ${baselineVariance.toStringAsPrecision(2)}");
    // }

    double localBaseline = 0.0;
    double localBaselineWeight = 0.0;
    double localBaselineVariance = 0.0;
    double localBaselineVarianceSum = 0.0;
    int pairwiseOpponentCount = 0;

    // Pairwise blending, conditioned on at least [weak field max size] opponents.
    if (settings.pairwiseBlendWeight > 0 && validScoresCount >= settings.weakFieldMaxSize) {
      final pairwiseOpponents = _selectOpponents(shooter, scores, shooterRatio);
      pairwiseOpponentCount = pairwiseOpponents.length;

      for (var opponent in pairwiseOpponents) {
        opponent as LatentLogRating;
        // Competitor's contribution to the numerator and denominator of B_local.
        final opponentScoreEvidence = competitorScoreEvidence[opponent];
        final opponentTailNoise = competitorTailNoise[opponent];
        final opponentWeight = competitorWeights[opponent];
        final opponentAgedVariance = opponent.calculateCurrentVariance(asOfDate: matchDate);
        if (opponentScoreEvidence == null || opponentTailNoise == null || opponentWeight == null) {
          _log.e("Missing parameter for pairwise blending: $shooter vs $opponent");
          continue;
        }
        final opponentBaselineResidual = opponent.rating - opponentScoreEvidence;
        final baselineContribution = opponentWeight * opponentBaselineResidual;
        final weightContribution = opponentWeight;

        localBaseline += baselineContribution;
        localBaselineWeight += weightContribution;
        localBaselineVarianceSum += weightContribution * opponentAgedVariance;
      }

      if (localBaselineWeight > 0) {
        final localBaselineUncertainty = localBaselineVarianceSum / localBaselineWeight;

        final localTaper = (pairwiseOpponentCount - 1) / pairwiseOpponentCount;
        localBaseline /= localBaselineWeight;
        localBaselineVariance = 1.0 / localBaselineWeight + settings.intraclassCorrelation * localTaper * localBaselineUncertainty;
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
        (1 - pairwiseBlendWeight) * looBaseline +
        pairwiseBlendWeight * localBaseline;
    var innovation = observedPerformance - shooter.rating;

    var pairwiseBlendWeightSquared = pairwiseBlendWeight * pairwiseBlendWeight;

    // How certain are we about the shooter's variance? If we're not very
    // certain, we can neither use nor update the dispersion by very much—
    // we don't know if we're varying around the mean because we don't know
    // where the mean is.
    final dispersionCertainty =
        1.0 - (shooterVariance / settings.maximumVariance).clamp(0.0, 1.0);

    // Effective observation noise propagates uncertainty from the baseline
    // estimate and pairwise estimate into the Kalman filter, rather than
    // treating them as known quantities.
    final totalObsNoise =
        settings.sportVariance +
        dispersionCertainty * shooter.dispersion +
        shooterTailNoise +
        weakFieldVariance +
        (1 - pairwiseBlendWeightSquared) * baselineVariance +
        pairwiseBlendWeightSquared * localBaselineVariance;
    final totalNoise = shooterVariance + totalObsNoise;
    final zScore = innovation / sqrt(totalNoise);

    // Student-t robust weight: damp outlier innovations.
    const nuMin = 2;
    const nuMax = 30;
    final nu = (nuMin + 0.5 * scores.length).clamp(nuMin, nuMax);
    final weight = min(1.0, (nu + 1) / (nu + zScore * zScore));
    final dampedInnovation = innovation * weight;

    final kalmanGain = shooterVariance / totalNoise;
    final newRating = shooter.rating + kalmanGain * dampedInnovation;

    // Use the stronger of surprise or momentum to add to variance.
    final surpriseCorrection = (innovation * innovation) - totalNoise;
    final momentumCorrection = (shooter.momentum * shooter.momentum) / settings.momentumAdaptationRate;
    final strongerCorrection = max(surpriseCorrection, momentumCorrection);

    final innovationCorrection =
        settings.surpriseAdaptationRate *
        max(0.0, strongerCorrection);
    final newVariance = min(
      settings.maximumVariance,
      shooterVariance * (1 - kalmanGain) + innovationCorrection,
    );

    final maximumDispersion = settings.maximumVariance * _dispersionScaleFactor;

    // 0.1% of starting variance (i.e., 'minimal')—we don't want to use 1% of maximum
    // because maximum may be very liberal, and we want this to be more like
    // an epsilon than a meaningful limit.
    final minimumDispersion = 0.001 * settings.startingVariance * _dispersionScaleFactor;

    // Clamp observations to 3SD
    final maxInstantaneousVariance = max(
      9.0 * shooter.dispersion,
      minimumDispersion
    );

    // Aleatoric noise (dispersion) is the portion of innovation not explained by:
    // 1. variance.
    final denoisedInnovationVariance = max(0, pow(innovation - shooter.momentum, 2) - shooterVariance - settings.sportVariance);
    final clampedInstantaneousVariance = denoisedInnovationVariance.clamp(minimumDispersion, maxInstantaneousVariance);

    final effectiveDispersionAdaptationRate = settings.dispersionAdaptationRate * max(0.25, dispersionCertainty);
    final newDispersion =
        (shooter.dispersion * (1 - effectiveDispersionAdaptationRate) +
        effectiveDispersionAdaptationRate * clampedInstantaneousVariance * _dispersionScaleFactor)
        .clamp(
          minimumDispersion,
          maximumDispersion,
        );

    // Momentum is a signed EMA over innovation.
    final effectiveMomentumAdaptationRate = settings.momentumAdaptationRate * max(0.25, dispersionCertainty);
    final newMomentum = shooter.momentum * (1 - effectiveMomentumAdaptationRate) +
        effectiveMomentumAdaptationRate * innovation;

    // Change is relative to the _committed_ variance, not the calculated current
    // variance-with-aging.
    final varianceChange = newVariance - shooter.variance;
    final dispersionChange = newDispersion - shooter.dispersion;
    final momentumChange = newMomentum - shooter.momentum;

    final displayVarianceChange = settings.scaleFactor * (sqrt(newVariance) - sqrt(shooter.variance));
    final displayDispersionChange = settings.scaleFactor * (sqrt(newDispersion) - sqrt(shooter.dispersion));
    final displayMomentumChange = settings.scaleFactor * momentumChange;

    final undriftedVariance = shooter.variance;

    final displayVarianceFromMomentum = settings.scaleFactor * (sqrt(undriftedVariance + max(0, momentumCorrection * settings.surpriseAdaptationRate)) - sqrt(undriftedVariance));
    final displayVarianceFromSurprise = settings.scaleFactor * (sqrt(undriftedVariance + max(0, surpriseCorrection * settings.surpriseAdaptationRate)) - sqrt(undriftedVariance));

    final displayInnovationCorrection = settings.scaleFactor * (sqrt(undriftedVariance + innovationCorrection) - sqrt(undriftedVariance));

    final stagesForEvent = byStage ? 1.0 : match.stages.length.toDouble();

    return RatingChange(
      change: {
        RatingSystem.ratingChangeKey: newRating - shooter.rating,
        // Committed variance before this match (not time-aged). Matches
        // varianceChange so oldVariance + varianceChange is the new committed
        // variance on the event (charts / history).
        LatentLogRater.oldVarianceKey: shooter.variance,
        LatentLogRater.oldDispersionKey: shooter.dispersion,
        LatentLogRater.varianceChangeKey: varianceChange,
        LatentLogRater.dispersionChangeKey: dispersionChange,
        LatentLogRater.momentumChangeKey: momentumChange,
        LatentLogRater.stagesKey: stagesForEvent,
      },
      infoLines: [
        "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
        "Rating ± Change: {{rating}}/{{change}}",
        "Momentum ± Change: {{momentum}}/{{momentumChange}}",
        "Variance ± Change: {{variance}}/{{varianceChange}} (+{{innovationCorrection}} mods)",
        "Change from surprise/momentum: {{surpriseCorrection}}/{{momentumCorrection}}",
        "Dispersion ± Change: {{dispersion}}/{{dispersionChange}}",
        "Considered {{opponents}} opponents",
        "Global/local baseline: {{globalBaseline}}/{{localBaseline}}",
        "Own variance (time drift): {{ownVariance}} ({{timeVariance}}) SV",
        "Own dispersion: {{ownDispersion}} SV",
        "Tail noise/weak field: {{tailNoise}}/{{weakField}} SV",
        "Global/local noise: {{globalBaselineNoise}}/{{localBaselineNoise}} SV",
        "Observation/total noise: {{observationNoise}}/{{totalNoise}} SV",
        "z-score/damping/Kalman gain: {{innovationZScore}}/{{weight}}x/{{kalmanGain}}",
        "Raw/damped innovation: {{innovation}}/{{dampedInnovation}}",
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
          name: "timeVariance",
          doubleValue: (shooterVariance - shooter.variance) / settings.sportVariance,
          numberFormat: "%00.3f",
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
          name: "dispersion",
          doubleValue: sqrt(newDispersion) * settings.scaleFactor,
          numberFormat: "%00.1f",
        ),
        RatingEventInfoElement.double(
          name: "dispersionChange",
          doubleValue: displayDispersionChange,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.int(
          name: "opponents",
          intValue: pairwiseOpponentCount,
        ),
        RatingEventInfoElement.double(
          name: "observationNoise",
          doubleValue: totalObsNoise / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "totalNoise",
          doubleValue: totalNoise / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "tailNoise",
          doubleValue: shooterTailNoise / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "weakField",
          doubleValue: weakFieldVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "globalBaseline",
          doubleValue: looBaseline,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "localBaseline",
          doubleValue: localBaseline,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "globalBaselineNoise",
          doubleValue: baselineVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "localBaselineNoise",
          doubleValue: localBaselineVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "ownVariance",
          doubleValue: shooterVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "ownDispersion",
          doubleValue: shooter.dispersion / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "innovationZScore",
          doubleValue: zScore,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "kalmanGain",
          doubleValue: kalmanGain,
          numberFormat: "%00.4f",
        ),
        RatingEventInfoElement.double(
          name: "weight",
          doubleValue: weight,
          numberFormat: "%00.4f",
        ),
        RatingEventInfoElement.double(
          name: "dampedInnovation",
          doubleValue: dampedInnovation,
          numberFormat: "%00.4f",
        ),
        RatingEventInfoElement.double(
          name: "innovation",
          doubleValue: innovation,
          numberFormat: "%00.4f",
        ),
        RatingEventInfoElement.double(
          name: "momentum",
          doubleValue: newMomentum * settings.scaleFactor,
          numberFormat: "%00.1f",
        ),
        RatingEventInfoElement.double(
          name: "momentumChange",
          doubleValue: displayMomentumChange,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "surpriseCorrection",
          doubleValue: displayVarianceFromSurprise,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "momentumCorrection",
          doubleValue: displayVarianceFromMomentum,
          numberFormat: "%00.2f",
        ),
      ],
    );
  }

  double _scoreEvidence(double ratio) {
    final boundedRatio = ratio.clamp(_scoreFloor, 1.0);
    return log(boundedRatio);
  }

  double _tailObservationVariance(double ratio) {
    if (settings.tailNoiseVariance <= 0) {
      return 0.0;
    }

    final boundedRatio = ratio.clamp(_scoreFloor, 1.0);
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
    var opponentsToTake = (opponentsByFinish.length * percentToTake).ceil();
    if(opponentsToTake < 3) {
      opponentsToTake = 3;
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
    if(matchDate != null && _predictionsUseAgedRatings && _predictionsAgeCapDays > 0) {
      if(matchDate.difference(DateTime.now()).inDays > _predictionsAgeCapDays) {
        matchDate = DateTime.now().add(Duration(days: _predictionsAgeCapDays));
        _log.i("Capping time-to-match to $_predictionsAgeCapDays days, new date $matchDate");
      }
    }

    List<AlgorithmPrediction> predictions = [];

    List<LatentLogRating> sortedRatings = ratings.cast<LatentLogRating>().where((r) => r.length > 0).sorted((a, b) => b.rating.compareTo(a.rating));

    if(sortedRatings.isEmpty) {
      return [];
    }

    if(sortedRatings.length < 2) {
      return [
        AlgorithmPrediction(
          shooter: sortedRatings[0],
          mean: 1.0,
          sigma: 0.0,
          settings: settings,
          algorithm: this,
          meanRatio: 1.0,
          oneSigmaRatio: 0.0,
          lowPlace: 1,
          highPlace: 1,
          medianPlace: 1,
        ),
      ];
    }

    List<_PresumedWinnerPrediction> presumedWinners = _predictionsUseMonteCarlo ?
      _presumedWinnersMonteCarlo(sortedRatings, matchDate: _predictionsUseAgedRatings ? matchDate : null) :
      _presumedWinnersClosedForm(sortedRatings, matchDate: _predictionsUseAgedRatings ? matchDate : null);

    for(var rating in sortedRatings) {
      /// The probability-weighted ratios are the expected final scores in ratio
      /// space for the competitor against each presumed winner, weighted by the
      /// presumed winner's win probability.
      ///
      /// This is their sum (i.e. their weighted average by win probability).
      double probabilityWeightedRatio = 0.0;

      /// The probability-weighted log difference between the competitor and the
      /// presumed winners, i.e. the component of the between-component variance
      /// multiplied by p_i.
      double probabilityWeightedLogDifference = 0.0;

      /// The win probability and log difference between the competitor and each
      /// presumed winner, i.e. the components of [probabilityWeightedLogDifference],
      /// i.e. the components of the between-component variance that occur in the
      /// sum and are weighted by p_w.
      List<({double pW, double muIW})> probabilityWeightedLogDifferences = [];

      /// The probability-weighted winner rating variance, used for the
      /// prediction band.
      double probabilityWeightedWinnerVariance = 0.0;

      /// Probability-weighted sum of presumed winners' behavioral variances
      /// (same weighting as [probabilityWeightedWinnerVariance]).
      double probabilityWeightedWinnerDispersion = 0.0;

      /// The win probability of the focal competitor as the presumed winner.
      double ownPresumedWinProbability = 0.0;

      final ratingVariance =
        matchDate != null && _predictionsUseAgedRatings ?
          rating.calculateCurrentVariance(asOfDate: matchDate) : //rating.variance :
          rating.variance;

      // Account for the tendency for extreme values to dominate in close fields.
      // i.e., if you have 10 evenly-matched competitors favored, the winner is the
      // one who has a +2SD day (more or less). Tight fields implement the winner's
      // curse: you'll do worse than you would against a simple weighted mean because
      // the winner _must_ shoot better than the mean to beat his peers.
      double sumOfSquaredWinProbabilities = 0.0;
      for(var p in presumedWinners) {
        sumOfSquaredWinProbabilities += p.winProbability * p.winProbability;
      }
      final nEff = 1.0 / sumOfSquaredWinProbabilities;
      final eMax = Normal.quantile((nEff - 0.375) / (nEff + 0.25));

      final kappa = settings.predictionBehavioralDispersionKappa;

      for(var presumedWinner in presumedWinners) {
        final winProbability = presumedWinner.winProbability;

        if(rating == presumedWinner.shooter) {
          // probabilityWeightedLogDifference += 0.0;

          // We contribute 1.0 * p_w to the ratio (i.e. we finish at exactly 100% of ourself by
          // definition)
          ownPresumedWinProbability = presumedWinner.winProbability;
          probabilityWeightedRatio += 1.0 * presumedWinner.winProbability;
          continue;
        }

        final winnerDrawStdDev = sqrt(
          presumedWinner.shooter.variance +
          kappa * presumedWinner.shooter.dispersion +
          settings.predictionSportVariance
        );
        final effectiveWinnerRating = presumedWinner.shooter.rating + winnerDrawStdDev * eMax;

        final logDifference = rating.rating - effectiveWinnerRating;
        probabilityWeightedLogDifference += logDifference * winProbability;
        probabilityWeightedLogDifferences.add((pW: winProbability, muIW: logDifference));

        final winnerVariance =
          matchDate != null && _predictionsUseAgedRatings ?
            presumedWinner.shooter.calculateCurrentVariance(asOfDate: matchDate) :
            presumedWinner.shooter.variance;

        final pairwiseVariance = winnerVariance + ratingVariance + 2 * settings.predictionSportVariance;

        final truncationCorrectionNumerator = -((logDifference + pairwiseVariance) / sqrt(pairwiseVariance));
        final truncationCorrectionDenominator = -(logDifference / sqrt(pairwiseVariance));
        final truncationCorrection = Normal.cdf(truncationCorrectionNumerator) / Normal.cdf(truncationCorrectionDenominator);

        final correctionTerm = pairwiseVariance / 2;
        final weightedRatio = exp(logDifference + correctionTerm) * truncationCorrection * winProbability;
        probabilityWeightedRatio += weightedRatio;
        probabilityWeightedWinnerVariance += winnerVariance * winProbability;
        probabilityWeightedWinnerDispersion +=
            presumedWinner.shooter.dispersion * winProbability;
      }

      double betweenComponentVariance = ownPresumedWinProbability * probabilityWeightedLogDifference * probabilityWeightedLogDifference;
      for(var (pW: double winProbability, muIW: double logDifference) in probabilityWeightedLogDifferences) {
        betweenComponentVariance += winProbability * pow(logDifference - probabilityWeightedLogDifference, 2);
      }

      final notWinnerProbability = 1.0 - ownPresumedWinProbability;
      final withinComponentVariance =
        notWinnerProbability * (
          ratingVariance +
          2 * settings.predictionSportVariance
          + (rating.dispersion * kappa)
        )
        + probabilityWeightedWinnerVariance
        + probabilityWeightedWinnerDispersion * kappa;

      final geometricSD = exp(sqrt(withinComponentVariance + betweenComponentVariance));
      final oneSigmaUpper = probabilityWeightedRatio * geometricSD;
      final oneSigma = oneSigmaUpper - probabilityWeightedRatio;

      if(probabilityWeightedRatio > 0.8) {
        _log.v("Rating: $rating");
        _log.v("Expectation/1σ:\t\t${probabilityWeightedRatio.toStringAsFixed(8)} / ${oneSigma.toStringAsFixed(8)}");
        if(ownPresumedWinProbability > 0.0) {
          _log.v("Own presumed p_w:\t\t${ownPresumedWinProbability.toStringAsFixed(8)}");
        }
        _log.v("Predictive variance:\t\t${withinComponentVariance.toStringAsFixed(8)}");
        _log.v("Rating variance:\t\t${ratingVariance.toStringAsFixed(8)}");
        _log.v("Variance age component:\t${(ratingVariance - rating.variance).toStringAsFixed(8)}");
        _log.v("Prediction sport variance:\t${(2 * settings.predictionSportVariance).toStringAsFixed(8)}");
        _log.v("Weighted winner variance::\t${probabilityWeightedWinnerVariance.toStringAsFixed(8)}");
        _log.v("Weighted rating dispersion:\t${(rating.dispersion * kappa).toStringAsFixed(8)}");
        _log.v("Weighted winner dispersion:\t${(probabilityWeightedWinnerDispersion * kappa).toStringAsFixed(8)}");
        _log.v("Kappa: \t\t\t${kappa.toStringAsFixed(2)}");
        _log.v("");
      }

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

    if(topRatings.length < 2) {
      return [
        _PresumedWinnerPrediction(shooter: topRatings[0], winProbability: 1.0),
      ];
    }

    // For each top rating, calculate the expected percentage.
    for (var rating in topRatings) {
      final ratingVariance =
        matchDate != null && _predictionsUseAgedRatings ?
          rating.calculateCurrentVariance(asOfDate: matchDate) : //rating.variance :
          rating.variance;
      List<double> pairwiseProbabilities = [];
      for (var opponent in sortedRatings) {
        if (opponent == rating) {
          continue;
        }

        final opponentVariance =
          matchDate != null && _predictionsUseAgedRatings ?
            opponent.calculateCurrentVariance(asOfDate: matchDate) : //opponent.variance :
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

  List<_PresumedWinnerPrediction> _presumedWinnersMonteCarlo(List<LatentLogRating> sortedRatings, {DateTime? matchDate, Random? random}) {
    random ??= Random();
    const trials = _predictionsMonteCarloTrials;
    List<_PresumedWinnerPrediction> predictions = [];

    if(sortedRatings.length < 2) {
      return [
        _PresumedWinnerPrediction(shooter: sortedRatings[0], winProbability: 1.0),
      ];
    }

    // Top quarter of the field, minimum 25.
    int depth = sortedRatings.length;
    if(sortedRatings.length > 100) {
      depth = sortedRatings.length ~/ 4;
    }

    Map<LatentLogRating, int> wins = {};
    for(int i = 0; i < trials; i++) {
      double bestRating = double.negativeInfinity;
      late LatentLogRating bestCompetitor;
      for(var (index, rating) in sortedRatings.indexed) {
        final currentVariance = matchDate != null && _predictionsUseAgedRatings ?
          rating.calculateCurrentVariance(asOfDate: matchDate) : //rating.variance :
          rating.variance;
        if(index > depth) {
          break;
        }
        var draw = random.nextGaussianWithParams(mu: rating.rating, sigma: sqrt(currentVariance + settings.predictionSportVariance));
        if(draw > bestRating) {
          bestRating = draw;
          bestCompetitor = rating;
        }
      }
      wins.increment(bestCompetitor);
    }

    for(final MapEntry(key: rating, value: wins) in wins.entries) {
      final probability = wins / trials;
      if(probability > 0.005) {
        predictions.add(_PresumedWinnerPrediction(shooter: rating, winProbability: probability));
      }
    }

    return _PresumedWinnerPrediction.normalize(predictions);
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