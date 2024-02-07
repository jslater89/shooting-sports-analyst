/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:normal/normal.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/gumbel.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/ui/elo_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/prediction_view.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';
import 'package:shooting_sports_analyst/util.dart';

class MultiplayerPercentEloRater extends RatingSystem<EloShooterRating, EloSettings, EloSettingsController> {
  static const errorKey = "error";
  static const baseKKey = "baseK";
  static const effectiveKKey = "effectiveK";
  static const matchScoreKey = "matchScore";

  static const doBackRating = false;
  static const backRatingErrorKey = "backRatingError";

  Timings timings = Timings();

  @override
  RatingMode get mode => RatingMode.oneShot;

  final EloSettings settings;

  /// K is the K parameter to the rating Elo algorithm
  double get K => settings.K;

  /// Probability base is the base used for the exponentiation in
  /// the Elo probability function, and says that someone with a
  /// rating margin of [scale] over another player is [probabilityBase]
  /// times more likely to win.
  double get probabilityBase => settings.probabilityBase;

  double get percentWeight => settings.percentWeight;
  double get placeWeight => settings.placeWeight;

  /// Scale is the scale parameter to the Elo probability function, and
  /// says that a rating difference of [scale] means the higher-rated
  /// player is [probabilityBase] times more likely to win.
  double get scale => settings.scale;

  double get matchBlend => settings.matchBlend;
  double get stageBlend => settings.stageBlend;

  @override
  bool get byStage => settings.byStage;
  bool get errorAwareK => settings.errorAwareK;
  bool get directionAwareK => settings.directionAwareK;
  bool get streakAwareK => settings.streakAwareK;

  double get streakLimit => settings.streakLimit;
  double get onStreakMultiplier => settings.directionAwareOnStreakMultiplier;
  double get offStreakMultiplier => settings.directionAwareOffStreakMultiplier;

  bool get bombProtection => settings.bombProtection;

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
    required PracticalMatch match,
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  }) {
    if(shooters.length != 1) {
      throw StateError("Incorrect number of shooters passed to MultiplayerElo");
    }

    if(scores.length == 0) {
      return {};
    }
    else if(scores.length == 1) {
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
    var params = _calculateScoreParams(
        match: match,
        aRating: aRating,
        aScore: aScore,
        aMatchScore: aMatchScore,
        scores: scores,
        matchScores: matchScores
    );
    if(Timings.enabled) timings.calcExpectedScore += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(params.usedScores == 1) {
      return {
        aRating: RatingChange(change: {
          RatingSystem.ratingKey: 0,
          errorKey: 0,
          baseKKey: 0,
          effectiveKKey: 0,
        }),
      };
    }

    if(Timings.enabled) start = DateTime.now();

    var actualScore = _calculateActualScore(match: match, score: aScore, matchScore: aMatchScore.total, params: params, isDnf: aMatchScore.isDnf);

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

    // Also adjust K based on the shooter's direction. Disable error-aware K if we're
    // on long mostly-positive/negative runs; adjust K in the same cases.
    //
    // This applies in both directions, for both positive and negative streaks, but in
    // other comments I describe this in terms of positive streaks only, for the sake of
    // my own sanity.
    var direction = aRating.shortDirection * 0.75 + aRating.direction * 0.25;
    var absDirection = direction.abs();

    var errMultiplier = 1.0;
    if(errorAwareK) {
        var errThreshold = settings.errorAwareMaxThreshold;
        final maxMultiplier = settings.errorAwareUpperMultiplier;
        final minMultiplier = settings.errorAwareLowerMultiplier;
        var minThreshold = settings.errorAwareMinThreshold;
        var zeroValue = settings.errorAwareZeroValue;
        if (error >= errThreshold) {
          errMultiplier = 1 + min(1.0, ((error - errThreshold) / (settings.scale - errThreshold))) * maxMultiplier;
        }
        else if (error < minThreshold && error >= zeroValue) {
          errMultiplier = 1 - ((minThreshold - error - zeroValue) / (minThreshold - zeroValue)) * minMultiplier;
        }
        else if (error < zeroValue) {
          errMultiplier = 1 - minMultiplier;
        }

        // If streak aware is on, don't reduce K for shooters on long runs.
        if(errMultiplier < 1.0 && (streakAwareK && absDirection >= streakLimit)) errMultiplier = 1.0;
    }

    var directionMultiplier = 1.0;
    if(directionAwareK && absDirection >= streakLimit) {
      if(direction.sign != (actualScore.score - params.expectedScore).sign) {
        // If this rating change goes opposite a streak, reduce K based on streak
        // length.
        directionMultiplier = 1.0
            - offStreakMultiplier * ((absDirection - streakLimit) / (1.0 - streakLimit));
      }
      else {
        // If this rating change is in the same direction as our streak, increase K.
        // (1.0x -> 1.5x) lerped over absDirection (streakLimit -> 1.0)
        directionMultiplier = 1.0
            + onStreakMultiplier * ((absDirection - streakLimit) / (1.0 - streakLimit));
      }
    }

    var expectedPercent = params.expectedScore * params.totalPercent * 100.0;
    var bombProtectionMultiplier = 1.0;

    if(bombProtection) {
      var baseChange = (actualScore.score - params.expectedScore) * K * (params.usedScores - 1);
      var lowerLimit = -K * settings.bombProtectionLowerThreshold;
      var upperLimit = -K * settings.bombProtectionUpperThreshold;
      var lowerPercent = settings.bombProtectionMinimumExpectedPercent;
      var difference = settings.bombProtectionMaximumExpectedPercent - lowerPercent;
      var minMult = settings.bombProtectionMinimumKReduction;
      var lerpedMult = settings.bombProtectionMaximumKReduction - minMult;
      if (expectedPercent > lowerPercent && baseChange < lowerLimit) {
        // Bomb protection gives you at most 75% reduction if your expected percent is 100% or more,
        // and at least 10% if your expected percent is 75% (assuming default settings).
        var multiplierBase = minMult + min(lerpedMult, lerpedMult * (expectedPercent - lowerPercent) / difference);

        var numerator = baseChange.abs() - lowerLimit.abs();
        var denominator = upperLimit.abs() - lowerLimit.abs();
        var ratio = numerator / denominator;
        bombProtectionMultiplier -= multiplierBase * min(1, max(0, ratio));
      }
    }

    var effectiveK = K
        * placementMultiplier
        * matchStrengthMultiplier
        * zeroMultiplier
        * connectednessMultiplier
        * eventWeightMultiplier
        * errMultiplier
        * directionMultiplier
        * bombProtectionMultiplier;

    var changeFromPercent = effectiveK * (params.usedScores - 1) * (actualScore.percentComponent * percentWeight - (params.expectedScore * percentWeight));
    var changeFromPlace = effectiveK * (params.usedScores - 1) * (actualScore.placeComponent * placeWeight - (params.expectedScore * placeWeight));

    var change = changeFromPlace + changeFromPercent;
    if(Timings.enabled) timings.updateRatings += (DateTime.now().difference(start).inMicroseconds).toDouble();

    if(change.isNaN || change.isInfinite) {
      debugPrint("### ${aRating.getName()} stats: ${actualScore.actualPercent} of ${params.usedScores} shooters for ${aScore.stage?.name}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}, placement $placementMultiplier, zero $zeroMultiplier (${params.zeroes})");
      debugPrint("AS/ES: ${actualScore.score.toStringAsFixed(6)}/${params.expectedScore.toStringAsFixed(6)}");
      debugPrint("Actual/expected percent: ${(actualScore.percentComponent * params.totalPercent * 100).toStringAsFixed(2)}/${(params.expectedScore * params.totalPercent * 100).toStringAsFixed(2)}");
      debugPrint("Actual/expected place: ${actualScore.placeBlend}/${(params.usedScores - (params.expectedScore * params.divisor)).toStringAsFixed(4)}");
      debugPrint("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      debugPrint("###");
      throw StateError("NaN/Infinite/really big");
    }

    var backRatingErr = 0.0;
    var backRatingRaw = 0.0;
    var stepSize = K * 2;
    int steps = 0;

    if(doBackRating) {
      // Back-prediction: what would your rating have had to be, for your expected score to be
      // your actual score?
      EloShooterRating backRating = EloShooterRating.copy(aRating);

      // Get an initial guess by working out how much changing the rating by the initial
      // step size will change a score
      var difference = actualScore.score - params.expectedScore;
      var initialRating = EloShooterRating.copy(backRating);
      initialRating.rating += stepSize * difference.sign;
      var backParams = _calculateScoreParams(
        match: match,
        aRating: initialRating,
        aScore: aScore,
        aMatchScore: aMatchScore,
        scores: scores,
        matchScores: matchScores
      );

      var oldDifference = difference;
      difference = actualScore.score - backParams.expectedScore;
      var scoreChange = (oldDifference - difference).abs();
      var scoreChangePerRating = scoreChange / stepSize;
      stepSize = difference.abs() / scoreChangePerRating;

      while (stepSize.abs() >= K * 0.1 && steps < 10) {
        backRating.rating += stepSize * difference.sign;

        var backParams = _calculateScoreParams(
          match: match,
          aRating: backRating,
          aScore: aScore,
          aMatchScore: aMatchScore,
          scores: scores,
          matchScores: matchScores
        );

        var oldDifference = difference;
        difference = actualScore.score - backParams.expectedScore;
        var scoreChange = (oldDifference - difference).abs();

        // We changed rating by stepSize, which changed the score miss by scoreChange.
        // At rating differences <<< scale, the probability change is basically linear.
        // So, assume a linear relationship and go from there.
        var scoreChangePerRating = scoreChange / stepSize;
        stepSize = difference.abs() / scoreChangePerRating;

        if (scoreChangePerRating.isNaN || scoreChangePerRating.isInfinite || stepSize.isNaN || stepSize.isInfinite || backRating.rating.isNaN ||
            backRating.rating.isInfinite) {
          debugPrint("pause");
          throw StateError("NaN");
        }

        if(scoreChange < 0.05 * difference || stepSize > scale * 4) {
          if(stepSize > scale * 4) {
            backRating.rating = aRating.rating * 1.5;
          }
          break;
        }

        steps += 1;
      }


      if(steps != 0) {
        backRatingRaw = backRating.rating;
        backRatingErr = aRating.rating - backRating.rating;
      }
      else {
        backRatingRaw = aRating.rating;
        backRatingErr = 0;
      }
    }

    if(Timings.enabled) start = DateTime.now();
    var hf = aScore.score.getHitFactor(scoreDQ: aScore.score.stage != null);
    Map<String, List<dynamic>> info = {
      "Actual/expected percent: %00.2f/%00.2f on %00.2fHF": [
        actualScore.percentComponent * params.totalPercent * 100, expectedPercent, hf
      ],
      "Actual/expected place: %00.1f/%00.1f": [
        actualScore.placeBlend, params.usedScores - (params.expectedScore * params.divisor)
      ],
      "Rating ± Change: %00.0f + %00.2f (%00.2f from pct, %00.2f from place)": [
        aRating.rating, change, changeFromPercent, changeFromPlace
      ],
      "eff. K, multipliers: %00.2f, SoS %00.3f, IP %00.3f, Zero %00.3f": [
        effectiveK, matchStrengthMultiplier, placementMultiplier, zeroMultiplier
      ],
      "Conn %00.3f, EW %00.3f, Err %00.3f, Dir %00.3f, Bomb %00.3f": [ // , Bomb %00.3f
        connectednessMultiplier, eventWeightMultiplier, errMultiplier, directionMultiplier, bombProtectionMultiplier
      ],
      if(doBackRating) "Back rating/error/steps/size: %00.0f/%00.1f/%d/%00.2f": [backRatingRaw, backRatingErr, steps, stepSize],
    };
    if(Timings.enabled) timings.printInfo += (DateTime.now().difference(start).inMicroseconds).toDouble();

    return {
      aRating: RatingChange(change: {
        RatingSystem.ratingKey: change,
        errorKey: (params.expectedScore - actualScore.score) * params.usedScores,
        baseKKey: K * (params.usedScores - 1),
        effectiveKKey: effectiveK * (params.usedScores),
        backRatingErrorKey: backRatingErr,
      },
      extraData: {
        matchScoreKey: aMatchScore,
      },
      info: info),
    };
  }

  _ScoreParameters _calculateScoreParams({
    PracticalMatch? match,
    required ShooterRating aRating,
    required RelativeScore aScore,
    required RelativeMatchScore aMatchScore,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
  }) {
    bool matchInProgress = match?.inProgress ?? false;

    double expectedScore = 0;
    var highOpponentScore = 0.0;

    // our own score
    int usedScores = 1;
    var totalPercent;

    if(_disableMatchBlend(matchInProgress, aScore.score.shooter.dq, aMatchScore.isDnf)) {
      // Give DQed shooters a break by not blending in the match score
      totalPercent = aScore.percent;
    }
    else {
      totalPercent = (aScore.percent * stageBlend) + (aMatchScore.total.percent * matchBlend);
    }

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
        debugPrint("NaN for ${bRating.rating} vs ${aRating.rating}");
        throw StateError("NaN");
      }

      var opponentPercent;
      if(_disableMatchBlend(matchInProgress, opponentScore.score.shooter.dq, opponentMatchScore.isDnf)) {
        // Give DQed shooters a break by not blending in the match score
        opponentPercent = opponentScore.percent;
      }
      else {
        opponentPercent = (opponentScore.percent * stageBlend) + (opponentMatchScore.total.percent * matchBlend);
      }

      expectedScore += probability;
      totalPercent += opponentPercent;
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

  bool _disableMatchBlend(bool matchInProgress, bool isDq, bool matchDnf) {
    return matchInProgress || (byStage && isDq) || (byStage && matchDnf);
  }
  
  _ActualScore _calculateActualScore({
    PracticalMatch? match,
    required RelativeScore score,
    required RelativeScore matchScore,
    required _ScoreParameters params,
    bool isDnf = false,
  }) {
    bool matchInProgress = match?.inProgress ?? false;

    var actualPercent;
    if(_disableMatchBlend(matchInProgress, score.score.shooter.dq, isDnf)) {
      // Give DQed shooters a break by not blending in the match score
      actualPercent = score.percent;
    }
    else {
      actualPercent = (score.percent * stageBlend) + (matchScore.percent * matchBlend);
    }

    if(score.percent == 1.0 && params.highOpponentScore > 0.1) {
      actualPercent = score.relativePoints / params.highOpponentScore;
      params.totalPercent += (actualPercent - 1.0);
    }

    var percentComponent = params.totalPercent == 0 ? 0.0 : (actualPercent / params.totalPercent);

    var placeBlend;
    if(_disableMatchBlend(matchInProgress, score.score.shooter.dq, isDnf)) {
      // Give DQed shooters a break by not blending in the match score
      placeBlend = score.place.toDouble();
    }
    else {
      placeBlend = ((score.place * stageBlend) + (matchScore.place * matchBlend)).toDouble();
    }
    var placeComponent = (params.usedScores - placeBlend) / params.divisor;

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
    return 1.0 / (1.0 + (pow(probabilityBase, (lose - win) / scale)));
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
  static const _directionFlex = 2;
  static const _stagesFlex = 2;
  static const _trailPaddingFlex = 2;

  @override
  Row buildRatingKey(BuildContext context) {
    var errorText = "The error calculated by the rating system.";
    if(doBackRating) {
      errorText += " A negative number means the calculated rating\n"
          "was too low. A positive number means the calculated rating was too high.";
    }
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
                message: errorText,
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
            flex: _directionFlex,
            child: Tooltip(
                message: "The shooter's rating trajectory: 100 if all of the last 30 rating events were positive, -100 if all were negative.",
                child: Text("Direction", textAlign: TextAlign.end)
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

    var trend = rating.trend.round();
    var positivity = (rating.direction * 100).round();
    var error = rating.standardError;
    if(doBackRating) {
      error = rating.backRatingError;
    }
    var lastMatchChange = rating.lastMatchChange;

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: _leadPaddingFlex, child: Text("")),
              Expanded(flex: _placeFlex, child: Text("$place")),
              Expanded(flex: _memNumFlex, child: Text(rating.originalMemberNumber)),
              Expanded(flex: _classFlex, child: Text(rating.lastClassification.displayString())),
              Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
              Expanded(flex: _ratingFlex, child: Text("${rating.rating.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _errorFlex, child: Text("${error.toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _matchChangeFlex, child: Text("${lastMatchChange.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _trendFlex, child: Text("$trend", textAlign: TextAlign.end)),
              Expanded(flex: _directionFlex, child: Text("$positivity", textAlign: TextAlign.end)),
              Expanded(flex: _connectednessFlex, child: Text("${(rating.connectedness - ShooterRating.baseConnectedness).toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _stagesFlex, child: Text("${rating.length}", textAlign: TextAlign.end,)),
              Expanded(flex: _trailPaddingFlex, child: Text("")),
            ],
          )
      ),
    );
  }

  @override
  ShooterRating copyShooterRating(EloShooterRating rating) {
    return EloShooterRating.copy(rating);
  }

  @override
  ShooterRating newShooterRating(Shooter shooter, {DateTime? date}) {
    return EloShooterRating(shooter, initialClassRatings[shooter.classification] ?? 800.0, date: date);
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    String csv = "Member#,Class,Name,Rating,LastChange,Error,Trend,Positivity,${byStage ? "Stages" : "Matches"}\n";

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

      csv += "${s.originalMemberNumber},";
      csv += "${s.lastClassification.name},";
      csv += "${s.getName(suffixes: false)},";
      csv += "${s.rating.round()},${lastMatchChange.round()},"
          "${error.toStringAsFixed(2)},"
          "${trend.toStringAsFixed(2)},"
          "${s.direction.toStringAsFixed(2)},"
          "${s.ratingEvents.length}\n";
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
    return EloRatingEvent(oldRating: rating.rating, match: match, stage: stage, score: score, ratingChange: 0, info: info, baseK: 0, effectiveK: 0, backRatingError: 0);
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

  List<RatingSortMode> get supportedSorts => [
    RatingSortMode.rating,
    RatingSortMode.classification,
    RatingSortMode.firstName,
    RatingSortMode.lastName,
    RatingSortMode.error,
    RatingSortMode.lastChange,
    RatingSortMode.trend,
    RatingSortMode.direction,
    RatingSortMode.stages,
  ];

  @override
  bool get supportsPrediction => true;

  @override
  bool get supportsValidation => true;

  @override
  List<ShooterPrediction> predict(List<ShooterRating> ratings, {int? seed}) {
    List<EloShooterRating> eloRatings = List.castFrom(ratings);
    List<ShooterPrediction> predictions = [];

    if(seed != null) {
      Gumbel.random = Random(seed);
    }

    for(var rating in eloRatings) {
      var error = rating.standardError;
      var stdDev = error;

      // Compression reduces the amount by which rating error far from compressionCenter
      // varies the size of error bars.
      // Smaller compression factors will yield wider error bars for people further from compressionCenter.
      // Essentially, this is a fluff factor to keep the system from predicting tiny errors for top shooters.
      var lowerCompressionFactor = 0.8;
      var upperCompressionFactor = 0.9;
      var compressionCenter = 100.0;
      if(error > compressionCenter) stdDev = compressionCenter + pow(stdDev - compressionCenter, upperCompressionFactor);
      else stdDev = compressionCenter - pow(compressionCenter - stdDev, lowerCompressionFactor);

      // If rating error is very high, increase the size of error bars. If it's very low, reduce the
      // size of error bars.
      var errThreshold = settings.errorAwareMaxThreshold;
      var minThreshold = settings.errorAwareMinThreshold;
      var errMultiplier = 1.0;
      if (error >= errThreshold) {
        errMultiplier = 1 + min(1.0, ((error - errThreshold) / (settings.scale - errThreshold))) * 1;
      }
      else if (error < minThreshold) {
        errMultiplier = 1 - ((minThreshold - error) / minThreshold) * 0.5;
      }
      stdDev = stdDev * errMultiplier;

      // Offset the ratings up or down around the center, based on the shooter's
      // trend. (If you're on an upward run, you get some upward shaping.)
      // var trends = [rating.shortDirection, rating.direction, rating.longDirection];
      var trendAverage = rating.shortTrend * 0.45 + rating.mediumTrend * 0.35 + rating.longTrend * 0.20;

      var trendShiftMaxVal = settings.scale / 2;
      var trendShiftMaxMagnitude = 0.9;
      var trendShiftProportion = max(-1.0, min(1.0, trendAverage / trendShiftMaxVal));
      var trendShift = trendShiftProportion * trendShiftMaxMagnitude;

      // Starting with the shooter's calculated rating, generate a bunch of potential ratings that could be the
      // actual, accurate representation of the shooter's skill, and average the win probability of all of those
      // potential ratings against the rest of the field.

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

    for(var prediction in predictions) {
      int topPlace = 1;
      int bottomPlace = 1;
      int medianPlace = 1;

      for(var other in predictions) {
        if(prediction == other) continue;

        // See tooltips in prediction_view.dart for some further explanation of these.
        if(prediction.highPrediction < other.halfLowPrediction) topPlace += 1;
        if(prediction.halfLowPrediction < other.halfHighPrediction) bottomPlace += 1;
        if(prediction.center < other.halfLowPrediction) medianPlace += 1;
      }

      prediction.highPlace = topPlace;
      prediction.lowPlace = bottomPlace;
      prediction.medianPlace = medianPlace;
    }

    return predictions;
  }

  @override
  PredictionOutcome validate({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required List<ShooterPrediction> predictions,
    bool chatty = true,
  }) {
    Map<ShooterRating, ShooterPrediction> shootersToPredictions = {};
    Map<ShooterPrediction, SimpleMatchResult> actualOutcomes = {};
    double errorSum = 0;
    List<double> errors = [];
    bool repredicted = false;

    // We have to re-predict if we don't have the same number of shooters and
    // predictions, because probabilities depend on N.
    if(shooters.length != predictions.length) {
      predictions = predict(shooters);
      repredicted = true;
    }

    for (var prediction in predictions) {
      shootersToPredictions[prediction.shooter] = prediction;
    }

    int correct95 = 0;
    int correct68 = 0;
    int correctPlace = 0;
    for(var shooter in shooters) {
      var prediction = shootersToPredictions[shooter];
      if(prediction == null) {
        print("Null prediction for $shooter");
        continue;
      }

      var score = scores[shooter]!;
      var matchScore = matchScores[shooter]!;
      var params = _calculateScoreParams(aRating: shooter, aScore: score, aMatchScore: matchScore, scores: scores, matchScores: matchScores);
      var eloScore = _calculateActualScore(score: score, matchScore: matchScore.total, params: params, isDnf: matchScore.isDnf);

      errors.add(eloScore.score - prediction.mean);
      errorSum += pow(eloScore.score - prediction.mean, 2);
      actualOutcomes[prediction] = SimpleMatchResult(raterScore: eloScore.score, percent: matchScore.total.percent, place: matchScore.total.place);

      if(eloScore.score >= prediction.mean - prediction.twoSigma + prediction.shift && eloScore.score <= prediction.mean + prediction.twoSigma + prediction.shift) {
        correct95 += 1;
      }
      if(eloScore.score >= prediction.mean - prediction.oneSigma + prediction.shift && eloScore.score <= prediction.mean + prediction.oneSigma + prediction.shift) {
        correct68 += 1;
      }
      if(matchScore.total.place <= prediction.lowPlace && matchScore.total.place >= prediction.highPlace) {
        correctPlace += 1;
      }
    }

    if(chatty) {
      print("Actual outcomes for ${actualOutcomes.length} shooters yielded an error sum of ${errors.sum} and an average error of ${errors.average.toStringAsPrecision(3)}");
      print("Std. dev: ${(sqrt(errorSum) / predictions.length).toStringAsPrecision(3)} of ${predictions.map((e) => e.mean).average}");
      print("Score correct: $correct68/$correct95/${actualOutcomes.length} (${(correct68 / actualOutcomes.length).asPercentage(decimals: 1)}%/${(correct95 / actualOutcomes.length * 100).toStringAsFixed(1)}%)");
      print("Place correct: $correctPlace/${actualOutcomes.length} (${(correctPlace / actualOutcomes.length).asPercentage(decimals: 1)}%)");
    }

    return PredictionOutcome(
      error: (sqrt(errorSum) / predictions.length), actualResults: actualOutcomes, mutatedInputs: repredicted,
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