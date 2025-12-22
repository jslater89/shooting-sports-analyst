/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:advance_math/advance_math.dart';
import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_score_functions.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("Glicko2Rater");

/// A rating system that uses a lightly modified version of the Glicko-2 algorithm.
///
/// Shooting Sports Analyst is built for continuous ratings that update on events
/// rather than over time, and standard Glicko-2 has the 'rating period' concept
/// that breaks that model. This implementation goes continuous by calculating
/// a continuous RD/rating deviation property that is updated based on the elapsed
/// time since a competitor's last event.
///
/// It operates in 'by match' mode, treating each match as a 'rating period' after
/// which we commit new ratings, RDs, and volatilities.
///
/// Numbers displayed to users are always scaled to display units, but all internal
/// calculations are done in internal units. (See [Glicko2Settings.scaleToInternal]
/// and [Glicko2Settings.scaleToDisplay].)
class Glicko2Rater extends RatingSystem<Glicko2Rating, Glicko2Settings> {

  // Keys for rating change data
  static const oldRDKey = "oldRD";
  static const rdChangeKey = "rdChange";
  static const oldVolatilityKey = "oldVolatility";
  static const volatilityChangeKey = "volatilityChange";
  static const stagesKey = "stages";

  Glicko2Rater({required this.settings});

  final Glicko2Settings settings;

  @override
  bool get byStage => settings.byStage;

  @override
  ShooterRating<RatingEvent> copyShooterRating(Glicko2Rating rating) {
    return Glicko2Rating.copy(rating);
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[DbRatingProject.algorithmKey] = DbRatingProject.glicko2Value;
    settings.encodeToJson(json);
  }

  static Glicko2Rater fromJson(Map<String, dynamic> json) {
    var settings = Glicko2Settings();
    settings.loadFromJson(json);
    return Glicko2Rater(settings: settings);
  }

  @override
  RatingMode get mode => RatingMode.oneShot;

  @override
  RatingEvent newEvent({required ShootingMatch match, MatchStage? stage, required ShooterRating<RatingEvent> rating, required RelativeScore score, required RelativeMatchScore matchScore, List<String> infoLines = const [], List<RatingEventInfoElement> infoData = const []}) {
    rating as Glicko2Rating;
    return Glicko2RatingEvent(
      settings: settings,
      ratingChange: 0.0,
      internalRatingChange: 0.0,
      oldRating: rating.rating,
      oldInternalRating: rating.internalRating,
      oldVolatility: rating.volatility,
      volatilityChange: 0.0,
      oldRD: rating.committedInternalRD,
      rdChange: 0.0,
      match: match,
      stage: stage,
      score: score,
      matchScore: matchScore,
      infoLines: infoLines,
      infoData: infoData,
    );
  }

  @override
  ShooterRating<RatingEvent> newShooterRating(MatchEntry shooter, {required Sport sport, required DateTime date}) {
    var ratingMultiplier = sport.initialGenericRatingMultipliers[shooter.classification] ?? 1.0;
    var initialRating = settings.initialRating * ratingMultiplier;
    // var initialRating = settings.initialRating;
    return Glicko2Rating(
      shooter, settings: settings, sport: sport, date: date,
      initialRating: initialRating,
      initialVolatility: settings.initialVolatility,
      initialRD: settings.startingRD,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating<RatingEvent>> ratings) {
    StringBuffer csv = StringBuffer();
    csv.writeln("Member#,Name,Rating,RD,Volatility,Matches,Stages");
    for(var r in ratings) {
      r as Glicko2Rating;
      csv.writeln("${r.memberNumber},${r.name},${r.rating},${r.currentInternalRD},${r.volatility},${r.lengthInMatches},${r.lengthInStages}");
    }
    return csv.toString();
  }

  @override
  List<JsonShooterRating> ratingsToJson(List<ShooterRating<RatingEvent>> ratings) {
    return ratings.map((e) => JsonShooterRating.fromShooterRating(e)).toList();
  }

  @override
  Glicko2Rating wrapDbRating(DbShooterRating rating) {
    return Glicko2Rating.wrapDbRatingWithSettings(this, rating);
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

    // TODO: by-stage Glicko-2?
    // Glicko-2 has more or less proven itself to be pretty much as good as carefully tuned Elo,
    // which means that with some careful tuning, it's plausibly the better rating system. That said,
    // by stage mode is useful; per-stage volatility is a useful thing to be able to see in the graph.
    //
    // By-stage mode kiiind of works, but volatility hits the roof almost immediately (as we'd expect;
    // shooting sports are pretty volatile from stage to stage). We solved that in Elo with the weaker
    // base/scale parameters, but I don't understand the Glicko math well enough to do the same thing.

    // we're in oneshot mode, so we should have 1 shooter and scores
    // for the full match.

    if(scores.length == 1) {
      // No changes for a match with only one competitor
      return {};
    }

    var shooter = shooters.first as Glicko2Rating;
    var shooterScore = scores[shooter];
    var shooterMatchScore = matchScores[shooter];
    if(shooterScore == null || shooterMatchScore == null) {
      throw Exception("Shooter score or match score is null");
    }

    // TODO: providing a relative score rather than a relative match score here might improve by stage mode
    // (compare stage score against close opponents on the stage rather than close opponents overall)
    var opponents = matchScores.keys.where((key) => key != shooter).toList();
    opponents = _selectOpponents(shooter, matchScores, shooterScore.ratio);

    /// For each competitor, we only update ratings for the stages that they completed.
    var shooterStageScores = shooterMatchScore.stageScores.entries
      .where((entry) => entry.key.scoring.countsInRatings && !entry.value.isDnf)
      .map((entry) => entry.value)
      .toList();

    // Step 1: V and delta

    // Calculate sum-of-V
    var vSum = 0.0;
    var deltaSum = 0.0;

    // Because Glicko-2 has a
    for(var opponent in opponents) {
      opponent as Glicko2Rating;
      var opponentRDAtMatch = opponent.calculateCurrentInternalRD(asOfDate: match.date);
      var opponentScore = scores[opponent];
      if(opponentScore == null) {
        continue;
      }

        var vForOpponent = _glickoVForOpponent(shooter.internalRating, opponent.internalRating, opponentRDAtMatch);
        vSum += vForOpponent;

        var shooterStageScoreRatio = shooterScore.ratio;
        var opponentStageScoreRatio = opponentScore.ratio;
        var scoreForOpponent = _calculateScoreForOpponent(shooterStageScoreRatio, opponentStageScoreRatio);

        var deltaForOpponent = _glickoDeltaForOpponent(scoreForOpponent, shooter.internalRating, opponent.internalRating, opponentRDAtMatch);
        deltaSum += deltaForOpponent;

      // by stage below
      // for(var shooterStageScore in shooterStageScores) {
      //   // We don't actually need the scores at this point, but we do do need to check that
      //   // they exist.
      //   var opponentStageScore = opponentMatchScore.stageScores[shooterStageScore.stage];
      //   if(opponentStageScore == null) {
      //     continue;
      //   }
      //   // reuse earlier V calculation
      //   vSum += vForOpponent;

      //   var shooterStageScoreRatio = shooterStageScore.ratio;
      //   var opponentStageScoreRatio = opponentStageScore.ratio;
      //   var scoreForOpponent = _calculateScoreForOpponent(shooterStageScoreRatio, opponentStageScoreRatio);

      //   var deltaForOpponent = _glickoDeltaForOpponent(scoreForOpponent, shooter.rating, opponent.rating, opponentRDAtMatch);
      //   deltaSum += deltaForOpponent;

      // }
    }

    var v = 1 / vSum;
    var delta = deltaSum * v;

    // Step 2: volatility update
    var newVolatility = _iterateVolatility(
      volatility: shooter.volatility,
      rd: shooter.committedInternalRD,
      delta: delta,
      v: v,
    );

    // Cap at 0.15; volatility higher than that yields instability.
    if(newVolatility > Glicko2Settings.defaultMaximumVolatility) {
      newVolatility = Glicko2Settings.defaultMaximumVolatility;
    }

    // var newVolatility = shooter.volatility;

    // Step 3: calculate changes to RD and volatility
    var rdStar = shooter.calculateCurrentInternalRD(
      volatilityOverride: newVolatility,
      asOfDate: match.date,
    );
    var rdPrime = 1 / sqrt((1 / pow(rdStar, 2)) + (1 / v));
    if(rdPrime > settings.internalMaximumRD) {
      rdPrime = settings.internalMaximumRD;
    }
    var ratingChange = pow(rdPrime, 2) * deltaSum;
    var maximumRatingChange = settings.internalMaximumRatingDelta;
    if(ratingChange.abs() > maximumRatingChange) {
      ratingChange = ratingChange.sign * maximumRatingChange;
    }

    var rdChange = rdPrime - shooter.committedInternalRD;
    var volatilityChange = newVolatility - shooter.volatility;

    return {
      shooter: RatingChange(
        change: {
          RatingSystem.ratingKey: ratingChange,
          Glicko2Rater.oldRDKey: shooter.committedInternalRD,
          Glicko2Rater.rdChangeKey: rdChange,
          Glicko2Rater.oldVolatilityKey: shooter.volatility,
          Glicko2Rater.volatilityChangeKey: volatilityChange,
          if(!byStage) Glicko2Rater.stagesKey: shooterStageScores.length.toDouble(),
          if(byStage) Glicko2Rater.stagesKey: 1,
        },
        infoLines: [
          "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
          "Rating ± Change: {{rating}}/{{change}}",
          "RD ± Change: {{rd}}/{{rdChange}}",
          "Volatility ± Change: {{volatility}}/{{volatilityChange}}",
          "Considered {{opponents}} opponents",
        ],
        infoData: [
          RatingEventInfoElement.int(name: "finish", intValue: shooterScore.place),
          RatingEventInfoElement.int(name: "competitors", intValue: matchScores.length),
          RatingEventInfoElement.double(name: "finishPercent", doubleValue: shooterScore.percentage, numberFormat: "%00.2f"),
          RatingEventInfoElement.double(name: "rating", doubleValue: shooter.rating, numberFormat: "%00.0f"),
          RatingEventInfoElement.double(name: "change", doubleValue: ratingChange * settings.scalingFactor, numberFormat: "%00.2f"),
          RatingEventInfoElement.double(name: "rd", doubleValue: rdPrime * settings.scalingFactor, numberFormat: "%00.0f"),
          RatingEventInfoElement.double(name: "rdChange", doubleValue: rdChange * settings.scalingFactor, numberFormat: "%00.2f"),
          RatingEventInfoElement.double(name: "volatility", doubleValue: newVolatility, numberFormat: "%00.4f"),
          RatingEventInfoElement.double(name: "volatilityChange", doubleValue: volatilityChange, numberFormat: "%00.4f"),
          RatingEventInfoElement.int(name: "opponents", intValue: opponents.length),
        ]
      ),
    };
  }

  @override
  bool get supportsPrediction => settings.scoreFunctionType == ScoreFunctionType.linearMarginOfVictory;

  @override
  PredictionSettings get predictionSettings => PredictionSettings(
    outputsAreRatios: true,
  );

  @override
  bool get predictionsOutputRatios => true;

  @override
  List<AlgorithmPrediction> predict(List<ShooterRating> ratings, {int? seed}) {
    /*
    The below was the initial design approach; it's retained for reference in case I forgot
    something.

    Thoughts:
    The head-to-head margin of victory algorithm actually probably can be used to predict.

    How? Leverage head-to-head scores. Exactly one person will be predicted to win. (He'll have
    a >0.5 score against all comers.)

    From that person, we can build up a ladder of initial predictions: people within 25% of the
    leader will have score greater than 0, and we can de-lerp the expected score to get that number
    (100 - delerp(expected_score)). Then, for people further than 25% away from the leader, we can
    use non-leaders for whom we have performances against the leader.

    xPb = xPa - (pctLoss(rB, rA) * (xPa / 100)) # scaling down as a 25% loss to 75% is only an 18.75% loss

    Once we have an initial estimate for everyone based off of one opponent, then we can go through the list
    and calculate estimates from everyone. I think it's probably a three-pass thing in total?

    1. Moving from the top of the list to the bottom of the list, calculate a possible percentage using only
    the competitors ahead of the player in the result. (Actually probably best to do this as the first step.)
    Use weighted averages (by opponent RD) to calculate the expected percentage.
    1.a. Opponent RD because player RD sort of averages out—if high RD pushes predictions closer to a tie,
    high player RD means "this player is close to a tie" with almost everyone, which is not useful as a prediction.
    2. Moving from the bottom of the list to the top of the list, calculate a possible percentage using both
    the competitors ahead of the player and the competitors behind the player. (This adds information from the
    lower end of the spectrum; "X is expected to beat Y by Z%").
    3. Moving from the top of the list to the bottom again, calculate predicted percentages using both competitors
    ahead of and behind the player. (This bubbles information from step 2 back down through the list.)
    */

    // Step 0: calculate initial expected scores for each competitor against all other competitors,
    // and sort by number of expected scores above 0.5, then average expected scores. This should
    // give us a good initial ordering.
    Map<ShooterRating, List<double>> initialExpectedScores = {};
    Map<ShooterRating, int> expectedScoresAboveDrawCount = {};
    Map<ShooterRating, double> averageExpectedScores = {};
    for(var aRating in ratings) {
      aRating as Glicko2Rating;
      for(var bRating in ratings) {
        if(aRating == bRating) {
          continue;
        }
        bRating as Glicko2Rating;
        // TODO: current RD for match date?
        var expectedScore = _glickoE(aRating.internalRating, bRating.internalRating, bRating.currentInternalRD);
        initialExpectedScores.addToList(aRating, expectedScore);
        if(expectedScore > 0.5) {
          expectedScoresAboveDrawCount.increment(aRating);
        }
      }
    }

    for(var rating in ratings) {
      var expectedScores = initialExpectedScores[rating];
      if(expectedScores == null) {
        continue;
      }
      var averageExpectedScore = expectedScores.average;
      averageExpectedScores[rating] = averageExpectedScore;
    }

    List<ShooterRating> sortedRatings = ratings.sorted((a, b) {
      if(a == b) {
        return 0;
      }
      var aScoresAboveDraw = expectedScoresAboveDrawCount[a] ?? 0;
      var bScoresAboveDraw = expectedScoresAboveDrawCount[b] ?? 0;
      if(aScoresAboveDraw != bScoresAboveDraw) {
        return bScoresAboveDraw.compareTo(aScoresAboveDraw);
      }
      var aAverageExpectedScore = averageExpectedScores[a] ?? 0.0;
      var bAverageExpectedScore = averageExpectedScores[b] ?? 0.0;
      return bAverageExpectedScore.compareTo(aAverageExpectedScore);
    }).toList();

    // At this point we have a sorted list in prediction order.

    // Step 1: calculate initial expected percentages for each competitor, by
    // running the score function in reverse for each pair of competitors and
    // averaging the results.

    Map<ShooterRating, _ExpectedPercentage> expectedPercentages = _calculateExpectedPercentages(sortedRatings, initial: true, descending: true);

    // Step 2: percolate from bottom to top.
    expectedPercentages = _calculateExpectedPercentages(sortedRatings.reversed.toList(), descending: false, priorExpectedPercentages: expectedPercentages);

    // Step 3: percolate from top to bottom.
    expectedPercentages = _calculateExpectedPercentages(sortedRatings, descending: true, priorExpectedPercentages: expectedPercentages);

    // Step 4: normalize
    var highestPercentage = expectedPercentages.values.map((e) => e.centralValue).max;
    var factor = 1.0 / highestPercentage;

    if((factor - 1.0).abs() > 0.05) {
      _log.w("Percentage output instability detected, factor: $factor");
    }
    else {
      _log.i("Percentage output stability within tolerance, factor: $factor");
    }

    for(var entry in expectedPercentages.entries) {
      expectedPercentages[entry.key] = _ExpectedPercentage(
        rating: entry.value.rating,
        rd: entry.value.rd,
        centralValue: entry.value.centralValue * factor,
        upperValue: entry.value.upperValue * factor,
        lowerValue: entry.value.lowerValue * factor,
      );
    }

    // Step 5: calculate expected places.
    Map<ShooterRating, int> expectedPlaces = {};
    Map<ShooterRating, int> expectedLowPlaces = {};
    Map<ShooterRating, int> expectedHighPlaces = {};
    sortedRatings.sort((a, b) => expectedPercentages[b]!.centralValue.compareTo(expectedPercentages[a]!.centralValue));
    for(var (i, rating) in sortedRatings.indexed) {
      expectedPlaces[rating] = i + 1;
    }

    for(var entry in sortedRatings) {
      var expectedPercentage = expectedPercentages[entry]!;
      int bestPlace = 1;
      int worstPlace = 1;
      for(var (i, other) in sortedRatings.indexed) {
        if(other == entry) {
          continue;
        }
        var otherExpectedPercentage = expectedPercentages[other]!;
        if(otherExpectedPercentage.centralValue > expectedPercentage.upperValue) {
          bestPlace = i + 1;
        }
        if(otherExpectedPercentage.centralValue > expectedPercentage.lowerValue) {
          worstPlace = i + 1;
        }
      }
      expectedHighPlaces[entry] = bestPlace;
      expectedLowPlaces[entry] = worstPlace;
    }


    return expectedPercentages.entries.map((entry) {
      // In Glicko-2, RD is the standard deviation of the rating. The upperValue and
      // lowerValue are calculated by adjusting the rating by ±RD (i.e., ±1σ in rating space).
      // The range (upperValue - lowerValue) represents approximately 2σ in rating space,
      // which maps to percentage space through a non-linear transformation.
      //
      // As a first-order approximation, we divide the range by 2 to get 1σ in percentage space.
      // This is principled because:
      // 1. RD represents 1σ uncertainty in rating space
      // 2. Adjusting by ±RD gives us the range from -1σ to +1σ (total span of 2σ)
      // 3. The transformation to percentage space, while non-linear, is relatively smooth
      //    in the linear region of the E function where we operate
      // 4. The range already incorporates the shooter's RD and is affected by opponents' RDs
      //    through the E function calculations, so it captures the relevant uncertainty
      var range = (entry.value.upperValue - entry.value.lowerValue).abs();
      var sigma = range / 2.0;

      return AlgorithmPrediction(
        shooter: entry.key,
        mean: entry.value.centralValue,
        sigma: sigma,
        settings: settings,
        algorithm: this,
        lowPlace: expectedLowPlaces[entry.key]!,
        highPlace: expectedHighPlaces[entry.key]!,
        medianPlace: expectedPlaces[entry.key]!,
      );
    }).toList();
  }

  // -- internal methods below --

  /// Get opponents based on the selection mode. Input must be sorted by match finish.
  List<ShooterRating> _selectOpponents(Glicko2Rating player, Map<ShooterRating, RelativeMatchScore> matchScores, double playerRatio) {
    var opponentsByFinish = matchScores.keys.toList();
    var opponentsByRating = opponentsByFinish.sorted((a, b) => b.rating.compareTo(a.rating)).toList();
    var selectionMode = settings.opponentSelectionMode;
    List<ShooterRating> selected = [];
    if(selectionMode == OpponentSelectionMode.all) {
      selected = opponentsByFinish;
    }
    else if(selectionMode == OpponentSelectionMode.top10Pct) {
      selected = _selectTop10PctOpponents(opponentsByFinish, opponentsByRating);
    }
    else if(selectionMode == OpponentSelectionMode.nearby) {
      selected = _selectNearbyOpponents(player, matchScores, opponentsByRating, playerRatio);
    }
    else if(selectionMode == OpponentSelectionMode.topAndNearby) {
      var topOpponents = _selectTop10PctOpponents(opponentsByFinish, opponentsByRating).toSet();
      topOpponents.addAll(_selectNearbyOpponents(player, matchScores, opponentsByRating, playerRatio));
      selected = topOpponents.toList();
    }
    else {
      throw Exception("Invalid opponent selection mode: $selectionMode");
    }

    // For new players, limit the number of opponents to avoid massive stacking rating
    // deltas, taking players closest in match finish first.
    final bool byMatchScore = settings.limitOpponentsMode == LimitOpponentsMode.finish;
    if((player.length == 0 && selected.length > settings.maximumOpponentCountForNew) ||
      (settings.maximumOpponentCountForExisting != null && player.length > 0 && selected.length > settings.maximumOpponentCountForExisting!)) {

      var limit = player.length == 0 ? settings.maximumOpponentCountForNew : settings.maximumOpponentCountForExisting!;
      selected = selected.sorted((a, b) {
        if(byMatchScore) {
          var aRatio = matchScores[a]?.ratio ?? 0.0;
          var bRatio = matchScores[b]?.ratio ?? 0.0;
          return aRatio.compareTo(bRatio);
        }
        else {
          var aDiff = (a.rating - player.rating).abs();
          var bDiff = (b.rating - player.rating).abs();
          return aDiff.compareTo(bDiff);
        }
      }).take(limit).toList();
    }

    // If that doesn't include the winner, include the winner and remove the most distant opponent.
    var winner = matchScores.keys.first;
    if(!selected.contains(winner) && player != winner) {
      selected.insert(0, winner);
      selected.removeLast();
    }

    return selected;
  }

  /// Get the top 10% of opponents by rating and match finish. Input must be sorted by match finish.
  List<ShooterRating> _selectTop10PctOpponents(List<ShooterRating> opponentsByFinish, List<ShooterRating> opponentsByRating) {
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

  List<ShooterRating> _selectNearbyOpponents(Glicko2Rating player, Map<ShooterRating, RelativeMatchScore> matchScores, List<ShooterRating> opponentsByRating, double competitorRatio) {
    double margin = 0.1;
    if(opponentsByRating.length < 10) {
      margin = 0.25;
    }

    Set<ShooterRating> nearbyOpponents = {};
    final topRatio = competitorRatio * (1 + margin);
    final bottomRatio = competitorRatio * (1 - margin);
    for(var opponent in matchScores.keys) {
      // Players with no rating history don't have a valid rating yet, so 'nearby' in rating terms
      // isn't meaningful yet.
      if((opponent.rating - player.rating).abs() <= settings.maximumRD) {
        nearbyOpponents.add(opponent);
        continue;
      }

      var opponentMatchScore = matchScores[opponent];
      if(opponentMatchScore == null) {
        continue;
      }
      var opponentRatio = opponentMatchScore.ratio;
      if(opponentRatio >= bottomRatio && opponentRatio <= topRatio) {
        nearbyOpponents.add(opponent);
      }
    }

    return nearbyOpponents.toList();
  }

  double _iterateVolatility({
    required double volatility,
    required double rd,
    required double delta,
    required double v,
    double epsilon = 0.000001,
  }) {
    var deltaSquared = pow(delta, 2).toDouble();
    var rdSquared = pow(rd, 2).toDouble();
    var alpha = log(pow(volatility, 2));
    var tau = settings.tau;

    var A = alpha;

    // Set B with iteration if needed
    double B;
    if(deltaSquared > (rdSquared + v)) {
      B = log(deltaSquared - rdSquared - v);
    }
    else {
      var k = 0;
      double fOut = -1;
      while(fOut <= 0) {
        k++;
        fOut = _iterativeVolatilityFunction(
          x: alpha - k * tau,
          deltaSquared: deltaSquared,
          rdSquared: rdSquared,
          v: v,
          alpha: alpha,
          tau: tau
        );
      }
      B = alpha - k * tau;
    }

    var fA = _iterativeVolatilityFunction(
      x: A,
      deltaSquared: deltaSquared,
      rdSquared: rdSquared,
      v: v,
      alpha: alpha,
      tau: tau
    );
    var fB = _iterativeVolatilityFunction(
      x: B,
      deltaSquared: deltaSquared,
      rdSquared: rdSquared,
      v: v,
      alpha: alpha,
      tau: tau
    );
    while((B - A).abs() > epsilon) {
      var cNumerator = (A - B) * fA;
      var cDenominator = fB - fA;
      var C = A + (cNumerator / cDenominator);
      var fC = _iterativeVolatilityFunction(
        x: C,
        deltaSquared: deltaSquared,
        rdSquared: rdSquared,
        v: v,
        alpha: alpha,
        tau: tau
      );

      if(fC * fB <= 0) {
        A = B;
        fA = fB;
      }
      else {
        fA = fA / 2;
      }

      B = C;
      fB = fC;
    }

    return exp(A / 2);
  }

  double _iterativeVolatilityFunction({
    required double x,
    required double deltaSquared,
    required double rdSquared,
    required double v,
    required double alpha,
    required double tau,
  }) {
    var firstTermNumerator = exp(x) * (deltaSquared - rdSquared - v - exp(x));
    var firstTermDenominator = 2 * pow(rdSquared + v + exp(x), 2);

    var secondTerm = (x - alpha) / pow(tau, 2);

    return (firstTermNumerator / firstTermDenominator) - secondTerm;
  }

  double _glickoDeltaForOpponent(double score, double rating, double opponentRating, double opponentRD) {
    var g = _glickoG(opponentRD);
    var e = _glickoE(rating, opponentRating, opponentRD);
    return g * (score - e);
  }

  /// Calculate a Glicko-compatible score against an opponent.
  double _calculateScoreForOpponent(double shooterRatio, double opponentRatio) {
    return settings.scoreFunction.calculateScore(shooterRatio, opponentRatio);
  }

  double _glickoVForOpponent(double rating, double opponentRating, double opponentRD) {
    var gSquared = pow(_glickoG(opponentRD), 2);
    var e = _glickoE(rating, opponentRating, opponentRD);
    return gSquared * e * (1 - e);
  }

  double _glickoE(double rating, double opponentRating, double opponentRD) {
    var rDiff = rating - opponentRating;
    var negativeG = -_glickoG(opponentRD);
    var expTerm = exp(negativeG * rDiff);
    return 1 / (1 + expTerm);
  }

  double _glickoG(double rd) {
    var denomTerm = 3 * pow(rd,2) / pow(pi, 2);
    return 1 / sqrt(1 + denomTerm);
  }

  /// Calculate expected percentages for each competitor in the list.
  ///
  /// [ratings] must be sorted, either ascending or descending. The [descending] parameter
  /// indicates the sort order.
  ///
  /// If [initial] is true, the algorithm makes two small tweaks:
  ///
  /// 1. The first rating is assigned 1.0, and other ratings' finishes are calculated against
  /// only better finishes.
  /// 2. It assumes that the list is sorted descending.
  Map<ShooterRating, _ExpectedPercentage> _calculateExpectedPercentages(List<ShooterRating> ratings, {
    Map<ShooterRating, _ExpectedPercentage>? priorExpectedPercentages,
    bool descending = true,
    bool initial = false,
    // TODO: date param for RD
  }) {
    // Magic number. Since expected scores are probabilistic (i.e., someone very likely to
    // lose might still have an expected score of 0.1), we want to slightly inflate the victory
    // margins we generate in this calculation to fudge the results toward what we expect to
    // happen. If we don't, repeated applications of this function end up compressing the outputs—
    // in the 0.1 case above, we get (1 - 0.9^3) for the way this is currently being used.
    final victoryMarginInflation = settings.marginOfVictoryInflation;

    var scoreFunction = settings.scoreFunction as LinearMarginOfVictoryScoreFunction;
    if(priorExpectedPercentages == null) {
      priorExpectedPercentages = {};
    }
    Map<ShooterRating, _ExpectedPercentage> outputExpectedPercentages = {};
    if(initial) {
      var firstRating = ratings[0] as Glicko2Rating;
      priorExpectedPercentages[firstRating] = _ExpectedPercentage(
        rating: firstRating.internalRating,
        rd: firstRating.currentInternalRD,
        centralValue: 1.0,
        upperValue: 1.0,
        lowerValue: 1.0,
      );
    }

    if(initial && !descending) {
      throw Exception("Initial expected percentages cannot be calculated for an ascending list");
    }

    Map<ShooterRating, List<_ExpectedPercentage>> expectedPercentages = {};
    Map<ShooterRating, List<double>> weights = {};

    for(var (i, rating) in ratings.indexed) {
      rating as Glicko2Rating;
      if(initial && i == 0) {
        outputExpectedPercentages[rating] = _ExpectedPercentage(
          rating: rating.internalRating,
          rd: rating.currentInternalRD,
          centralValue: 1.0,
          upperValue: 1.0,
          lowerValue: 1.0,
        );
        continue;
      }
      else {
        var betterRatings = descending ? ratings.sublist(0, i) : ratings.sublist(i + 1);
        var worseRatings = descending ? ratings.sublist(i + 1) : ratings.sublist(0, i);
        for(var betterRating in betterRatings) {
          betterRating as Glicko2Rating;
          var opponentExpectedPercentage = priorExpectedPercentages[betterRating];
          if(opponentExpectedPercentage == null) {
            _log.e("Missing expected percentage in prediction calculation for $rating vs $betterRating (better ratings, descending: $descending, initial: $initial)");
            continue;
          }
          var expectedPercentage = _calculateHeadToHeadExpectedPercentage(
            playerRating: rating.internalRating,
            playerRD: rating.currentInternalRD,
            playerVolatility: rating.volatility,
            opponentRating: betterRating.internalRating,
            opponentRD: betterRating.currentInternalRD,
            opponentRatio: opponentExpectedPercentage.centralValue,
            playerRatio: null, // not needed for this scenario
            scoreFunction: scoreFunction,
            victoryMarginInflation: victoryMarginInflation,
            playerIsBetter: false,
          );
          if(expectedPercentage == null) {
            continue;
          }
          if(initial) {
            // For the first run through, set the prior expected percentage to the new estimate immediately.
            priorExpectedPercentages[rating] = expectedPercentage;
          }
          expectedPercentages.addToList(rating, expectedPercentage);
          weights.addToList(rating, _glickoG(betterRating.currentInternalRD));
        }

        if(!initial) {
          for(var worseRating in worseRatings) {
            // For worse ratings, we want to calculate the margin from the player to the worse rating,
            // so we want the opponent's expected score rather than the player's.
            worseRating as Glicko2Rating;
            var playerExpectedPercentage = priorExpectedPercentages[rating];
            var opponentExpectedPercentage = priorExpectedPercentages[worseRating];
            if(playerExpectedPercentage == null || opponentExpectedPercentage == null) {
              _log.e("Missing expected percentage (p: $playerExpectedPercentage, o: $opponentExpectedPercentage) in prediction calculation for $rating vs $worseRating (worse ratings, descending: $descending, initial: $initial)");
              continue;
            }
            var expectedPercentage = _calculateHeadToHeadExpectedPercentage(
              playerRating: rating.internalRating,
              playerRD: rating.currentInternalRD,
              playerVolatility: rating.volatility,
              opponentRating: worseRating.internalRating,
              opponentRD: worseRating.currentInternalRD,
              opponentRatio: opponentExpectedPercentage.centralValue,
              playerRatio: playerExpectedPercentage.centralValue,
              scoreFunction: scoreFunction,
              victoryMarginInflation: victoryMarginInflation,
              playerIsBetter: true,
            );

            if(expectedPercentage == null) {
              continue;
            }
            expectedPercentages.addToList(rating, expectedPercentage);
            weights.addToList(rating, _glickoG(worseRating.currentInternalRD));
          }
        }
      }
    }

    for(var rating in ratings) {
      rating as Glicko2Rating;
      var ratingExpectedPercentages = expectedPercentages[rating];
      if(ratingExpectedPercentages == null) {
        continue;
      }
      var ratingWeights = weights[rating];
      if(ratingWeights == null) {
        continue;
      }
      var centerExpectedPercentage = ratingExpectedPercentages.map((e) => e.centralValue).weightedAverage(ratingWeights);
      var upperExpectedPercentage = ratingExpectedPercentages.map((e) => e.upperValue).weightedAverage(ratingWeights);
      var lowerExpectedPercentage = ratingExpectedPercentages.map((e) => e.lowerValue).weightedAverage(ratingWeights);
      outputExpectedPercentages[rating] = _ExpectedPercentage(
        rating: rating.internalRating,
        rd: rating.currentInternalRD,
        centralValue: centerExpectedPercentage,
        upperValue: upperExpectedPercentage,
        lowerValue: lowerExpectedPercentage,
      );
    }

    return outputExpectedPercentages;
  }

  /// Calculate the expected percentage for a given rating and RD.
  ///
  /// [playerRating] is the rating of the competitor to calculate the expected percentage for.
  /// [playerRD] is the RD of the competitor to calculate the expected percentage for.
  /// [playerVolatility] is the volatility of the competitor to calculate the expected percentage for.
  /// [opponentRating] is the rating of the opponent.
  /// [opponentRD] is the RD of the opponent.
  /// [winnerRatio] is 0-1 match outcome of the winner against the field (not just the opponent).
  /// [playerIsBetter] is true if the player is the winner, false if the player is the loser.
  /// [scoreFunction] is the score function to use to calculate the expected percentage.
  /// [victoryMarginInflation] is the inflation factor to apply to the victory margin.
  ///
  /// Returns the expected percentage as a _ExpectedPercentage object, or null if the
  /// center value of the expected percentage is outside the linear region of the E function.
  _ExpectedPercentage? _calculateHeadToHeadExpectedPercentage({
    required double playerRating,
    required double playerRD,
    required double playerVolatility,
    double? playerRatio,
    required double opponentRating,
    required double opponentRD,
    required double opponentRatio,
    required LinearMarginOfVictoryScoreFunction scoreFunction,
    required double victoryMarginInflation,
    required bool playerIsBetter,
  }) {
    var volatilityFactor = lerpAroundCenter(
      value: playerVolatility,
      center: settings.initialVolatility,
      rangeMin: settings.initialVolatility * 0.75,
      rangeMax: settings.initialVolatility * 1.25,
      minOut: 0.5,
      centerOut: 1.0,
      maxOut: 2.0,
    );
    double adjustedRD = playerRD * volatilityFactor;

    double expectedScore, downRdExpectedScore, upRdExpectedScore;
    if(!playerIsBetter) {
      expectedScore = _glickoE(playerRating, opponentRating, opponentRD);
      downRdExpectedScore = _glickoE(playerRating - adjustedRD, opponentRating, opponentRD);
      upRdExpectedScore = _glickoE(playerRating + adjustedRD, opponentRating, opponentRD);
    }
    else {
      expectedScore = _glickoE(opponentRating, playerRating, playerRD);
      downRdExpectedScore = _glickoE(opponentRating, playerRating - adjustedRD, playerRD);
      upRdExpectedScore = _glickoE(opponentRating, playerRating + adjustedRD, playerRD);
    }

    // The linear region of the E function outputs approximately 0.2 to 0.8.
    if(expectedScore > (1 - settings.eLinearRegion) || expectedScore < settings.eLinearRegion) {
      return null;
    }

    if(playerIsBetter && playerRatio == null) {
      throw ArgumentError("playerRatio is required when playerIsBetter is true");
    }

    var winnerRatio = playerIsBetter ? playerRatio! : opponentRatio;

    // The margin from the winner (i.e. the better rating) to the loser (i.e. the player).
    var victoryMargin = scoreFunction.calculateVictoryMargin(expectedScore, winnerRatio);
    var downRdVictoryMargin = scoreFunction.calculateVictoryMargin(downRdExpectedScore, winnerRatio);
    var upRdVictoryMargin = scoreFunction.calculateVictoryMargin(upRdExpectedScore, winnerRatio);
    // Magic number: since expected scores are a sigmoid function that will approach saturation but
    // never quite get there, we want to slightly inflate the output margins to make sure we aren't
    // compressing the outputs with repeated applications of this function.
    victoryMargin *= victoryMarginInflation;
    downRdVictoryMargin *= victoryMarginInflation;
    upRdVictoryMargin *= victoryMarginInflation;

    double expectedPercentage, downRdExpectedPercentage, upRdExpectedPercentage;
    if(!playerIsBetter) {
      expectedPercentage = opponentRatio - victoryMargin;
      downRdExpectedPercentage = opponentRatio - downRdVictoryMargin;
      upRdExpectedPercentage = opponentRatio - upRdVictoryMargin;
    }
    else {
      expectedPercentage = opponentRatio + victoryMargin;
      downRdExpectedPercentage = opponentRatio + downRdVictoryMargin;
      upRdExpectedPercentage = opponentRatio + upRdVictoryMargin;
    }

    return _ExpectedPercentage(
      rating: playerRating,
      rd: playerRD,
      centralValue: expectedPercentage,
      upperValue: upRdExpectedPercentage,
      lowerValue: downRdExpectedPercentage,
    );
  }
}

/// As produced by the Glicko-2 prediction algorithm, an expected percentage is actually
/// a range of percentages, centered around the actual rating with detours up and down
/// based on RD.
class _ExpectedPercentage {
  final double rating;
  final double rd;
  final double centralValue;
  final double upperValue;
  final double lowerValue;

  _ExpectedPercentage({
    required this.rating,
    required this.rd,
    required this.centralValue,
    required this.upperValue,
    required this.lowerValue,
  });

  @override
  String toString() {
    return "${centralValue.toStringAsFixed(2)} - ${lowerValue.toStringAsFixed(2)} + ${upperValue.toStringAsFixed(2)}";
  }
}