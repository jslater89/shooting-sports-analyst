/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_system_ui_data.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
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

  @override
  List<RatingSortMode> get supportedSorts => [
    RatingSortMode.agedRating,
    RatingSortMode.rating,
    RatingSortMode.lastChange,
    RatingSortMode.classification,
    RatingSortMode.error,
    RatingSortMode.dispersion,
    RatingSortMode.trend,
    RatingSortMode.stages,
    RatingSortMode.firstName,
    RatingSortMode.lastName,
  ];

  static LatentLogRater fromJson(Map<String, dynamic> json) {
    var settings = LatentLogSettings();
    settings.loadFromJson(json);
    return LatentLogRater(settings: settings);
  }

  @override
  double scaleRating(double rating) {
    return rating * settings.scaleFactor + settings.scaleOffset;
  }

  @override
  double scaleNumber(double number) {
    return number * settings.scaleFactor;
  }

  double unscaleRating(double rating) {
    return (rating - settings.scaleOffset) / settings.scaleFactor;
  }

  double unscaleNumber(double number) {
    return number / settings.scaleFactor;
  }

  @override
  String formatNumericRating(double rating) {
    return settings.formatNumericRating(rating);
  }

  @override
  String formatNumericRatingChange(double ratingChange) {
    return settings.formatNumericRatingChange(ratingChange);
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
    double initialRating = settings.startingRating;
    double initialVariance = settings.startingVariance;

    if(sport.initialLatentLogRatings.containsKey(shooter.classification)) {
      initialRating = sport.initialLatentLogRatings[shooter.classification]!.rating;
      initialVariance = sport.initialLatentLogRatings[shooter.classification]!.varianceMultiplier * settings.startingVariance;
    }
    else if(sport.initialGenericRatingMultipliers.containsKey(shooter.classification)) {
      var ratingMultiplier = sport.initialGenericRatingMultipliers[shooter.classification] ?? 1.0;
      if(ratingMultiplier != 1.0) {
        // LLR ratings are log performance multipliers.
        // We soften the prior by moving it only 1/3rd of the way from the global
        // mean to the classification mean in pure log-space.

        double logAdvantage = log(ratingMultiplier);
        double softLogAdvantage = logAdvantage / 3.0; // Shrinkage applied here

        initialRating += softLogAdvantage;
        // initialRating = log(ratingMultiplier);
      }
    }

    return LatentLogRating(
      shooter,
      sport: sport,
      date: date,
      initialRating: initialRating,
      initialVariance: initialVariance,
      initialDispersion: settings.startingDispersion,
      settings: settings,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating<RatingEvent>> ratings) {
    StringBuffer csv = StringBuffer();
    csv.writeln("Member#,Name,Rating,Variance,Dispersion,Momentum,MinRating,MaxRating,Matches,Stages");
    for (var r in ratings) {
      r as LatentLogRating;
      final displayMinimumRating = r.formatNumericRating(r.careerMinimumRating);
      final displayMaximumRating = r.formatNumericRating(r.careerMaximumRating);
      csv.writeln(
        '${r.memberNumber},"${r.name}",${r.displayAgedRating},${r.displayVariance},${r.displayDispersion},${r.displayMomentum},$displayMinimumRating,$displayMaximumRating,${r.lengthInMatches},${r.lengthInStages}',
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
    double weightedMaturitySum = 0.0;
    double totalWeight = 0.0;
    double totalRobustWeight = 0.0;
    double weightedSquareRootVarianceSum = 0.0;
    double squaredWeightedVarianceSum = 0.0;
    Map<ShooterRating, double> competitorScoreEvidence = {};
    Map<ShooterRating, double> competitorTailNoise = {};
    Map<ShooterRating, double> competitorAgedRatings = {};
    Map<ShooterRating, double> competitorVariances = {};
    Map<ShooterRating, Set<ShooterRating>> pairwiseOpponents = {};

    late DateTime start;
    if (Timings.enabled) {
      start = DateTime.now();
    }

    // First pass: gather data and calculate the baseline.
    List<ShooterRating> validShooters = [];
    for (var shooter in shooters) {
      shooter as LatentLogRating;
      final agedRating = shooter.calculateAgedRating(asOfDate: match.date);
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
      competitorAgedRatings[shooter] = agedRating;
      competitorVariances[shooter] = shooterVariance;
      final weight =
          1.0 /
          (shooterVariance +
              settings.sportVariance +
              shooter.dispersion +
              tailNoise);

      competitorWeights[shooter] = weight;
      weightedSquareRootVarianceSum += weight * sqrt(shooterVariance);
      squaredWeightedVarianceSum += weight * weight * shooterVariance;
      totalWeight += weight;
      // Per-competitor logarithmic maturity μ_i, precision-weighted
      // into field maturity μ̄ (paper Step 6).
      weightedMaturitySum += weight * _graphMaturity(shooter.length.toDouble());

      final residual = agedRating - scoreEvidence;
      competitorBaselineResiduals[shooter] = residual;
      baselineResidual += weight * residual;
    }

    // Null assertions are safe because validShooters filters out shooters with no score.
    final competitorsByFinish = validShooters.sorted((a, b) => scores[a]!.place.compareTo(scores[b]!.place));
    final competitorsByRating = validShooters.sorted((a, b) => competitorAgedRatings[b]!.compareTo(competitorAgedRatings[a]!));
    final top10PctCompetitors = _selectTop10PctOpponents(competitorsByFinish, competitorsByRating);

    int lowIndex = 0;
    int highIndex = 0;
    if(settings.pairwiseBlendWeight > 0) {
      final finishAsc = competitorsByFinish.reversed.toList();
      final finishN = finishAsc.length;
      final ratingAsc = competitorsByRating.reversed.toList();
      final ratingN = ratingAsc.length;
      final targetRatioMargin = competitorsByFinish.length >= 10 ? 0.1 : 0.25;

      for(int i = 0; i < competitorsByFinish.length; i++) {
        final competitorRatio = scores[finishAsc[i]]!.ratio;
        final windowBottom = competitorRatio * (1 - targetRatioMargin);
        final windowTop = competitorRatio * (1 + targetRatioMargin);

        while(lowIndex < finishN && scores[finishAsc[lowIndex]]!.ratio < windowBottom) {
          lowIndex++;
        }
        while(highIndex < finishN && scores[finishAsc[highIndex]]!.ratio <= windowTop) {
          highIndex++;
        }

        pairwiseOpponents[finishAsc[i]] = {
          ...top10PctCompetitors,
          ...finishAsc.sublist(lowIndex, highIndex),
        };
      }

      lowIndex = 0;
      highIndex = 0;
      for(int i = 0; i < competitorsByRating.length; i++) {
        final competitorRating = competitorAgedRatings[ratingAsc[i]]!;
        final windowBottom = competitorRating - 2 * sqrt(settings.sportVariance);
        final windowTop = competitorRating + 2 * sqrt(settings.sportVariance);

        while(lowIndex < ratingN && competitorAgedRatings[ratingAsc[lowIndex]]! < windowBottom) {
          lowIndex++;
        }
        while(highIndex < ratingN && competitorAgedRatings[ratingAsc[highIndex]]! <= windowTop) {
          highIndex++;
        }

        pairwiseOpponents[ratingAsc[i]]!.addAll(ratingAsc.sublist(lowIndex, highIndex));
      }
    }

    // If baseline robustness is enabled, apply a Huber-style taper to
    // the baseline weights to downweight extreme outliers.
    if (totalWeight > 0 && settings.baselineRobustnessZ > 0) {
      // Recalculate with robust weights
      weightedSquareRootVarianceSum = 0.0;
      squaredWeightedVarianceSum = 0.0;

      final rawBaseline = baselineResidual / totalWeight;
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

        weightedSquareRootVarianceSum += effectiveWeight * sqrt(competitorVariances[shooter]!);
        squaredWeightedVarianceSum += effectiveWeight * effectiveWeight * competitorVariances[shooter]!;

        competitorWeights[shooter] = effectiveWeight;
        robustResidualSum += effectiveWeight * residual;
        robustWeightSum += effectiveWeight;
      }
      if (robustWeightSum > 0) {
        baselineResidual = robustResidualSum;
        totalRobustWeight = robustWeightSum;
      }
    }
    else {
      // If baseline robustness is disabled, put the total weight into the robust
      // weight var for minimum impact later on in this function.
      totalRobustWeight = totalWeight;
    }

    // If weak field observation variance is enabled, calculate additional
    // observation noise for small/degenerate fields.
    final weakFieldVariance = _weakFieldObservationVariance(
      validShooters,
      scores,
    );

    // Field maturity μ̄ ∈ [0, 1]: precision-weighted mean of per-competitor
    // logarithmic maturity fractions. Novelty scales by (1 - μ̄).
    final fieldMaturity = (weightedMaturitySum / totalWeight).clamp(0.0, 1.0);
    final newFieldVariance = settings.noveltyVariance * (1.0 - fieldMaturity);

    if (Timings.enabled) {
      Timings().add(TimingType.calcExpected, DateTime.now().difference(start).inMicroseconds);
      start = DateTime.now();
    }

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
        shooterAgedRating: competitorAgedRatings[shooter]!,
        baselineResidualSum: baselineResidual,
        weightedSquareRootVarianceSum: weightedSquareRootVarianceSum,
        squaredWeightedVarianceSum: squaredWeightedVarianceSum,
        totalBaselineWeight: totalRobustWeight,
        weakFieldVariance: weakFieldVariance,
        fieldMaturity: fieldMaturity,
        newFieldVariance: newFieldVariance,
        validScoresCount: validShooters.length,
        scores: scores,
        competitorScoreEvidence: competitorScoreEvidence,
        competitorTailNoise: competitorTailNoise,
        competitorWeights: competitorWeights,
        competitorAgedRatings: competitorAgedRatings,
        competitorVariances: competitorVariances,
        top10PctCompetitors: top10PctCompetitors,
        competitorsByRating: competitorsByRating,
        pairwiseOpponents: pairwiseOpponents[shooter] ?? {},
      );
      if (change == null) {
        continue;
      }
      changes[shooter] = change;
    }

    if (Timings.enabled) {
      Timings().add(TimingType.updateRatings, DateTime.now().difference(start).inMicroseconds);
    }

    return changes;
  }

  @override
  RatingChange noOpChangeFor({
    required LatentLogRating shooter,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    required NonRatingResultReason reason,
  }) {
    return RatingChange(
      change: {
        RatingSystem.ratingChangeKey: 0.0,
        LatentLogRater.oldVarianceKey: shooter.variance,
        LatentLogRater.oldDispersionKey: shooter.dispersion,
        LatentLogRater.varianceChangeKey: 0.0,
        LatentLogRater.dispersionChangeKey: 0.0,
        LatentLogRater.momentumChangeKey: 0.0,
        LatentLogRater.stagesKey: 0.0,
      },
      infoLines: [
        "No rating change ({{resultReason}})",
      ],
      infoData: [
        RatingEventInfoElement.string(name: "resultReason", stringValue: reason.name.toUpperCase()),
      ],
      nonRatingResultReason: reason,
    );
  }

  @override
  bool hasAgedRatings() {
    return settings.meanReversionDecayRate > 0.0;
  }

  /// The standard scaler for the latent log rater.
  RatingScaler get standardScaler => StandardizedMaximumScaler(info: null, scaleMin: -1.0, scaleMax: 0.5);

  @override
  Future<Set<DbShooterRating>> ageRatings({
    required DbRatingProject project,
    required RatingGroup group,
    required DateTime referenceDate,
    Iterable<DbShooterRating> loadedRatings = const {},
  }) async {
    final graceDays = (settings.meanReversionGraceYears * 365).round();
    final graceDate = referenceDate.subtract(Duration(days: graceDays));
    final ratings = await project.getRatingsLastSeenBefore(group, graceDate);

    if(ratings.isErr()) {
      _log.e("Error getting ratings to age: ${ratings.unwrapErr()}");
      return {};
    }

    Map<int, DbShooterRating> ratingsToConsider = {};
    for(var rating in loadedRatings) {
      if(rating.lastSeen.isBefore(graceDate) && LatentLogRating.getLastCommitDate(rating).isBefore(graceDate)) {
        ratingsToConsider[rating.id] = rating;
      }
      else {
        ratingsToConsider.remove(rating.id);
      }
    }

    for(var rating in ratings.unwrap()) {
      if(ratingsToConsider.containsKey(rating.id)) {
        continue;
      }

      // We know that lastSeen is before graceDate because it's coming from a query to that effect.
      if(LatentLogRating.getLastCommitDate(rating).isBefore(graceDate)) {
        ratingsToConsider[rating.id] = rating;
      }
      else {
        ratingsToConsider.remove(rating.id);
      }
    }

    final agedRatings = ratingsToConsider.values.toSet();

    for(var rating in agedRatings) {
      rating.agedRating = LatentLogRating.calculateAgedRatingStatic(
        rating: rating.rating,
        asOfDate: referenceDate,
        settings: settings,
        lastSeen: LatentLogRating.getLastCommitDate(rating),
      );
    }

    return agedRatings;
  }

  RatingChange? _calculateRatingChangeForShooter({
    /// The match being processed.
    required ShootingMatch match,

    /// The shooter being processed.
    required ShooterRating shooter,

    /// The aged rating of the shooter.
    required double shooterAgedRating,

    /// The aged variance of the shooter, accounting for time since the last update.
    required double shooterVariance,

    /// The sum of the baseline residuals.
    required double baselineResidualSum,

    /// The weighted sum of the square roots of the variances.
    required double weightedSquareRootVarianceSum,

    /// The sum of the variances weighted by the squares of their weights.
    required double squaredWeightedVarianceSum,

    /// The total weight of the baseline.
    required double totalBaselineWeight,

    /// The weak field observation variance.
    required double weakFieldVariance,

    /// The field maturity (i.e. precision-weighted mean log-history length).
    required double fieldMaturity,

    /// The new field variance.
    required double newFieldVariance,

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

    /// The aged ratings of the competitors.
    required Map<ShooterRating, double> competitorAgedRatings,

    /// The variances of the competitors.
    required Map<ShooterRating, double> competitorVariances,

    /// The top 10% of competitors by rating and finish, for pairwise blending.
    required List<ShooterRating> top10PctCompetitors,

    /// The list of competitor ratings sorted by rating.
    required List<ShooterRating> competitorsByRating,

    /// The pairwise opponents of the shooter.
    required Set<ShooterRating> pairwiseOpponents,
  }) {
    shooter as LatentLogRating;
    final agedRating = shooterAgedRating;
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

    // Leave-one-out baseline: remove this competitor's own contribution
    // to avoid circularity. B_{-i} = (Σ w_j (R_j - L_j) - w_i (R_i - L_i)) / (Σ w_j - w_i).
    final looWeight = totalBaselineWeight - shooterWeight;
    if (looWeight <= 0) {
      return null;
    }

    final looSquareRootVarianceSum = weightedSquareRootVarianceSum - (shooterWeight * sqrt(shooterVariance));
    final looSquaredWeightedVarianceSum = squaredWeightedVarianceSum - (shooterWeight * shooterWeight) * shooterVariance;
    final term1 = 1.0 / looWeight;
    final term2 =
      (settings.intraclassCorrelation / (looWeight * looWeight))
      * ((looSquareRootVarianceSum * looSquareRootVarianceSum) - looSquaredWeightedVarianceSum);

    final looBaseline =
        (baselineResidualSum - shooterWeight * (agedRating - shooterScoreEvidence)) /
        looWeight;
    final looBaselineVariance = term1 + term2;

    // if(fieldAverageUncertainty > baselineVariance) {
    //   _log.w("Match ${match.name} with $opponentCount opponents has "
    //   "field average uncertainty ${fieldAverageUncertainty.toStringAsPrecision(2)} > "
    //   "baseline variance ${baselineVariance.toStringAsPrecision(2)}");
    // }

    double localBaseline = 0.0;
    double localBaselineWeight = 0.0;
    double localBaselineVariance = 0.0;
    double localWeightedSquareRootVarianceSum = 0.0;
    double localSquaredWeightedVarianceSum = 0.0;
    int pairwiseOpponentCount = 0;

    // Pairwise blending, conditioned on at least [weak field max size] opponents.
    if (settings.pairwiseBlendWeight > 0 && validScoresCount >= settings.weakFieldMaxSize) {
      pairwiseOpponentCount = pairwiseOpponents.length;

      for (var opponent in pairwiseOpponents) {
        opponent as LatentLogRating;
        // Competitor's contribution to the numerator and denominator of B_local.
        final opponentScoreEvidence = competitorScoreEvidence[opponent];
        final opponentTailNoise = competitorTailNoise[opponent];
        final opponentWeight = competitorWeights[opponent];
        final opponentAgedRating = competitorAgedRatings[opponent];
        final opponentAgedVariance = competitorVariances[opponent];
        if (opponentScoreEvidence == null || opponentTailNoise == null || opponentWeight == null || opponentAgedRating == null || opponentAgedVariance == null) {
          //_log.e("Missing parameter for pairwise blending: $shooter vs $opponent");
          continue;
        }
        final opponentBaselineResidual = opponentAgedRating - opponentScoreEvidence;
        final baselineContribution = opponentWeight * opponentBaselineResidual;
        final weightContribution = opponentWeight;

        localBaseline += baselineContribution;
        localBaselineWeight += weightContribution;
        localWeightedSquareRootVarianceSum += weightContribution * sqrt(opponentAgedVariance);
        localSquaredWeightedVarianceSum += weightContribution * weightContribution * opponentAgedVariance;
      }

      if (localBaselineWeight > 0) {
        final term1 = 1.0 / localBaselineWeight;
        final term2 = (settings.intraclassCorrelation / (localBaselineWeight * localBaselineWeight))
          * ((localWeightedSquareRootVarianceSum * localWeightedSquareRootVarianceSum) - localSquaredWeightedVarianceSum);

        localBaseline /= localBaselineWeight;
        localBaselineVariance = term1 + term2;
      }
    }

    var pairwiseBlendWeight = settings.pairwiseBlendWeight;
    if (pairwiseOpponentCount < 10) {
      pairwiseBlendWeight *= lerpAroundCenter(
        value: pairwiseOpponentCount.toDouble(),
        center: (10 + 2) / 2,
        rangeMin: 2,
        rangeMax: 10,
        minOut: 0,
        centerOut: 0.5,
        maxOut: 1,
      );
    }

    final observedBaseline =
        (1 - pairwiseBlendWeight) * looBaseline +
        pairwiseBlendWeight * localBaseline;
    final observedPerformance = shooterScoreEvidence + observedBaseline;
    var innovation = observedPerformance - agedRating;

    var pairwiseBlendWeightSquared = pairwiseBlendWeight * pairwiseBlendWeight;

    // How certain are we about the shooter's variance? If we're not very
    // certain, we can neither use nor update the dispersion by very much—
    // we don't know if we're varying around the mean because we don't know
    // where the mean is.
    final dispersionCertainty =
        1.0 - (shooterVariance / settings.maximumVariance).clamp(0.0, 1.0);

    // Certainty-scaled momentum adaptation rate (λ_i^eff in the paper).
    // Computed here because it is the denominator of the Trend calculation
    // below, as well as the EMA rate for the momentum update later on.
    final effectiveMomentumAdaptationRate =
        settings.momentumAdaptationRate * max(0.25, dispersionCertainty);

    // Effective observation noise propagates uncertainty from the baseline
    // estimate and pairwise estimate into the Kalman filter, rather than
    // treating them as known quantities.
    final blendedBaselineVariance =
      (1 - pairwiseBlendWeightSquared) * looBaselineVariance
      + pairwiseBlendWeightSquared * localBaselineVariance;
    final effectiveDispersion = dispersionCertainty * shooter.dispersion;
    final cleanObsNoise =
      settings.sportVariance
      + effectiveDispersion
      + blendedBaselineVariance;

    final totalObsNoise =
      cleanObsNoise
      + shooterTailNoise
      + weakFieldVariance
      + newFieldVariance;

    // Trend-driven prior inflation: the committed momentum (from prior
    // matches) acts as adaptive process noise and inflates the prior before
    // the Kalman update. This is the Kalman-canonical placement for process
    // noise; sustained drift detected by the momentum EMA raises the gain on
    // this match's mean update, not just the posterior variance.
    //
    // Dividing by λ_eff (rather than raw λ) is a self-normalizing detector:
    // under the EMA null, E[m_i^2] ≈ λ_eff · Var(robustInnovation), so the
    // expected "no-drift" Trend is constant across certainty levels.
    final momentumCorrection = (shooter.momentum * shooter.momentum) / effectiveMomentumAdaptationRate;
    final trendInjection = settings.surpriseAdaptationRate * max(0.0, momentumCorrection);
    final priorVariance = min(
      settings.maximumVariance,
      shooterVariance + trendInjection,
    );

    final totalNoise = priorVariance + totalObsNoise;
    final zScore = innovation / sqrt(totalNoise);

    final obsQuality = cleanObsNoise / totalObsNoise;

    // Student-t robust weight: damp outlier innovations.
    final nu = settings.studentTNu;

    // Asymmetric damping: strong positive signals are more likely to be skill signals, strong negative
    // signals are more likely to be noise.
    final cT = innovation > 0 ? settings.studentTCutoffUpperZ : settings.studentTCutoffLowerZ;
    final weight = min(1.0, (nu + cT * cT) / (nu + zScore * zScore));
    final dampedInnovation = innovation * weight;

    final kalmanGain = priorVariance / totalNoise;
    final newRating = agedRating + kalmanGain * dampedInnovation;

    // Momentum is a signed EMA over innovation.
    // We operate on 'clean' innovation, i.e. only that portion of innovation that
    // is not explained by degenerate fields, tail noise, etc.
    // The updated momentum drives the next match's Trend injection.
    final robustInnovation = dampedInnovation * obsQuality;
    final newMomentum = shooter.momentum * (1 - effectiveMomentumAdaptationRate) +
        effectiveMomentumAdaptationRate * robustInnovation;

    // Shock is a single-event posterior variance injection, independent of
    // Trend. We use the physical innovation (structural noise stripped, but
    // physical outliers retained) against the Trend-inflated totalNoise, so
    // Shock only fires on surprises that exceed even the trend-authorized
    // expectation.
    final physicalInnovation = innovation * obsQuality;
    final surpriseCorrection = (physicalInnovation * physicalInnovation) - totalNoise;
    final shockInjection = settings.surpriseAdaptationRate * max(0.0, surpriseCorrection);

    final newVariance = min(
      settings.maximumVariance,
      priorVariance * (1 - kalmanGain) + shockInjection,
    );

    final maximumDispersion = settings.maximumVariance * _dispersionScaleFactor;

    // 0.1% of starting variance (i.e., 'minimal')—we don't want to use 1% of maximum
    // because maximum may be very liberal, and we want this to be more like
    // an epsilon than a meaningful limit.
    final minimumDispersion = 0.001 * settings.startingVariance * _dispersionScaleFactor;

    // Clamp observations to 3SD
    final maxInstantaneousVarianceSigmaSquared = 9.0;
    final maxInstantaneousVarianceReference = max(shooter.dispersion, 0.25 * settings.sportVariance);

    final maxInstantaneousVariance = max(
      maxInstantaneousVarianceSigmaSquared * maxInstantaneousVarianceReference,
      minimumDispersion
    );

    // Aleatoric noise (dispersion) is the portion of innovation not explained by:
    // 1. variance.
    // 2. inherent sport noise.
    // and 3. an ongoing trend as tracked by momentum.
    final denoisedInnovationVariance = max(0, pow(physicalInnovation - newMomentum, 2) - shooterVariance - settings.sportVariance);
    final clampedInstantaneousVariance = denoisedInnovationVariance.clamp(minimumDispersion, maxInstantaneousVariance);

    final effectiveDispersionAdaptationRate = settings.dispersionAdaptationRate * max(0.25, dispersionCertainty);
    final newDispersion =
        (shooter.dispersion * (1 - effectiveDispersionAdaptationRate) +
        effectiveDispersionAdaptationRate * clampedInstantaneousVariance * _dispersionScaleFactor)
        .clamp(
          minimumDispersion,
          maximumDispersion,
        );


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

    final stagesForEvent = byStage ? 1.0 : match.stages.length.toDouble();

    return RatingChange(
      change: {
        // The committed rating is not aged, so we want to calculate the
        // change against that baseline.
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
        "@tpl:llrV2",
      ],
      infoData: [
        RatingEventInfoElement.double(
          name: "baselineResidual",
          doubleValue: baselineResidualSum,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "totalWeight",
          doubleValue: totalBaselineWeight,
          numberFormat: "%00.2f",
        ),
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
          numberFormat: "%00.1f",
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
          name: "priorVariance",
          doubleValue: priorVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "trendInjection",
          doubleValue: trendInjection / settings.sportVariance,
          numberFormat: "%00.3f",
        ),
        RatingEventInfoElement.double(
          name: "cleanObsNoise",
          doubleValue: cleanObsNoise / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "effectiveDispersion",
          doubleValue: effectiveDispersion / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "baselineVar",
          doubleValue: blendedBaselineVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "pairwiseAlpha",
          doubleValue: pairwiseBlendWeight,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "pairwiseAlphaSquared",
          doubleValue: pairwiseBlendWeightSquared,
          numberFormat: "%00.3f",
        ),
        RatingEventInfoElement.double(
          name: "observedBaseline",
          doubleValue: observedBaseline,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "obsQuality",
          doubleValue: obsQuality,
          numberFormat: "%00.3f",
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
          doubleValue: looBaselineVariance / settings.sportVariance,
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
        RatingEventInfoElement.double(
          name: "ePhysSquared",
          doubleValue: (physicalInnovation * physicalInnovation) / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "lambdaEff",
          doubleValue: effectiveMomentumAdaptationRate,
          numberFormat: "%00.4f",
        ),
        RatingEventInfoElement.double(
          name: "certainty",
          doubleValue: dispersionCertainty,
          numberFormat: "%00.3f",
        ),
        RatingEventInfoElement.double(
          name: "noveltyNoise",
          doubleValue: newFieldVariance / settings.sportVariance,
          numberFormat: "%00.2f",
        ),
        RatingEventInfoElement.double(
          name: "fieldMaturity",
          doubleValue: fieldMaturity,
          numberFormat: "%00.2f",
        ),
      ],
    );
  }

  /// Per-competitor graph maturity μ_i = min(1, ln(k+1) / ln(k_max+1)).
  double _graphMaturity(double experienceCount) {
    final kMax = settings.graphMaturityThreshold;
    if (kMax <= 0) {
      return 1.0;
    }
    return (log(experienceCount + 1.0) / log(kMax + 1.0)).clamp(0.0, 1.0);
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

    var top10PctByMatchFinish = opponentsByFinish.take(opponentsToTake).toSet();
    var top10PctByRating = opponentsByRating.take(opponentsToTake).toSet();

    top10PctByMatchFinish.addAll(top10PctByRating);
    return top10PctByMatchFinish.toList();
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
    final actualDate = _predictionsUseAgedRatings ? matchDate : null;
    var actualVarianceDate = actualDate;
    if(actualDate != null && _predictionsUseAgedRatings && _predictionsAgeCapDays > 0) {
      if(actualDate.difference(DateTime.now()).inDays > _predictionsAgeCapDays) {
        actualVarianceDate = DateTime.now().add(Duration(days: _predictionsAgeCapDays));
        _log.i("Capping time-to-match for variance to $_predictionsAgeCapDays days, new date $matchDate");
      }
    }

    List<AlgorithmPrediction> predictions = [];

    List<LatentLogRating> sortedRatings = ratings
      .cast<LatentLogRating>()
      .where((r) => r.length > 0 && r.stageCount! > 0)
      .sorted((a, b) => b.calculateAgedRating(asOfDate: matchDate).compareTo(a.calculateAgedRating(asOfDate: matchDate)));

    if(sortedRatings.isEmpty) {
      return [];
    }

    if(sortedRatings.length < 2) {
      return [
        AlgorithmPrediction(
          shooter: sortedRatings[0],
          displayCenter: 1.0,
          sigma: 0.0,
          settings: settings,
          algorithm: this,
          expectedRatio: 1.0,
          oneSigmaRatio: 0.0,
          lowPlace: 1,
          highPlace: 1,
          medianPlace: 1,
        ),
      ];
    }

    List<_PresumedWinnerPrediction> presumedWinners = _predictionsUseMonteCarlo ?
      _presumedWinnersMonteCarlo(sortedRatings, matchDate: actualDate, varianceDate: actualVarianceDate) :
      _presumedWinnersClosedForm(sortedRatings, matchDate: actualDate, varianceDate: actualVarianceDate);

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
      double probabilityWeightedGrandMean = 0.0;

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

      /// Probability-weighted sum of the within-component variance of the difference
      /// between the focal competitor and each presumed winner.
      double probabilityWeightedWithinVariance = 0.0;

      /// The win probability of the focal competitor as the presumed winner.
      double ownPresumedWinProbability = 0.0;

      final agedRating = rating.calculateAgedRating(asOfDate: actualDate);

      final ratingVariance = rating.calculateCurrentVariance(asOfDate: actualVarianceDate);

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

      // Account for the fact that winning performances are typically physically bounded;
      // it's asymmetric.
      final eMax = stdNormal.quantile((nEff - 0.375) / (nEff + 0.25)).toDouble();

      final kappa = settings.predictionBehavioralDispersionKappa;
      final ownCertainty = 1.0 - (ratingVariance / settings.maximumVariance).clamp(0.0, 1.0);

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


        final winnerVariance = presumedWinner.shooter.calculateCurrentVariance(asOfDate: actualVarianceDate);
        final winnerAgedRating = presumedWinner.shooter.calculateAgedRating(asOfDate: actualDate);

        final winnerCertainty = 1.0 - (winnerVariance / settings.maximumVariance).clamp(0.0, 1.0);

        final winnerDrawStdDev = sqrt(
          (1 - settings.intraclassCorrelation) * winnerVariance +
          kappa * winnerCertainty * presumedWinner.shooter.dispersion +
          settings.predictionSportVariance
        );
        final effectiveWinnerRating = winnerAgedRating + winnerDrawStdDev * eMax;

        final logDifference = agedRating - effectiveWinnerRating;
        probabilityWeightedGrandMean += logDifference * winProbability;
        probabilityWeightedLogDifferences.add((pW: winProbability, muIW: logDifference));

        // The variance of the difference (R_i - R_w) equals V_i + V_w - 2*Cov(i,w)
        // Covariance is approximated by rho * sqrt(V_i * V_w)
        final epistemicPairwise = ratingVariance + winnerVariance
            - 2 * settings.intraclassCorrelation * sqrt(ratingVariance * winnerVariance);

        final dispersionComponent =
          settings.predictionBehavioralDispersionKappa
          * (ownCertainty * rating.dispersion + winnerCertainty * presumedWinner.shooter.dispersion);

        final pairwiseVariance = epistemicPairwise + 2 * settings.predictionSportVariance + dispersionComponent;

        probabilityWeightedWithinVariance += pairwiseVariance * winProbability;

        final truncationCorrectionNumerator = -((logDifference + pairwiseVariance) / sqrt(pairwiseVariance));
        final truncationCorrectionDenominator = -(logDifference / sqrt(pairwiseVariance));
        final truncationCorrection = stdNormal.cdf(truncationCorrectionNumerator) / stdNormal.cdf(truncationCorrectionDenominator);

        final correctionTerm = pairwiseVariance / 2;
        final weightedRatio = exp(logDifference + correctionTerm) * truncationCorrection * winProbability;
        probabilityWeightedRatio += weightedRatio;
        probabilityWeightedWinnerVariance += winnerVariance * winProbability;
        probabilityWeightedWinnerDispersion +=
            winnerCertainty * presumedWinner.shooter.dispersion * winProbability;
      }

      double betweenComponentVariance = ownPresumedWinProbability * probabilityWeightedGrandMean * probabilityWeightedGrandMean;
      for(var (pW: double winProbability, muIW: double logDifference) in probabilityWeightedLogDifferences) {
        betweenComponentVariance += winProbability * pow(logDifference - probabilityWeightedGrandMean, 2);
      }
      final withinComponentVariance = probabilityWeightedWithinVariance;

      final geometricSD = exp(sqrt(withinComponentVariance + betweenComponentVariance));
      final lowerCi = probabilityWeightedRatio / geometricSD;
      final upperCi = probabilityWeightedRatio * geometricSD;

      final rawLogSigma = sqrt(
        (1 - settings.intraclassCorrelation) * ratingVariance
        + kappa * rating.dispersion
        + settings.predictionSportVariance
      );

      final varianceCorrection = exp(-0.5 * (withinComponentVariance + betweenComponentVariance));
      final medianRatio = probabilityWeightedRatio * varianceCorrection;
      final oneSigmaRatio = ((upperCi - probabilityWeightedRatio) + (probabilityWeightedRatio - lowerCi)) / 2;

      if(probabilityWeightedRatio > 0.8) {
        final logLine = StringBuffer();
        logLine.writeln("Rating: $rating");
        logLine.writeln("Expectation/1σ CI:\t\t${probabilityWeightedRatio.toStringAsFixed(8)} / (${lowerCi.toStringAsFixed(8)} - ${upperCi.toStringAsFixed(8)})");
        if(ownPresumedWinProbability > 0.0) {
          logLine.writeln("Own presumed p_w:\t\t${ownPresumedWinProbability.toStringAsFixed(8)}");
        }
        logLine.writeln("Predictive variance:\t\t${withinComponentVariance.toStringAsFixed(8)}");
        logLine.writeln("Rating variance:\t\t${ratingVariance.toStringAsFixed(8)}");
        logLine.writeln("Variance age component:\t\t${(ratingVariance - rating.variance).toStringAsFixed(8)}");
        logLine.writeln("Prediction sport variance:\t${(2 * settings.predictionSportVariance).toStringAsFixed(8)}");
        logLine.writeln("Weighted winner variance::\t${probabilityWeightedWinnerVariance.toStringAsFixed(8)}");
        logLine.writeln("Weighted rating dispersion:\t${(rating.dispersion * kappa).toStringAsFixed(8)}");
        logLine.writeln("Weighted winner dispersion:\t${(probabilityWeightedWinnerDispersion * kappa).toStringAsFixed(8)}");
        logLine.writeln("Kappa: \t\t\t\t${kappa.toStringAsFixed(2)}");
        logLine.writeln("");
        _log.v(logLine.toString());
      }

      // We'll fill in places in a second pass
      predictions.add(AlgorithmPrediction(
        shooter: rating,
        displayCenter: medianRatio,
        sigma: geometricSD,
        settings: settings,
        algorithm: this,
        expectedRatio: probabilityWeightedRatio,
        oneSigmaRatio: oneSigmaRatio,
        shiftRatio: 0.0,
        isLogNormal: true,
        logMean: agedRating,
        logSigma: rawLogSigma,
      ));
    }

    var sortedPredictions = predictions.sorted((a, b) => b.displayCenter.compareTo(a.displayCenter));

    for(var (centerPlace, prediction) in sortedPredictions.indexed) {
      int belowCompetitorsLow = 0;
      int belowCompetitorsHigh = 0;
      prediction.medianPlace = centerPlace + 1;
      for(var other in sortedPredictions) {
        if(prediction == other) {
          continue;
        }

        // Place is the number of competitors who beat us + 1.
        // Our low prediction the number of competitors whose high
        // prediction beats our mean.
        // Our high prediction is the number of competitors whose low
        // prediction beats our mean.
        if(other.highPrediction > prediction.displayCenter) {
          belowCompetitorsLow++;
        }
        if(other.lowPrediction > prediction.displayCenter) {
          belowCompetitorsHigh++;
        }
      }

      prediction.lowPlace = belowCompetitorsLow + 1;
      prediction.highPlace = belowCompetitorsHigh + 1;
    }

    return predictions;
  }

  List<_PresumedWinnerPrediction> _presumedWinnersClosedForm(
    List<LatentLogRating> sortedRatings,
    {
      DateTime? matchDate,
      DateTime? varianceDate,
    }
  ) {
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
      final agedRating = rating.calculateAgedRating(asOfDate: matchDate);
      final ratingVariance = rating.calculateCurrentVariance(asOfDate: varianceDate);
      List<double> pairwiseProbabilities = [];
      for (var opponent in sortedRatings) {
        if (opponent == rating) {
          continue;
        }

        final opponentAgedRating = opponent.calculateAgedRating(asOfDate: matchDate);
        final opponentVariance = opponent.calculateCurrentVariance(asOfDate: varianceDate);

        double numerator = agedRating - opponentAgedRating;
        // all properties are in variance units

        double denominator = sqrt(
          ratingVariance
          + opponentVariance
          + 2 * settings.predictionSportVariance
        );

        double probability = stdNormal.cdf(numerator / denominator).toDouble();
        pairwiseProbabilities.add(probability);
      }
      double winProbability = pairwiseProbabilities.reduce((a, b) => a * b);
      predictions.add(_PresumedWinnerPrediction(shooter: rating, winProbability: winProbability));
    }

    return _PresumedWinnerPrediction.normalize(predictions);
  }

  List<_PresumedWinnerPrediction> _presumedWinnersMonteCarlo(
    List<LatentLogRating> sortedRatings,
    {
      DateTime? matchDate,
      DateTime? varianceDate,
      Random? random,
    }
  ) {
    varianceDate ??= matchDate;
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
        final agedRating = rating.calculateAgedRating(asOfDate: matchDate);
        final currentVariance = varianceDate != null && _predictionsUseAgedRatings ?
          rating.calculateCurrentVariance(asOfDate: varianceDate) : //rating.variance :
          rating.variance;
        if(index > depth) {
          break;
        }
        var draw = random.nextGaussianWithParams(mu: agedRating, sigma: sqrt(currentVariance + settings.predictionSportVariance));
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

  static const _paddingFlex = 2;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _ratingFlex = 2;
  static const _lastChangeFlex = 2;
  static const _varianceFlex = 2;
  static const _dispersionFlex = 2;
  static const _momentumFlex = 2;
  static const _matchesFlex = 2;
  static const _stagesFlex = 2;

  @override
  List<RatingRowData> buildRatingKeyData({DateTime? trendDate, RatingSortMode? sortMode}) {
    return [
      RatingRowData(data: "", flex: _paddingFlex),
      RatingRowData(data: "", flex: _placeFlex),
      RatingRowData(data: "Member #", flex: _memberNumFlex),
      RatingRowData(data: "Class", flex: _classFlex),
      RatingRowData(data: "Name", flex: _nameFlex),
      RatingRowData(data: "Rating", alignment: AbstractAlignment.end, flex: _ratingFlex),
      RatingRowData(data: "Last ±", alignment: AbstractAlignment.end, flex: _lastChangeFlex),
      RatingRowData(
        data: "Uncertainty",
        tooltip: "Approximate standard deviation of the rating. Uncertainty grows over time. Rows show uncertainty at the last rating update. Tooltips show uncertainty today.",
        alignment: AbstractAlignment.end,
        flex: _varianceFlex,
      ),
      RatingRowData(
        data: "Dispersion",
        tooltip: "How much a competitor's rating tends to move from event to event.",
        alignment: AbstractAlignment.end,
        flex: _dispersionFlex,
      ),
      RatingRowData(
        data: "Momentum",
        tooltip: "The directional tendency of the rating change over time.",
        alignment: AbstractAlignment.end,
        flex: _momentumFlex,
      ),
      RatingRowData(data: "Matches", alignment: AbstractAlignment.end, flex: _matchesFlex),
      RatingRowData(data: "Stages", alignment: AbstractAlignment.end, flex: _stagesFlex),
      RatingRowData(data: "", flex: _paddingFlex),
    ];
  }

  @override
  List<RatingRowData> buildRatingRowData({
    required ShooterRating rating,
    required int place,
    DateTime? trendDate,
    RatingScaler? scaler,
    RatingSortMode? sortMode,
  }) {
    rating as LatentLogRating;
    final changeDecimals = settings.decimalCount() + 1;
    final displayDelta = settings.formatNumericRatingChange(rating.lastMatchChange);
    final seenYearsAgo = DateTime.now().difference(rating.lastSeen).inDays / 365;
    final fadeRow = seenYearsAgo > 1;
    final ratingTooltip = seenYearsAgo > 1 ?
      "Last active ${seenYearsAgo.toStringAsFixed(1)} years ago." :
      null;
    final ratingDisplay = sortMode == RatingSortMode.agedRating ?
      rating.formattedAgedRating :
      rating.formattedRating;

    return [
      RatingRowData(data: "", flex: _paddingFlex, fadeText: fadeRow),
      RatingRowData(data: "$place", flex: _placeFlex, fadeText: fadeRow),
      RatingRowData(data: rating.memberNumber, flex: _memberNumFlex, fadeText: fadeRow),
      RatingRowData(data: rating.lastClassification?.shortDisplayName ?? "none", flex: _classFlex, fadeText: fadeRow),
      RatingRowData(data: rating.getName(suffixes: false), flex: _nameFlex, fadeText: fadeRow),
      RatingRowData(
        data: ratingDisplay,
        tooltip: ratingTooltip,
        alignment: AbstractAlignment.end,
        flex: _ratingFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(
        data: displayDelta,
        alignment: AbstractAlignment.end,
        flex: _lastChangeFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(
        data: rating.displayStandardDeviation.toStringAsFixed(changeDecimals),
        tooltip: "Current: ${rating.displayCurrentStandardDeviation.toStringAsFixed(changeDecimals)}",
        alignment: AbstractAlignment.end,
        flex: _varianceFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(
        data: rating.displayDispersionStandardDeviation.toStringAsFixed(changeDecimals),
        alignment: AbstractAlignment.end,
        flex: _dispersionFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(
        data: rating.displayMomentum.toStringAsFixed(changeDecimals),
        alignment: AbstractAlignment.end,
        flex: _momentumFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(
        data: rating.lengthInMatches.toString(),
        alignment: AbstractAlignment.end,
        flex: _matchesFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(
        data: rating.lengthInStages.toString(),
        alignment: AbstractAlignment.end,
        flex: _stagesFlex,
        fadeText: fadeRow,
      ),
      RatingRowData(data: "", flex: _paddingFlex, fadeText: fadeRow),
    ];
  }

  @override
  int histogramBucketSize({required int shooterCount, required int matchCount, required double minRating, required double maxRating}) {
    final totalSize = settings.scaleFactor + settings.scaleOffset;
    if(totalSize >= 2000) {
      return 100;
    }
    else if(totalSize >= 1000) {
      return 50;
    }
    else if(totalSize >= 500) {
      return 25;
    }
    else if(totalSize >= 250) {
      return 15;
    }
    else if(totalSize >= 100) {
      return 10;
    }
    else if(totalSize >= 50) {
      return 5;
    }
    else if(totalSize >= 25) {
      return 2;
    }
    else {
      return 1;
    }
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