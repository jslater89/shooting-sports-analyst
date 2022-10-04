import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:normal/normal.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/prediction/gumbel.dart';
import 'package:uspsa_result_viewer/data/ranking/prediction/match_prediction.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/ui/elo_settings_ui.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/ranking/timings.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';

class MultiplayerPercentEloRater extends RatingSystem<EloShooterRating, EloSettings, EloSettingsController> {
  static const errorKey = "error";
  static const baseKKey = "baseK";
  static const effectiveKKey = "effectiveKKey";

  static const defaultK = 60.0;
  static const defaultPercentWeight = 0.4;
  static const defaultPlaceWeight = 0.6;
  static const defaultScale = 800.0;
  static const defaultMatchBlend = 0.3;

  Timings timings = Timings();

  @override
  RatingMode get mode => RatingMode.oneShot;

  final EloSettings settings;

  /// K is the K parameter to the rating Elo algorithm
  double get K => settings.K;
  double get percentWeight => settings.percentWeight;
  double get placeWeight => settings.placeWeight;
  double get scale => settings.scale;

  get matchBlend => settings.matchBlend;
  get stageBlend => settings.stageBlend;

  @override
  bool get byStage => settings.byStage;
  bool get errorAwareK => settings.errorAwareK;

  late double errThreshold = EloShooterRating.errorScale / (K / 7.5);

  MultiplayerPercentEloRater({
    EloSettings? settings,
  }) :
      this.settings = settings != null ? settings : EloSettings() {
    EloShooterRating.errorScale = this.scale;
  }

  factory MultiplayerPercentEloRater.fromJson(Map<String, dynamic> json) {
    var settings = EloSettings();
    settings.loadFromJson(json);

    return MultiplayerPercentEloRater(settings: settings);
  }

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  }) {
    if(shooters.length != 1) {
      throw StateError("Incorrect number of shooters passed to MultiplayerElo");
    }

    if(scores.length <= 1) {
      return {
        shooters[0]: RatingChange(change: {
          RatingSystem.ratingKey: 0,
          errorKey: 0,
          baseKKey: 0,
          effectiveKKey: 0,
        }),
      };
    }

    var aRating = shooters[0] as EloShooterRating;
    var aScore = scores[aRating]!;
    var aMatchScore = matchScores[aRating]!;

    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    var params = _calculateScoreParams(aRating: aRating, aScore: aScore, aMatchScore: aMatchScore, scores: scores, matchScores: matchScores);
    if(Timings.enabled) timings.calcExpectedScore += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(params.usedScores == 1) {
      return {
        shooters[0]: RatingChange(change: {
          RatingSystem.ratingKey: 0,
          errorKey: 0,
          baseKKey: 0,
          effectiveKKey: 0,
        }),
      };
    }

    if(Timings.enabled) start = DateTime.now();

    var actualScore = _calculateActualScore(score: aScore, matchScore: aMatchScore, params: params);

    // The first N matches you shoot get bonuses for initial placement.
    var placementMultiplier = aRating.ratingEvents.length < RatingSystem.initialPlacementMultipliers.length ?
      RatingSystem.initialPlacementMultipliers[aRating.ratingEvents.length] : 1.0;

    // If lots of people zero a stage, we can't reason effectively about the relative
    // differences in performance of those people, compared to each other or compared
    // to the field that didn't zero it. If more than 10% of people zero a stage, start
    // scaling K down (to 0.34, when 30%+ of people zero a stage).
    var zeroMultiplier = (params.zeroes / params.usedScores) < 0.1 ? 1.0 : 1 - 0.66 * ((min(0.3, (params.zeroes / params.usedScores) - 0.1)) / 0.3);


    // Adjust K based on the confidence in the shooter's rating.
    // If we're more confident, we adjust less to smooth out performances.
    // If we're less confident, we adjust more to find the correct rating faster.
    var error = aRating.standardError;

    var errMultiplier = 1.0;
    final maxMultiplier = 1.0;
    final minMultiplier = 0.5;
    if(errorAwareK) {
      var minThreshold = errThreshold;
      if (error >= errThreshold) {
        errMultiplier = 1 + min(1.0, ((error - errThreshold) / (EloShooterRating.errorScale - errThreshold))) * maxMultiplier;
      }
      else if (error < minThreshold) {
        errMultiplier = 1 - ((minThreshold - error) / minThreshold) * minMultiplier;
      }
    }

    var effectiveK = K * placementMultiplier * matchStrengthMultiplier * zeroMultiplier * connectednessMultiplier * eventWeightMultiplier * errMultiplier;

    var changeFromPercent = effectiveK * (params.usedScores - 1) * (actualScore.percentComponent * percentWeight - (params.expectedScore * percentWeight));
    var changeFromPlace = effectiveK * (params.usedScores - 1) * (actualScore.placeComponent * placeWeight - (params.expectedScore * placeWeight));

    var change = changeFromPlace + changeFromPercent;
    if(Timings.enabled) timings.updateRatings += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(change.isNaN || change.isInfinite) {
      debugPrint("### ${aRating.shooter.lastName} stats: ${actualScore.actualPercent} of ${params.usedScores} shooters for ${aScore.stage?.name}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}, placement $placementMultiplier, zero $zeroMultiplier (${params.zeroes})");
      debugPrint("AS/ES: ${actualScore.score.toStringAsFixed(6)}/${params.expectedScore.toStringAsFixed(6)}");
      debugPrint("Actual/expected percent: ${(actualScore.percentComponent * params.totalPercent * 100).toStringAsFixed(2)}/${(params.expectedScore * params.totalPercent * 100).toStringAsFixed(2)}");
      debugPrint("Actual/expected place: ${actualScore.placeBlend}/${(params.usedScores - (params.expectedScore * params.divisor)).toStringAsFixed(4)}");
      debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      debugPrint("###");
      throw StateError("NaN/Infinite");
    }

    if(Timings.enabled) start = DateTime.now();
    var hf = aScore.score.getHitFactor(scoreDQ: aScore.score.stage != null);
    Map<String, List<dynamic>> info = {
      "Actual/expected percent: %00.2f/%00.2f on %00.2fHF": [actualScore.percentComponent * params.totalPercent * 100, params.expectedScore * params.totalPercent * 100, hf],
      "Actual/expected place: %00.1f/%00.1f": [actualScore.placeBlend, params.usedScores - (params.expectedScore * params.divisor)],
      "Rating ± Change: %00.0f + %00.2f (%00.2f from pct, %00.2f from place)": [aRating.rating, change, changeFromPercent, changeFromPlace],
      "eff. K, multipliers: %00.2f, SoS %00.3f, IP %00.3f, Zero %00.3f, Conn %00.3f, EW %00.3f, Err %00.3f": [effectiveK, matchStrengthMultiplier, placementMultiplier, zeroMultiplier, connectednessMultiplier, eventWeightMultiplier, errMultiplier]
    };
    if(Timings.enabled) timings.printInfo += (DateTime.now().difference(start).inMicroseconds).toDouble();

    return {
      aRating: RatingChange(change: {
        RatingSystem.ratingKey: change,
        errorKey: (params.expectedScore - actualScore.score) * params.usedScores,
        baseKKey: K * (params.usedScores - 1),
        effectiveKKey: effectiveK * (params.usedScores),
      }, info: info),
    };
  }

  _ScoreParameters _calculateScoreParams({
    required ShooterRating aRating,
    required RelativeScore aScore,
    required RelativeScore aMatchScore,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeScore> matchScores,
  }) {
    double expectedScore = 0;
    var highOpponentScore = 0.0;

    // our own score
    int usedScores = 1;
    var totalPercent = (aScore.percent * stageBlend) + (aMatchScore.percent * matchBlend);
    int zeroes = aScore.relativePoints < 0.1 ? 1 : 0;

    for(var bRating in scores.keys) {
      var opponentScore = scores[bRating]!;
      var opponentMatchScore = matchScores[bRating]!;

      // No credit against ourselves
      if(opponentScore == aScore) continue;

      if (opponentScore.relativePoints > highOpponentScore) {
        highOpponentScore = opponentScore.relativePoints;
      }

      if(opponentScore.relativePoints < 0.1) {
        zeroes += 1;
      }

      var probability = _probability(bRating.rating, aRating.rating);
      if (probability.isNaN) {
        throw StateError("NaN");
      }

      expectedScore += probability;
      totalPercent += (opponentScore.percent * stageBlend) + (opponentMatchScore.percent * matchBlend);
      usedScores++;
    }

    var divisor = ((usedScores * (usedScores - 1)) / 2);
    return _ScoreParameters(
      expectedScore: expectedScore / divisor,
      highOpponentScore: highOpponentScore,
      totalPercent: totalPercent,
      divisor: divisor,
      usedScores: usedScores,
      zeroes: zeroes,
    );
  }
  
  _ActualScore _calculateActualScore({
    required RelativeScore score,
    required RelativeScore matchScore,
    required _ScoreParameters params,
  }) {
    var actualPercent = (score.percent * stageBlend) + (matchScore.percent * matchBlend);
    if(score.percent == 1.0 && params.highOpponentScore > 0.1) {
      actualPercent = score.relativePoints / params.highOpponentScore;
      params.totalPercent += (actualPercent - 1.0);
    }

    var percentComponent = params.totalPercent == 0 ? 0.0 : (actualPercent / params.totalPercent);

    var placeBlend = ((score.place * stageBlend) + (matchScore.place * matchBlend)).toDouble();
    var placeComponent = (params.usedScores - placeBlend) /  params.divisor;

    return _ActualScore(
      placeComponent: placeComponent,
      percentComponent: percentComponent,
      actualPercent: actualPercent,
      placeBlend: placeBlend,
      score: percentComponent * percentWeight + placeComponent * placeWeight
    );
  }

  /// Return the probability that win beats lose.
  double _probability(double lose, double win) {
    return 1.0 / (1.0 + (pow(10, (lose - win) / scale)));
  }

  static const _leadPaddingFlex = 2;
  static const _placeFlex = 1;
  static const _memNumFlex = 2;
  static const _classFlex = 1;
  static const _nameFlex = 5;
  static const _ratingFlex = 2;
  static const _matchChangeFlex = 2;
  static const _uncertaintyFlex = 2;
  static const _errorFlex = 2;
  static const _connectednessFlex = 2;
  static const _trendFlex = 2;
  static const _stagesFlex = 2;
  static const _trailPaddingFlex = 2;

  @override
  Row buildRatingKey(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(flex: _leadPaddingFlex + _placeFlex, child: Text("")),
        Expanded(flex: _memNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Rating", textAlign: TextAlign.end)),
        Expanded(
            flex: _errorFlex,
            child: Tooltip(
                message:
                  "The error calculated by the rating system.",
                child: Text("Error", textAlign: TextAlign.end)
            )
        ),
        Expanded(
            flex: _matchChangeFlex,
            child: Tooltip(
                message:
                "The change in the shooter's rating at the last match.",
                child: Text("Last ±", textAlign: TextAlign.end)
            )
        ),
        Expanded(
          flex: _trendFlex,
          child: Tooltip(
            message: "The change in the shooter's rating, over the last 30 rating events.",
            child: Text("Trend", textAlign: TextAlign.end)
          )
        ),
        Expanded(
          flex: _connectednessFlex,
          child: Tooltip(
            message: "The shooter's connectedness, a measure of how much he shoots against other shooters in the set.",
            child: Text("Conn.", textAlign: TextAlign.end)
          )
        ),
        Expanded(flex: _stagesFlex, child: Text(byStage ? "Stages" : "Matches", textAlign: TextAlign.end)),
        Expanded(flex: _trailPaddingFlex, child: Text("")),
      ],
    );
  }

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating}) {
    rating as EloShooterRating;

    var trend = rating.trend;
    var error = rating.standardError;
    var lastMatchChange = rating.lastMatchChange;

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: _leadPaddingFlex, child: Text("")),
              Expanded(flex: _placeFlex, child: Text("$place")),
              Expanded(flex: _memNumFlex, child: Text(rating.shooter.memberNumber)),
              Expanded(flex: _classFlex, child: Text(rating.lastClassification.displayString())),
              Expanded(flex: _nameFlex, child: Text(rating.shooter.getName(suffixes: false))),
              Expanded(flex: _ratingFlex, child: Text("${rating.rating.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _errorFlex, child: Text("${error.toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _matchChangeFlex, child: Text("${lastMatchChange.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _trendFlex, child: Text("${trend.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _connectednessFlex, child: Text("${(rating.connectedness - ShooterRating.baseConnectedness).toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _stagesFlex, child: Text("${rating.length}", textAlign: TextAlign.end,)),
              Expanded(flex: _trailPaddingFlex, child: Text("")),
            ],
          )
      ),
    );
  }

  @override
  ShooterRating<EloShooterRating> copyShooterRating(EloShooterRating rating) {
    return EloShooterRating.copy(rating);
  }

  @override
  ShooterRating<EloShooterRating> newShooterRating(Shooter shooter, {DateTime? date}) {
    return EloShooterRating(shooter, initialClassRatings[shooter.classification] ?? 800.0, date: date);
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    String csv = "Member#,Name,Rating,LastChange,Error,Trend,${byStage ? "Stages" : "Matches"}\n";

    for(var s in ratings) {
      s as EloShooterRating;
      var trend = s.rating - s.averageRating().firstRating;

      var error = s.standardError;

      PracticalMatch? match;
      double lastMatchChange = 0;
      for(var event in s.ratingEvents.reversed) {
        if(match == null) {
          match = event.match;
        }
        else if(match != event.match) {
          break;
        }
        lastMatchChange += event.ratingChange;
      }

      csv += "${s.shooter.memberNumber},";
      csv += "${s.shooter.getName()},";
      csv += "${s.rating.round()},${lastMatchChange.round()},${error.toStringAsFixed(2)},${trend.toStringAsFixed(2)},${s.ratingEvents.length}\n";
    }
    return csv;
  }

  static const initialClassRatings = {
    Classification.GM: 1300.0,
    Classification.M: 1200.0,
    Classification.A: 1100.0,
    Classification.B: 1000.0,
    Classification.C: 900.0,
    Classification.D: 800.0,
    Classification.U: 900.0,
    Classification.unknown: 800.0,
  };

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[RatingProject.algorithmKey] = RatingProject.multiplayerEloValue;
    settings.encodeToJson(json);
  }

  @override
  RatingEvent newEvent({
    required PracticalMatch match,
    Stage? stage,
    required ShooterRating rating, required RelativeScore score, Map<String, List<dynamic>> info = const {}
  }) {
    return EloRatingEvent(oldRating: rating.rating, match: match, stage: stage, score: score, ratingChange: 0, info: info, baseK: 0, effectiveK: 0);
  }

  @override
  EloSettingsController newSettingsController() {
    return EloSettingsController();
  }

  @override
  EloSettingsWidget newSettingsWidget(EloSettingsController controller) {
    // create a new state when the controller changes
    return EloSettingsWidget(controller: controller);
  }

  static const monteCarloTrials = 1000;

  @override
  bool get supportsPrediction => true;

  @override
  bool get supportsValidation => true;

  @override
  List<ShooterPrediction> predict(List<ShooterRating> ratings) {
    List<EloShooterRating> eloRatings = List.castFrom(ratings);
    List<ShooterPrediction> predictions = [];

    for(var rating in eloRatings) {
      var error = rating.standardError;
      var stdDev = error;

      // Smaller compression factors mean more compression, 1.0 means no compression.
      var lowerCompressionFactor = 0.8;
      var upperCompressionFactor = 0.9;
      var compressionCenter = 100.0;
      if(error > compressionCenter) stdDev = compressionCenter + pow(stdDev - compressionCenter, upperCompressionFactor);
      else stdDev = compressionCenter - pow(compressionCenter - stdDev, lowerCompressionFactor);

      var errMultiplier = 1.0;
      if (error >= errThreshold) {
        errMultiplier = 1 + min(1.0, ((error - errThreshold) / (EloShooterRating.errorScale - errThreshold))) * 1;
      }
      else if (error < errThreshold) {
        errMultiplier = 1 - ((errThreshold - error) / errThreshold) * 0.5;
      }
      stdDev = stdDev * errMultiplier;

      var trends = [rating.shortTrend, rating.mediumTrend, rating.longTrend];

      var trendShiftMaxVal = 400;
      var trendShiftMaxMagnitude = 0.9;
      var trendShiftProportion = max(-1.0, min(1.0, trends.average / trendShiftMaxVal));
      var trendShift = trendShiftProportion * trendShiftMaxMagnitude;

      //List<double> possibleRatings = Normal.generate(monteCarloTrials, mean: rating.rating, variance: stdDev * stdDev);
      List<double> possibleRatings = Gumbel.generate(monteCarloTrials, mu: rating.rating, beta: stdDev);
      List<double> expectedScores = [];
      for(var maybeRating in possibleRatings) {
        var expectedScore = 0.0;
        for(var opponent in eloRatings) {
          if(opponent == rating) continue;
          expectedScore += _probability(opponent.rating, maybeRating);
        }
        var n = ratings.length;
        expectedScore = expectedScore / ((n * (n-1)) / 2);
        expectedScores.add(expectedScore);
      }

      var averagePerformance = expectedScores.average;
      var variance = expectedScores.map((e) => pow(e - averagePerformance, 2)).average;
      var performanceDeviation = sqrt(variance);

      predictions.add(ShooterPrediction(
        shooter: rating,
        mean: averagePerformance,
        ciOffset: trendShift,
        sigma: performanceDeviation,
      ));
    }

    return predictions;
  }

  @override
  PredictionOutcome validate({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeScore> matchScores,
    required List<ShooterPrediction> predictions
  }) {
    Map<ShooterRating, ShooterPrediction> shootersToPredictions = {};
    Map<ShooterPrediction, SimpleMatchResult> actualOutcomes = {};
    double errorSum = 0;
    List<double> errors = [];

    for(var prediction in predictions) {
      shootersToPredictions[prediction.shooter] = prediction;
    }

    int correct95 = 0;
    int correct68 = 0;
    for(var shooter in shooters) {
      var prediction = shootersToPredictions[shooter];
      if(prediction == null) {
        print("Null prediction for $shooter");
        continue;
      }

      var score = scores[shooter]!;
      var matchScore = matchScores[shooter]!;
      var params = _calculateScoreParams(aRating: shooter, aScore: score, aMatchScore: matchScore, scores: scores, matchScores: matchScores);
      var eloScore = _calculateActualScore(score: score, matchScore: matchScore, params: params);

      errors.add(eloScore.score - prediction.mean);
      errorSum += pow(eloScore.score - prediction.mean, 2);
      actualOutcomes[prediction] = SimpleMatchResult(raterScore: eloScore.score, percent: matchScore.percent, place: matchScore.place);

      if(eloScore.score >= prediction.mean - prediction.twoSigma + prediction.shift && eloScore.score <= prediction.mean + prediction.twoSigma + prediction.shift) {
        correct95 += 1;
      }
      if(eloScore.score >= prediction.mean - prediction.oneSigma + prediction.shift && eloScore.score <= prediction.mean + prediction.oneSigma + prediction.shift) {
        correct68 += 1;
      }
    }

    print("Actual outcomes for ${actualOutcomes.length} shooters yielded an error sum of ${errors.sum} and an average error of ${errors.average.toStringAsPrecision(3)}");
    print("Std. dev: ${(sqrt(errorSum) / predictions.length).toStringAsPrecision(3)} of ${predictions.map((e) => e.mean).average}");
    print("Score correct: $correct68/$correct95/${actualOutcomes.length} (${(correct68 / actualOutcomes.length * 100).toStringAsFixed(1)}%/${(correct95 / actualOutcomes.length * 100).toStringAsFixed(1)}%)");

    return PredictionOutcome(
      error: (sqrt(errorSum) / predictions.length), actualResults: actualOutcomes
    );
  }
}

class _ScoreParameters {
  double expectedScore;
  double highOpponentScore;
  double totalPercent;
  double divisor;
  int usedScores;
  int zeroes;

  _ScoreParameters({
    required this.expectedScore,
    required this.highOpponentScore,
    required this.totalPercent,
    required this.divisor,
    required this.usedScores,
    required this.zeroes,
  });
}

class _ActualScore {
  final double score;
  final double placeComponent;
  final double percentComponent;
  final double actualPercent;
  final double placeBlend;

  _ActualScore({
    required this.placeComponent,
    required this.percentComponent,
    required this.actualPercent,
    required this.placeBlend,
    required this.score,
  });
}