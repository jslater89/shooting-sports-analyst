import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/sorted_list.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

const _kKey = "k";
const _pctWeightKey = "pctWt";
const _scaleKey = "scale";
const _matchBlendKey = "matchBlend";
const _errorAwareKKey = "errK";

class MultiplayerPercentEloRater implements RatingSystem<EloShooterRating> {
  static const ratingKey = "rating";
  static const errorKey = "error";

  static const defaultK = 60.0;
  static const defaultPercentWeight = 0.4;
  static const defaultPlaceWeight = 0.6;
  static const defaultScale = 800.0;
  static const defaultMatchBlend = 0.0;

  @override
  RatingMode get mode => RatingMode.oneShot;

  /// K is the K parameter to the rating Elo algorithm
  final double K;
  final double percentWeight;
  final double placeWeight;
  final double scale;
  final double _matchBlend;

  double get matchBlend => _matchBlend;
  double get stageBlend => 1 - _matchBlend;

  @override
  final bool byStage;

  final bool errorAwareK;

  MultiplayerPercentEloRater({
    this.K = defaultK,
    this.scale = defaultScale,
    this.percentWeight = defaultPercentWeight,
    double matchBlend = defaultMatchBlend,
    required this.byStage,
    required this.errorAwareK,
  })
      : this.placeWeight = 1.0 - percentWeight,
        this._matchBlend = byStage ? matchBlend : 0.0 {
    EloShooterRating.errorScale = this.scale;
  }

  factory MultiplayerPercentEloRater.fromJson(Map<String, dynamic> json) {

    // fix my oopsie
    if(!(json[_errorAwareKKey] is bool)) {
      json[_errorAwareKKey] = false;
    }

    return MultiplayerPercentEloRater(
      K: (json[_kKey] ?? defaultK) as double,
      percentWeight: (json[_pctWeightKey] ?? defaultPercentWeight) as double,
      scale: (json[_scaleKey] ?? defaultScale) as double,
      matchBlend: (json[_matchBlendKey] ?? defaultMatchBlend) as double,
      byStage: (json[RatingProject.byStageKey] ?? true) as bool,
      errorAwareK: (json[_errorAwareKKey] ?? false) as bool,
    );
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
          ratingKey: 0,
          errorKey: 0,
        }),
      };
    }

    var aRating = shooters[0] as EloShooterRating;
    var aScore = scores[aRating]!;
    var aMatchScore = matchScores[aRating]!;

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

    if(usedScores == 1) {
      return {
        shooters[0]: RatingChange(change: {
          ratingKey: 0,
          errorKey: 0,
        }),
      };
    }

    var divisor = (usedScores * (usedScores - 1)) / 2;

    // TODO: solve my expected-percent-above-100 issue
    // I might be able to solve this by distributing percent actual score more like it's distributed for placement:
    // pick a floor for percent points for last place, and adjust the intervals on the way up by relative finish.
    // This is, however, a good soft cap on pubstompers.
    expectedScore = (expectedScore) / divisor;

    var actualPercent = (aScore.percent * stageBlend) + (aMatchScore.percent * matchBlend);
    if(aScore.percent == 1.0 && highOpponentScore > 0.1) {
      actualPercent = aScore.relativePoints / highOpponentScore;
      totalPercent += (actualPercent - 1.0);
    }

    var percentComponent = totalPercent == 0 ? 0 : (actualPercent / totalPercent);

    var placeBlend = (aScore.place * stageBlend) + (aMatchScore.place * matchBlend);
    var placeComponent = (usedScores - placeBlend) /  divisor;

    // The first N matches you shoot get bonuses for initial placement.
    var placementMultiplier = aRating.ratingEvents.length < RatingSystem.initialPlacementMultipliers.length ?
      RatingSystem.initialPlacementMultipliers[aRating.ratingEvents.length] : 1.0;

    // If lots of people zero a stage, we can't reason effectively about the relative
    // differences in performance of those people, compared to each other or compared
    // to the field that didn't zero it. If more than 10% of people zero a stage, start
    // scaling K down (to 0.34, when 30%+ of people zero a stage).
    var zeroMultiplier = (zeroes / usedScores) < 0.1 ? 1 : 1 - 0.66 * ((min(0.3, (zeroes / usedScores) - 0.1)) / 0.3);

    var error = aRating.normalizedErrorWithWindow();
    var errThreshold = EloShooterRating.errorScale / (K / 7.5);
    var errMultiplier = 1.0;
    if(errorAwareK) {
      if (error >= errThreshold) {
        errMultiplier = 1 + ((error - errThreshold) / (EloShooterRating.errorScale - errThreshold)) * 1;
      }
      else if (error < (errThreshold * 0.75)) {
        errMultiplier = 1 - (((errThreshold * 0.75) - error) / (errThreshold * 0.75)) * 0.9;
      }
    }

    var actualScore = percentComponent * percentWeight + placeComponent * placeWeight;
    var effectiveK = K * placementMultiplier * matchStrengthMultiplier * zeroMultiplier * connectednessMultiplier * eventWeightMultiplier * errMultiplier;

    var changeFromPercent = effectiveK * (usedScores - 1) * (percentComponent * percentWeight - (expectedScore * percentWeight));
    var changeFromPlace = effectiveK * (usedScores - 1) * (placeComponent * placeWeight - (expectedScore * placeWeight));

    var change = changeFromPlace + changeFromPercent;

    if(change.isNaN || change.isInfinite) {
      debugPrint("### ${aRating.shooter.lastName} stats: $actualPercent of $usedScores shooters for ${aScore.stage?.name}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}, placement $placementMultiplier, zero $zeroMultiplier ($zeroes)");
      debugPrint("AS/ES: ${actualScore.toStringAsFixed(6)}/${expectedScore.toStringAsFixed(6)}");
      debugPrint("Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)}");
      debugPrint("Actual/expected place: $placeBlend/${(usedScores - (expectedScore * divisor)).toStringAsFixed(4)}");
      debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      debugPrint("###");
      throw StateError("NaN/Infinite");
    }

    var hf = aScore.score.getHitFactor(scoreDQ: aScore.score.stage != null);
    List<String> info = [
      "Actual/expected percent: ${(percentComponent * totalPercent * 100).toStringAsFixed(2)}/${(expectedScore * totalPercent * 100).toStringAsFixed(2)} on ${hf.toStringAsFixed(2)}HF",
      "Actual/expected place: $placeBlend/${(usedScores - (expectedScore * divisor)).toStringAsFixed(4)}",
      "Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)",
      "eff. K, multipliers: ${(effectiveK).toStringAsFixed(2)}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}, IP ${placementMultiplier.toStringAsFixed(2)}, Zero ${zeroMultiplier.toStringAsFixed(2)}, Conn ${connectednessMultiplier.toStringAsFixed(2)}, EW ${eventWeightMultiplier.toStringAsFixed(2)}, Err ${errMultiplier.toStringAsFixed(2)}",
    ];

    return {
      aRating: RatingChange(change: {
        ratingKey: change,
        errorKey: (expectedScore - actualScore) * usedScores
      }, info: info),
    };
  }

  /// Return the probability that win beats lose.
  double _probability(double lose, double win) {
    return 1.0 / (1.0 + (pow(10, (lose - win) / scale)));
  }

  static const _leadPaddingFlex = 1;
  static const _placeFlex = 2;
  static const _memNumFlex = 3;
  static const _nameFlex = 5;
  static const _ratingFlex = 2;
  static const _uncertaintyFlex = 2;
  static const _errorFlex = 2;
  static const _connectednessFlex = 2;
  static const _trendFlex = 2;
  static const _stagesFlex = 2;
  static const _trailPaddingFlex = 1;

  @override
  Row buildRatingKey(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(flex: _leadPaddingFlex + _placeFlex, child: Text("")),
        Expanded(flex: _memNumFlex, child: Text("Member #")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Rating", textAlign: TextAlign.end)),
        Expanded(
            flex: _errorFlex,
            child: Tooltip(
                message:
                  "The likely error calculated by the rating system.",
                child: Text("Raw Error", textAlign: TextAlign.end)
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
    var trend = rating.rating - rating.averageRating().firstRating;

    rating as EloShooterRating;

    var error = rating.normalizedErrorWithWindow();

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: _leadPaddingFlex, child: Text("")),
              Expanded(flex: _placeFlex, child: Text("$place")),
              Expanded(flex: _memNumFlex, child: Text(rating.shooter.memberNumber)),
              Expanded(flex: _nameFlex, child: Text(rating.shooter.getName(suffixes: false))),
              Expanded(flex: _ratingFlex, child: Text("${rating.rating.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _errorFlex, child: Text("${error.toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _trendFlex, child: Text("${trend.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _connectednessFlex, child: Text("${(rating.connectedness - ShooterRating.baseConnectedness).toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _stagesFlex, child: Text("${rating.ratingEvents.length}", textAlign: TextAlign.end,)),
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
    String csv = "Member#,Name,Rating,Variance,Trend,${byStage ? "Stages" : "Matches"}\n";

    for(var s in ratings) {
      s as EloShooterRating;
      csv += "${s.shooter.memberNumber},";
      csv += "${s.shooter.getName()},";
      csv += "${s.rating.round()},${s.variance.toStringAsFixed(2)},${s.trend.toStringAsFixed(2)},${s.ratingEvents.length}\n";
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
    json[RatingProject.byStageKey] = byStage;
    json[_kKey] = K;
    json[_pctWeightKey] = percentWeight;
    json[_scaleKey] = scale;
    json[_matchBlendKey] = _matchBlend;
    json[_errorAwareKKey] = errorAwareK;
  }

  @override
  RatingEvent newEvent({required ShooterRating rating, required String eventName, required RelativeScore score, List<String> info = const []}) {
    return EloRatingEvent(oldRating: rating.rating, eventName: eventName, score: score, ratingChange: 0, info: info);
  }
}