/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

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
  /// Glicko-2 is always 'by match', but considers stages inside each match
  /// step.
  bool get byStage => false;

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
    // we're in oneshot mode, so we should have 1 shooter and scores
    // for the full match.

    if(scores.length == 1) {
      // No changes for a match with only one competitor
      return {};
    }

    var shooter = shooters.first as Glicko2Rating;
    var shooterMatchScore = matchScores[shooter];
    if(shooterMatchScore == null) {
      throw Exception("Shooter match score is null");
    }

    var opponents = matchScores.keys.where((key) => key != shooter).toList();
    opponents = _selectOpponents(matchScores, shooter.rating, shooterMatchScore.ratio);

    /// For each competitor, we only update ratings for the stages that they completed.
    var shooterStageScores = shooterMatchScore.stageScores.entries
      .where((entry) => entry.key.scoring.countsInRatings && !entry.value.isDnf)
      .map((entry) => entry.value)
      .toList();

    // Step 1: V and delta

    // Calculate sum-of-V
    var vSum = 0.0;
    var deltaSum = 0.0;

    // To handle multiple stages against the same opponent within a match/rating period,
    // we just pretend that each stage-opponent pair is a separate 'game' for Glicko
    // purposes.
    //
    // So, when calculating sum-of-V, we can just do nested iteration over stages and
    // opponent scores, and add to V for each stage-opponent pair.
    // We can also calculate the sum component of delta while iterating to save a
    // pass over all the scores.
    for(var opponent in opponents) {
      opponent as Glicko2Rating;
      var opponentRDAtMatch = opponent.calculateCurrentInternalRD(asOfDate: match.date);
      var opponentMatchScore = matchScores[opponent];
      if(opponentMatchScore == null) {
        continue;
      }

        var vForOpponent = _glickoVForOpponent(shooter.internalRating, opponent.internalRating, opponentRDAtMatch);
        vSum += vForOpponent;

        var shooterStageScoreRatio = shooterMatchScore.ratio;
        var opponentStageScoreRatio = opponentMatchScore.ratio;
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

    if(newVolatility > 0.15) {
      newVolatility = 0.15;
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
          Glicko2Rater.stagesKey: shooterStageScores.length.toDouble(),
        },
        infoLines: [
          "Finish: {{finish}} of {{competitors}} at {{finishPercent}}%",
          "Rating ± Change: {{rating}}/{{change}}",
          "RD ± Change: {{rd}}/{{rdChange}}",
          "Volatility ± Change: {{volatility}}/{{volatilityChange}}",
          "Considered {{opponents}} opponents",
        ],
        infoData: [
          RatingEventInfoElement.int(name: "finish", intValue: shooterMatchScore.place),
          RatingEventInfoElement.int(name: "competitors", intValue: matchScores.length),
          RatingEventInfoElement.double(name: "finishPercent", doubleValue: shooterMatchScore.percentage, numberFormat: "%00.2f"),
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

  /// Get opponents based on the selection mode. Input must be sorted by match finish.
  List<ShooterRating> _selectOpponents(Map<ShooterRating, RelativeMatchScore> matchScores, double competitorRating, double competitorRatio) {
    var opponentsByFinish = matchScores.keys.toList();
    var opponentsByRating = opponentsByFinish.sorted((a, b) => b.rating.compareTo(a.rating)).toList();
    var selectionMode = settings.opponentSelectionMode;
    if(selectionMode == OpponentSelectionMode.all) {
      return opponentsByFinish;
    }
    else if(selectionMode == OpponentSelectionMode.top10Pct) {
      return _selectTop10PctOpponents(opponentsByFinish, opponentsByRating);
    }
    else if(selectionMode == OpponentSelectionMode.nearby) {
      return _selectNearbyOpponents(matchScores, opponentsByRating, competitorRating, competitorRatio);
    }
    else if(selectionMode == OpponentSelectionMode.topAndNearby) {
      var topOpponents = _selectTop10PctOpponents(opponentsByFinish, opponentsByRating).toSet();
      topOpponents.addAll(_selectNearbyOpponents(matchScores, opponentsByRating, competitorRating, competitorRatio));
      return topOpponents.toList();
    }
    else {
      throw Exception("Invalid opponent selection mode: $selectionMode");
    }
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

  List<ShooterRating> _selectNearbyOpponents(Map<ShooterRating, RelativeMatchScore> matchScores, List<ShooterRating> opponentsByRating, double competitorRating, double competitorRatio) {
    List<ShooterRating> nearbyOpponents = [];
    for(var opponent in matchScores.keys) {
      if((opponent.rating - competitorRating).abs() <= settings.maximumRD) {
        nearbyOpponents.add(opponent);
        continue;
      }

      var opponentMatchScore = matchScores[opponent];
      if(opponentMatchScore == null) {
        continue;
      }
      var opponentRatio = opponentMatchScore.ratio;
      if((opponentRatio - competitorRatio).abs() <= 0.1) {
        nearbyOpponents.add(opponent);
      }
    }

    return nearbyOpponents;
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
}
