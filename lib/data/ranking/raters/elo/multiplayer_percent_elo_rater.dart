/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_system_ui_data.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MultiplayerPctEloRater");

class MultiplayerPercentEloRater extends RatingSystem<EloShooterRating, EloSettings> {
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
  String formatNumericRating(double rating) {
    return rating.round().toString();
  }

  @override
  String formatNumericRatingChange(double ratingChange) {
    return ratingChange.toStringAsFixed(1);
  }

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({
    required ShootingMatch match,
    bool isMatchOngoing = false,
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
          RatingSystem.ratingChangeKey: 0,
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
    if(Timings.enabled) timings.add(TimingType.calcExpected, DateTime.now().difference(start).inMicroseconds);

    if(params.usedScores == 1) {
      return {
        aRating: RatingChange(change: {
          RatingSystem.ratingChangeKey: 0,
          errorKey: 0,
          baseKKey: 0,
          effectiveKKey: 0,
        }),
      };
    }

    if(Timings.enabled) start = DateTime.now();

    var actualScore = _calculateActualScore(match: match, score: aScore, matchScore: aMatchScore, params: params, isDnf: aMatchScore.isDnf);

    var aLength = aRating.length;
    // The first N matches you shoot get bonuses for initial placement.
    var placementMultiplier = aLength < RatingSystem.initialPlacementMultipliers.length ?
      RatingSystem.initialPlacementMultipliers[aLength] : 1.0;

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
    if(Timings.enabled) timings.add(TimingType.updateRatings, DateTime.now().difference(start).inMicroseconds);

    if(change.isNaN || change.isInfinite) {
      MatchStage? stage;
      if(aScore is RelativeStageScore) {
        stage = aScore.stage;
      }
      _log.w("### ${aRating.getName()} stats: ${actualScore.actualPercent} of ${params.usedScores} shooters for ${stage?.name}, SoS ${matchStrengthMultiplier.toStringAsFixed(3)}, placement $placementMultiplier, zero $zeroMultiplier (${params.zeroes})");
      _log.w("AS/ES: ${actualScore.score.toStringAsFixed(6)}/${params.expectedScore.toStringAsFixed(6)}");
      _log.w("Actual/expected percent: ${(actualScore.percentComponent * params.totalPercent * 100).toStringAsFixed(2)}/${(params.expectedScore * params.totalPercent * 100).toStringAsFixed(2)}");
      _log.w("Actual/expected place: ${actualScore.placeBlend}/${(params.usedScores - (params.expectedScore * params.divisor)).toStringAsFixed(4)}");
      _log.w("Rating±Change: ${aRating.rating.round()} + ${change.toStringAsFixed(2)} (${changeFromPercent.toStringAsFixed(2)} from pct, ${changeFromPlace.toStringAsFixed(2)} from place)");
      _log.w("###");
      throw StateError("NaN/Infinite/really big");
    }

    var backRatingErr = 0.0;
    // ignore: unused_local_variable
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
          _log.w("pause");
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
    late RawScore rawScore;
    if(aScore is RelativeMatchScore) {
      rawScore = aScore.total;
    }
    else {
      aScore as RelativeStageScore;
      rawScore = aScore.score;
    }

    List<String> infoLines = [
      "@tpl:eloV1",
    ];
    List<RatingEventInfoElement> infoData = [
      RatingEventInfoElement.string(name: "stage", stringValue: rawScore.displayString),
      RatingEventInfoElement.double(name: "pcActual", doubleValue: actualScore.percentComponent * params.totalPercent * 100, numberFormat: "%00.2f"),
      RatingEventInfoElement.double(name: "pcExpected", doubleValue: expectedPercent, numberFormat: "%00.2f"),
      RatingEventInfoElement.double(name: "placeActual", doubleValue: actualScore.placeBlend, numberFormat: "%00.1f"),
      RatingEventInfoElement.double(name: "placeExpected", doubleValue: params.usedScores - (params.expectedScore * params.divisor), numberFormat: "%00.1f"),
      RatingEventInfoElement.double(name: "rating", doubleValue: aRating.rating, numberFormat: "%00.0f"),
      RatingEventInfoElement.double(name: "change", doubleValue: change, numberFormat: "%00.2f"),
      RatingEventInfoElement.double(name: "eloFromPct", doubleValue: changeFromPercent, numberFormat: "%00.2f"),
      RatingEventInfoElement.double(name: "eloFromPlace", doubleValue: changeFromPlace, numberFormat: "%00.2f"),
      RatingEventInfoElement.double(name: "effK", doubleValue: effectiveK, numberFormat: "%00.2f"),
      RatingEventInfoElement.double(name: "sos", doubleValue: matchStrengthMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "ip", doubleValue: placementMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "zero", doubleValue: zeroMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "conn", doubleValue: connectednessMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "ew", doubleValue: eventWeightMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "err", doubleValue: errMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "dir", doubleValue: directionMultiplier, numberFormat: "%00.3f"),
      RatingEventInfoElement.double(name: "bomb", doubleValue: bombProtectionMultiplier, numberFormat: "%00.3f"),
    ];

    return {
      aRating: RatingChange(change: {
        RatingSystem.ratingChangeKey: change,
        errorKey: (params.expectedScore - actualScore.score) * params.usedScores,
        baseKKey: K * (params.usedScores - 1),
        effectiveKKey: effectiveK * (params.usedScores),
        backRatingErrorKey: backRatingErr,
      },
      infoLines: infoLines,
      infoData: infoData,
    )};
  }

  @override
  RatingChange noOpChangeFor({
    required EloShooterRating shooter,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    required NonRatingResultReason reason,
  }) {
    return RatingChange(
      change: {
        RatingSystem.ratingChangeKey: 0,
        errorKey: 0,
        baseKKey: 0,
        effectiveKKey: 0,
        backRatingErrorKey: 0,
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

  // TODO: investigate softmax for scaling expected scores
  _ScoreParameters _calculateScoreParams({
    ShootingMatch? match,
    required ShooterRating aRating,
    required RelativeScore aScore,
    required RelativeMatchScore aMatchScore,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
  }) {
    bool matchInProgress = match?.inProgress ?? false;

    double expectedScore = 0;
    double highOpponentRatio = 0.0;

    // our own score
    int usedScores = 1;
    var totalPercent;

    if(_disableMatchBlend(matchInProgress, aScore.shooter.dq, aMatchScore.isDnf)) {
      // Give DQed shooters a break by not blending in the match score
      totalPercent = aScore.ratio;
    }
    else {
      totalPercent = (aScore.ratio * stageBlend) + (aMatchScore.ratio * matchBlend);
    }

    /// TODO: turn off for time plus?
    int zeroes = aScore.points < 0.1 ? 1 : 0;

    for(var bRating in scores.keys) {
      var opponentScore = scores[bRating]!;
      var opponentMatchScore = matchScores[bRating]!;

      // No credit against ourselves
      if(opponentScore == aScore) continue;

      if (opponentScore.ratio > highOpponentRatio) {
        highOpponentRatio = opponentScore.ratio;
      }

      if(opponentScore.points < 0.1) {
        zeroes += 1;
      }

      var probability = _probability(bRating.rating, aRating.rating);
      if (probability.isNaN) {
        _log.e("NaN for ${bRating.rating} vs ${aRating.rating}");
        throw StateError("NaN");
      }

      var opponentPercent;
      if(_disableMatchBlend(matchInProgress, opponentScore.shooter.dq, opponentMatchScore.isDnf)) {
        // Give DQed shooters a break by not blending in the match score
        opponentPercent = opponentScore.ratio;
      }
      else {
        opponentPercent = (opponentScore.ratio * stageBlend) + (opponentMatchScore.ratio * matchBlend);
      }

      expectedScore += probability;
      totalPercent += opponentPercent;
      usedScores++;
    }

    var divisor = ((usedScores * (usedScores - 1)) / 2);
    return _ScoreParameters(
      expectedScore: expectedScore / divisor,
      highOpponentRatio: highOpponentRatio,
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
    ShootingMatch? match,
    required RelativeScore score,
    required RelativeScore matchScore,
    required _ScoreParameters params,
    bool isDnf = false,
  }) {
    // TODO: put this in project settings eventually.
    bool matchInProgress = false;

    double actualPercent;
    if(_disableMatchBlend(matchInProgress, score.shooter.dq, isDnf)) {
      // Give DQed shooters a break by not blending in the match score
      actualPercent = score.ratio;
    }
    else {
      actualPercent = (score.ratio * stageBlend) + (matchScore.ratio * matchBlend);
    }

    if(score.ratio == 1.0 && params.highOpponentRatio > 0.1) {
      actualPercent = score.ratio / params.highOpponentRatio;
      params.totalPercent += (actualPercent - 1.0);
    }

    var percentComponent = params.totalPercent == 0 ? 0.0 : (actualPercent / params.totalPercent);

    var placeBlend;
    if(_disableMatchBlend(matchInProgress, score.shooter.dq, isDnf)) {
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

  @override
  ShooterRating copyShooterRating(EloShooterRating rating) {
    return EloShooterRating.copy(rating);
  }

  @override
  ShooterRating newShooterRating(MatchEntry shooter, {required Sport sport, required DateTime date}) {
    return EloShooterRating(shooter, sport.initialEloRatings[shooter.classification] ?? 800.0, sport: sport, date: date);
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    String csv = "Member#,Class,Name,Rating,LastChange,Error,Trend,MinRating,MaxRating,Positivity,${byStage ? "Stages" : "Matches"}\n";

    for(var s in ratings) {
      s as EloShooterRating;
      var trend = s.rating - s.averageRating().firstRating;

      var error = s.standardError;

      double lastMatchChange = s.lastMatchChange;

      csv += "${s.originalMemberNumber},";
      csv += "${s.lastClassification?.name ?? "?"},";
      csv += "${s.getName(suffixes: false).replaceAll(RegExp(r'[",]', caseSensitive: false), "")},"; // sanitize for CSV
      csv += "${s.rating.round()},${lastMatchChange.round()},"
          "${error.toStringAsFixed(2)},"
          "${trend.toStringAsFixed(2)},"
          "${s.careerMinimumRating.round()},${s.careerMaximumRating.round()},"
          "${s.direction.toStringAsFixed(2)},"
          "${s.length}\n";
    }
    return csv;
  }

  @override
  List<JsonShooterRating> ratingsToJson(List<ShooterRating> ratings) {
    return ratings.map((e) => JsonShooterRating.fromShooterRating(e)).toList();
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[DbRatingProject.algorithmKey] = DbRatingProject.multiplayerEloValue;
    settings.encodeToJson(json);
  }

  @override
  RatingEvent newEvent({
    required ShootingMatch match,
    MatchStage? stage,
    required ShooterRating rating,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  }) {
    return EloRatingEvent(
      oldRating: rating.rating,
      match: match,
      stage: stage,
      score: score,
      matchScore: matchScore,
      ratingChange: 0,
      infoLines: infoLines,
      infoData: infoData,
      baseK: 0,
      effectiveK: 0,
      backRatingError: 0
    );
  }

  @override
  EloShooterRating wrapDbRating(DbShooterRating rating) {
    return EloShooterRating.wrapDbRating(rating);
  }
  static const monteCarloTrials = 1000;

  static const _leadPaddingFlex = 2;
  static const _placeFlex = 1;
  static const _memNumFlex = 2;
  static const _classFlex = 1;
  static const _nameFlex = 5;
  static const _ratingFlex = 2;
  static const _matchChangeFlex = 2;
  // ignore: unused_field
  static const _uncertaintyFlex = 2;
  static const _errorFlex = 2;
  static const _connectednessFlex = 2;
  static const _trendFlex = 2;
  static const _directionFlex = 2;
  static const _stagesFlex = 2;
  static const _trailPaddingFlex = 2;

  @override
  List<RatingRowData> buildRatingKeyData({DateTime? trendDate, RatingSortMode? sortMode}) {
    return [
      RatingRowData(data: "", flex: _leadPaddingFlex + _placeFlex),
      RatingRowData(data: "Member #", flex: _memNumFlex),
      RatingRowData(data: "Class", flex: _classFlex),
      RatingRowData(data: "Name", flex: _nameFlex),
      RatingRowData(data: "Rating", alignment: AbstractAlignment.end, flex: _ratingFlex),
      RatingRowData(
        data: "Error",
        tooltip: "The error calculated by the rating system.",
        alignment: AbstractAlignment.end,
        flex: _errorFlex,
      ),
      RatingRowData(
        data: "Last ±",
        tooltip: "The change in the shooter's rating at the last match.",
        alignment: AbstractAlignment.end,
        flex: _matchChangeFlex,
      ),
      RatingRowData(
        data: "Trend",
        tooltip: trendDate != null ? "The change in the shooter's rating since ${DateFormat.yMd().format(trendDate)}." : "The change in the shooter's rating over the last 30 rating events.",
        alignment: AbstractAlignment.end,
        flex: _trendFlex,
      ),
      RatingRowData(
        data: "Direction",
        tooltip: "The shooter's rating trajectory: 100 if all of the last 30 rating events were positive, -100 if all were negative.",
        alignment: AbstractAlignment.end,
        flex: _directionFlex,
      ),
      RatingRowData(
        data: "Conn.",
        tooltip: "The shooter's connectedness, a measure of how much he shoots against other shooters in the set.",
        alignment: AbstractAlignment.end,
        flex: _connectednessFlex,
      ),
      RatingRowData(data: byStage ? "Stages" : "Matches", alignment: AbstractAlignment.end, flex: _stagesFlex),
      RatingRowData(data: "", flex: _trailPaddingFlex),
    ];
  }

  @override
  List<RatingRowData> buildRatingRowData({required ShooterRating rating, required int place, DateTime? trendDate, RatingScaler? scaler, RatingSortMode? sortMode}) {
    rating as EloShooterRating;

    var trend = rating.trend.round();
    if(trendDate != null) {
      var forDate = rating.ratingForDate(trendDate);
      trend = (rating.rating - forDate).round();
      // _log.vv("rating: ${rating.rating}, date: $trendDate, forDate: $forDate, trend: $trend");
    }
    var positivity = (rating.direction * 100).round();
    var error = rating.standardError; //rating.decayingAverageRatingChangeError;
    if(MultiplayerPercentEloRater.doBackRating) {
      error = rating.backRatingError;
    }
    var lastMatchChange = rating.lastMatchChange;

    var ratingNumber = rating.rating.round();
    if(scaler != null) {
      ratingNumber = scaler.scaleRating(rating.rating, group: rating.group).round();
      error = scaler.scaleNumber(error, originalRating: rating.rating, group: rating.group);
      lastMatchChange = scaler.scaleNumber(lastMatchChange, originalRating: rating.rating);
      trend = scaler.scaleNumber(rating.trend, originalRating: rating.rating).round();
    }

    return [
      RatingRowData(data: "", flex: _leadPaddingFlex),
      RatingRowData(data: "$place", flex: _placeFlex),
      RatingRowData(data: rating.memberNumber, flex: _memNumFlex),
      RatingRowData(data: rating.lastClassification?.shortDisplayName ?? "?", flex: _classFlex),
      RatingRowData(data: rating.getName(suffixes: false), flex: _nameFlex),
      RatingRowData(data: "$ratingNumber", alignment: AbstractAlignment.end, flex: _ratingFlex),
      RatingRowData(data: "${error.toStringAsFixed(1)}", alignment: AbstractAlignment.end, flex: _errorFlex),
      RatingRowData(data: "${lastMatchChange.toStringAsFixed(1)}", alignment: AbstractAlignment.end, flex: _matchChangeFlex),
      RatingRowData(data: "$trend", alignment: AbstractAlignment.end, flex: _trendFlex),
      RatingRowData(data: "$positivity", alignment: AbstractAlignment.end, flex: _directionFlex),
      RatingRowData(data: "${(rating.connectivity).toStringAsFixed(1)}", alignment: AbstractAlignment.end, flex: _connectednessFlex),
      RatingRowData(data: "${rating.length}", alignment: AbstractAlignment.end, flex: _stagesFlex),
      RatingRowData(data: "", flex: _trailPaddingFlex),
    ];
  }

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
  PredictionSettings get predictionSettings => PredictionSettings(
    placeSigmaMultiplier: 1.0,
    percentSigmaMultiplier: 2.0,
    spreadSigmaMultiplier: 1.0,
  );

  @override
  bool get supportsValidation => true;

  @override
  List<AlgorithmPrediction> predict(List<ShooterRating> ratings, {int? seed, DateTime? matchDate}) {
    List<EloShooterRating> eloRatings = List.castFrom(ratings);
    List<AlgorithmPrediction> predictions = [];

    Random r;
    if(seed != null) {
      r = Random(seed);
    }
    else {
      r = Random();
    }

    double bestRating = double.negativeInfinity;
    double worstRating = double.infinity;

    for(var rating in eloRatings) {
      bestRating = max(bestRating, rating.rating);
      worstRating = min(worstRating, rating.rating);
    }

    double ratioFloor = estimateRatioFloor(bestRating - worstRating);
    double ratioMultiplier = 1.0 - ratioFloor;

    double highPrediction = 0;

    for(var rating in eloRatings) {
      var error = rating.standardError;
      var scale = settings.scale;

      // Error range thresholds
      // These are tuned with the default scale of 400.0, and
      // standardError uses scale as a scaling factor, so we need
      // to adjust the thresholds here to maintain the same relative
      // error ranges for different settings.
      final lowErrorThreshold = 10.0 * (scale / 400.0);
      final midErrorThreshold = 40.0 * (scale / 400.0);
      final highErrorMaxThreshold = 80.0 * (scale / 400.0);  // Explicit maximum error that maps to maxPercent

      // Percentage ranges for each error level
      const lowErrorMinPercent = 0.025;  // 2.5%
      const lowErrorMaxPercent = 0.045;  // 4.5%
      const midErrorMinPercent = 0.045;  // 4.5%
      const midErrorMaxPercent = 0.0575; // 5.5%
      const highErrorMinPercent = 0.0575; // 5.75%
      const highErrorMaxPercent = 0.065;  // 6.5%

      // Map error ranges to percentage of rating
      double errorPercentage;
      if (error < lowErrorThreshold) {
        errorPercentage = lowErrorMinPercent +
            (error / lowErrorThreshold) *
                (lowErrorMaxPercent - lowErrorMinPercent);
      } else if (error < midErrorThreshold) {
        errorPercentage = midErrorMinPercent +
            (error - lowErrorThreshold) /
                (midErrorThreshold - lowErrorThreshold) *
                (midErrorMaxPercent - midErrorMinPercent);
      } else {
        errorPercentage = highErrorMinPercent +
            min(
              highErrorMaxPercent - highErrorMinPercent,
              (error - midErrorThreshold) /
                  (highErrorMaxThreshold - midErrorThreshold) *
                  (highErrorMaxPercent - highErrorMinPercent),
            );
      }

      var stdDev = rating.rating * errorPercentage;

      // If rating error is very high, increase the size of error bars. If it's very low, reduce the
      // size of error bars.
      var errThreshold = settings.errorAwareMaxThreshold;
      var minThreshold = settings.errorAwareMinThreshold;
      var errMultiplier = 1.0;
      if (error >= errThreshold) {
        errMultiplier = 1 + min(0.5, ((error - errThreshold) / (scale - errThreshold))) * 1;
      }
      if (error < minThreshold) {
        errMultiplier = 1 - ((minThreshold - error) / minThreshold) * 0.5;
      }
      stdDev = stdDev * errMultiplier;

      // Offset the ratings up or down around the center, based on the shooter's
      // trend. (If you're on an upward run, you get some upward shaping.)
      // var trends = [rating.shortDirection, rating.direction, rating.longDirection];
      var trendAverage = rating.shortTrend * 0.45 + rating.mediumTrend * 0.35 + rating.longTrend * 0.20;

      var trendShiftMaxVal = scale / 2;
      var trendShiftMaxMagnitude = 0.9;
      if(rating.length < 100) {
        trendShiftMaxMagnitude = 0.9 * rating.length / 100;
      }
      var trendShiftProportion = max(-1.0, min(1.0, trendAverage / trendShiftMaxVal));
      var trendShift = trendShiftProportion * trendShiftMaxMagnitude;

      // Starting with the shooter's calculated rating, generate a bunch of potential ratings that could be the
      // actual, accurate representation of the shooter's skill, and average the win probability of all of those
      // potential ratings against the rest of the field.

      // List<double> possibleRatings = Gumbel.generate(monteCarloTrials, mu: rating.rating, beta: stdDev, rng: r);
      List<double> possibleRatings = r.generateGaussianWithParams(monteCarloTrials, mu: rating.rating, sigma: stdDev);
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
      highPrediction = max(highPrediction, averagePerformance);
      var variance = expectedScores.map((e) => pow(e - averagePerformance, 2)).average;
      var performanceDeviation = sqrt(variance);

      double meanRatio = averagePerformance;
      double oneSigmaRatio = performanceDeviation;

      predictions.add(AlgorithmPrediction(
        settings: settings,
        algorithm: this,
        shooter: rating,
        displayCenter: averagePerformance,
        ciOffset: trendShift,
        sigma: performanceDeviation,
        expectedRatio: meanRatio,
        oneSigmaRatio: oneSigmaRatio,
        shiftRatio: trendShift,
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

      prediction.expectedRatio = ratioFloor + (prediction.displayCenter / highPrediction * ratioMultiplier);
      prediction.oneSigmaRatio = prediction.oneSigma / highPrediction * ratioMultiplier;
      prediction.shiftRatio = prediction.shift / highPrediction * ratioMultiplier;
    }

    return predictions;
  }

  @override
  bool get supportsRatioFloor => true;

  @override
  double estimateRatioFloor(double ratingDelta, {RaterSettings? settings}) {
    var eloSettings = (settings as EloSettings?) ?? this.settings;
    var scalingFactor = -58 * log(eloSettings.probabilityBase) / (4.0 * eloSettings.scale);
    var outputRatio = ((100 + scalingFactor * ratingDelta) / 100).clamp(0.01, 1.0);
    return outputRatio;
  }

  @override
  PredictionOutcome validate({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required List<AlgorithmPrediction> predictions,
    bool chatty = true,
  }) {
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions = {};
    Map<AlgorithmPrediction, SimpleMatchResult> actualOutcomes = {};
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
        _log.w("Null prediction for $shooter");
        continue;
      }

      var score = scores[shooter]!;
      var matchScore = matchScores[shooter]!;
      var params = _calculateScoreParams(aRating: shooter, aScore: score, aMatchScore: matchScore, scores: scores, matchScores: matchScores);
      var eloScore = _calculateActualScore(score: score, matchScore: matchScore, params: params, isDnf: matchScore.isDnf);

      errors.add(eloScore.score - prediction.displayCenter);
      errorSum += pow(eloScore.score - prediction.displayCenter, 2);
      actualOutcomes[prediction] = SimpleMatchResult(raterScore: eloScore.score, percent: matchScore.ratio, place: matchScore.place);

      if(eloScore.score >= prediction.displayCenter - prediction.twoSigma + prediction.shift && eloScore.score <= prediction.displayCenter + prediction.twoSigma + prediction.shift) {
        correct95 += 1;
      }
      if(eloScore.score >= prediction.displayCenter - prediction.oneSigma + prediction.shift && eloScore.score <= prediction.displayCenter + prediction.oneSigma + prediction.shift) {
        correct68 += 1;
      }
      if(matchScore.place <= prediction.lowPlace && matchScore.place >= prediction.highPlace) {
        correctPlace += 1;
      }
    }

    if(chatty) {
      _log.d("Actual outcomes for ${actualOutcomes.length} shooters yielded an error sum of ${errors.sum} and an average error of ${errors.average.toStringAsPrecision(3)}");
      _log.d("Std. dev: ${(sqrt(errorSum) / predictions.length).toStringAsPrecision(3)} of ${predictions.map((e) => e.displayCenter).average}");
      _log.d("Score correct: $correct68/$correct95/${actualOutcomes.length} (${(correct68 / actualOutcomes.length).asPercentage(decimals: 1)}%/${(correct95 / actualOutcomes.length * 100).toStringAsFixed(1)}%)");
      _log.d("Place correct: $correctPlace/${actualOutcomes.length} (${(correctPlace / actualOutcomes.length).asPercentage(decimals: 1)}%)");
    }

    return PredictionOutcome(
      error: (sqrt(errorSum) / predictions.length), actualResults: actualOutcomes, mutatedInputs: repredicted,
    );
  }
}

class _ScoreParameters {
  double expectedScore;
  double highOpponentRatio;
  double totalPercent;
  double divisor;
  int usedScores;
  int zeroes;

  _ScoreParameters({
    required this.expectedScore,
    required this.highOpponentRatio,
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
