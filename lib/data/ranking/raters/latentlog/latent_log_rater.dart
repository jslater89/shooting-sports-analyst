
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// A rating system that uses a latent log-ratio model to calculate ratings.
class LatentLogRater extends RatingSystem<LatentLogRating, LatentLogSettings> {
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
      initialVolatility: settings.sportVolatility,
      settings: settings,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating<RatingEvent>> ratings) {
    StringBuffer csv = StringBuffer();
    csv.writeln("Member#,Name,Rating,Variance,Volatility,Matches,Stages");
    for(var r in ratings) {
      r as LatentLogRating;
      csv.writeln('${r.memberNumber},"${r.name}",${r.rating},${r.variance},${r.volatility},${r.lengthInMatches},${r.lengthInStages}');
    }
    return csv.toString();
  }

  @override
  List<JsonShooterRating> ratingsToJson(List<ShooterRating<RatingEvent>> ratings) {
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
    double baselineResidual = 0.0;
    double totalWeight = 0.0;
    Map<ShooterRating, double> competitorLogScores = {};
    Map<ShooterRating, double> competitorVariances = {};

    // First pass: gather data and calculate the baseline.
    for(var shooter in shooters) {
      shooter as LatentLogRating;
      var score = scores[shooter];
      if(score == null) {
        continue;
      }

      final logScore = log(score.ratio);
      competitorLogScores[shooter] = logScore;
      final shooterVariance = shooter.calculateCurrentVariance(asOfDate: match.date);
      competitorVariances[shooter] = shooterVariance;
      final weight = 1.0 / (shooterVariance + settings.sportVolatility + shooter.volatility);
      competitorWeights[shooter] = weight;
      totalWeight += weight;

      baselineResidual += weight * (shooter.rating - logScore);
    }

    final baseline = baselineResidual / totalWeight;

    for(var shooter in shooters) {
      shooter as LatentLogRating;
      final shooterVariance = competitorVariances[shooter];
      if(shooterVariance == null) {
        continue;
      }
      var change = _calculateRatingChangeForShooter(
        match: match,
        shooter: shooter,
        shooterVariance: competitorVariances[shooter]!,
        matchDate: match.date,
        baseline: baseline,
        scores: scores,
        competitorLogScores: competitorLogScores,
        competitorPairwiseResiduals: competitorWeights,
      );
      if(change == null) {
        continue;
      }
      changes[shooter] = change;
    }

    return changes;
  }

  RatingChange? _calculateRatingChangeForShooter({
    required ShootingMatch match,
    required ShooterRating shooter,
    required double shooterVariance,
    required DateTime matchDate,
    required double baseline,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, double> competitorLogScores,
    required Map<ShooterRating, double> competitorPairwiseResiduals,
  }) {
    shooter as LatentLogRating;
    final shooterScore = scores[shooter];
    final shooterLogScore = competitorLogScores[shooter];
    if(shooterScore == null || shooterLogScore == null) {
      return null;
    }
    final shooterRatio = shooterScore.ratio;

    double pairwiseResidual = 0.0;
    int pairwiseOpponentCount = 0;
    if(settings.pairwiseBlendWeight > 0) {
      final pairwiseOpponents = _selectOpponents(shooter, scores, shooterRatio);
      pairwiseOpponentCount = pairwiseOpponents.length;

      double weightedResiduals = 0.0;
      double totalWeights = 0.0;
      for(var opponent in pairwiseOpponents) {
        opponent as LatentLogRating;
        final opponentVariance = opponent.calculateCurrentVariance(asOfDate: matchDate);
        final opponentLogScore = competitorLogScores[opponent];
        if(opponentLogScore == null) {
          continue;
        }
        final residual = (shooterLogScore - opponentLogScore) - (shooter.rating - opponent.rating);
        final weight = 1 / (opponentVariance + settings.sportVolatility + opponent.volatility);
        weightedResiduals += residual * weight;
        totalWeights += weight;
      }
      pairwiseResidual = weightedResiduals / totalWeights;
    }

    final observedPerformance = shooterLogScore + baseline + settings.pairwiseBlendWeight * pairwiseResidual;
    final innovation = observedPerformance - shooter.rating;
    final kalmanGain = shooterVariance / (shooterVariance + settings.sportVolatility + shooter.volatility);
    final newRating = shooter.rating + kalmanGain * innovation;

    final innovationVariance = innovation * innovation;
    final innovationCorrection = settings.surpriseAdaptationRate * max(0.0, innovationVariance - (shooterVariance + settings.sportVolatility + shooter.volatility));
    final newVariance = shooterVariance * (1 - kalmanGain) + innovationCorrection;
    final newVolatility = shooter.volatility * (1 - settings.volatilityAdaptationRate) + settings.volatilityAdaptationRate * innovationVariance;

    final varianceChange = newVariance - shooterVariance;
    final volatilityChange = newVolatility - shooter.volatility;

    final stagesForEvent = byStage ? 1.0 : match.stages.length.toDouble();

    return RatingChange(
      change: {
        RatingSystem.ratingChangeKey: newRating - shooter.rating,
        LatentLogRater.oldVarianceKey: shooterVariance,
        LatentLogRater.oldVolatilityKey: shooter.volatility,
        LatentLogRater.varianceChangeKey: varianceChange,
        LatentLogRater.volatilityChangeKey: volatilityChange,
        LatentLogRater.stagesKey: stagesForEvent,
      },
      infoLines: [
        "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
        "Rating ± Change: {{rating}}/{{change}}",
        "Variance ± Change: {{variance}}/{{varianceChange}}",
        "Volatility ± Change: {{volatility}}/{{volatilityChange}}",
        "Considered {{opponents}} opponents",
      ],
      infoData: [
        RatingEventInfoElement.int(name: "finish", intValue: shooterScore.place),
        RatingEventInfoElement.int(name: "competitors", intValue: scores.length),
        RatingEventInfoElement.double(name: "finishPercent", doubleValue: shooterScore.percentage, numberFormat: "%00.2f"),
        RatingEventInfoElement.double(name: "rating", doubleValue: newRating, numberFormat: "%00.0f"),
        RatingEventInfoElement.double(name: "change", doubleValue: newRating - shooter.rating, numberFormat: "%00.2f"),
        RatingEventInfoElement.double(name: "variance", doubleValue: newVariance, numberFormat: "%00.2f"),
        RatingEventInfoElement.double(name: "varianceChange", doubleValue: varianceChange, numberFormat: "%00.2f"),
        RatingEventInfoElement.double(name: "volatility", doubleValue: newVolatility, numberFormat: "%00.4f"),
        RatingEventInfoElement.double(name: "volatilityChange", doubleValue: volatilityChange, numberFormat: "%00.4f"),
        RatingEventInfoElement.int(name: "opponents", intValue: pairwiseOpponentCount),
      ],
    );
  }

  List<ShooterRating> _selectOpponents(
    LatentLogRating shooter,
    Map<ShooterRating, RelativeScore> scores,
    double shooterRatio,
  ) {
    var opponentsByFinish = scores.keys.toList();
    var opponentsByRating = opponentsByFinish.sorted((a, b) => b.rating.compareTo(a.rating)).toList();

    // For now, Latent Log Ratio only does top-and-nearby.
    Set<ShooterRating> selected = {};
    selected.addAll(_selectTop10PctOpponents(opponentsByFinish, opponentsByRating));
    selected.addAll(_selectNearbyOpponents(shooter, scores, opponentsByRating, shooterRatio));
    return selected.toList();
  }

  List<ShooterRating> _selectTop10PctOpponents(
    List<ShooterRating> opponentsByFinish,
    List<ShooterRating> opponentsByRating,
  ) {
    var percentToTake = 0.1;
    if(opponentsByFinish.length < 10) {
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
    if(opponentsByRating.length < 10) {
      margin = 0.25;
    }

    Set<ShooterRating> nearbyOpponents = {};
    final topRatio = competitorRatio * (1 + margin);
    final bottomRatio = competitorRatio * (1 - margin);
    for(var opponent in scores.keys) {
      // Players with no rating history don't have a valid rating yet, so 'nearby' in rating terms
      // isn't meaningful yet.
      if(opponent.length == 0) {
        continue;
      }

      if((opponent.rating - shooter.rating).abs() <= settings.startingVariance) {
        nearbyOpponents.add(opponent);
        continue;
      }

      var opponentScore = scores[opponent];
      if(opponentScore == null) {
        continue;
      }
      var opponentRatio = opponentScore.ratio;
      if(opponentRatio >= bottomRatio && opponentRatio <= topRatio) {
        nearbyOpponents.add(opponent);
      }
    }

    return nearbyOpponents.toList();
  }

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
}