/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/util.dart';

class Wager {
  final UserPrediction prediction;
  final double amount;
  final PredictionProbability probability;

  double get payout => amount * probability.decimalOdds;

  Wager({
    required this.prediction,
    required this.probability,
    required this.amount,
  });
}

class Parlay {
  final List<Wager> legs;
  final double amount;
  PredictionProbability get probability => PredictionProbability.fromParlayLegs(legs);

  Parlay({
    required this.legs,
    required this.amount,
  });

  bool isPossible() {
    return Parlay.isParlayPossible(legs);
  }

  double get fillProportion => Parlay.parlayFillProportion(legs.map((leg) => leg.prediction).toList());
  double get specificity => Parlay.parlaySpecificity(legs.map((leg) => leg.prediction).toList());

  static bool isParlayPossible(List<Wager> legs) {
    // Find the maximum place we need to consider
    int maxPlace = legs.map((p) => p.prediction.worstPlace).reduce(max);

    // Try to assign each prediction to a valid place
    return _canAssignPredictions(legs, 0, <int, Wager>{}, maxPlace);
  }

  static bool _canAssignPredictions(
    List<Wager> legs,
    int predictionIndex,
    Map<int, Wager> currentAssignment,
    int maxPlace
  ) {
    // Base case: all predictions assigned
    if (predictionIndex >= legs.length) {
      return true;
    }

    var currentLeg = legs[predictionIndex];

    // Try each place in this prediction's range
    for (int place = currentLeg.prediction.bestPlace; place <= currentLeg.prediction.worstPlace; place++) {
      // Skip if this place is already taken
      if (currentAssignment.containsKey(place)) {
        continue;
      }

      // Try assigning this prediction to this place
      currentAssignment[place] = currentLeg;

      // Recursively try to assign remaining predictions
      if (_canAssignPredictions(legs, predictionIndex + 1, currentAssignment, maxPlace)) {
        return true;
      }

      // Backtrack
      currentAssignment.remove(place);
    }

    return false;
  }

  /// Return a factor from 0 to 1 representing how 'full' the parlay is.
  ///
  /// A "full parlay" is one where each place covered by the parlay must be
  /// occupied by a prediction, e.g. a 10-leg parlay where each leg predicts
  /// a top 10 finish.
  ///
  /// Full parlays will have a value of 1.0. Parlays that fail the impossible
  /// parlays check will have a value greater than 1.0.
  static double  parlayFillProportion(List<UserPrediction> predictions) {
    // Calculate the number of predictions that cover each place.
    Map<int, int> requiredAtPlace = {};
    for(var leg in predictions) {
      for(var place = leg.bestPlace; place <= leg.worstPlace; place++) {
        requiredAtPlace.increment(place);
      }
    }

    // Calculate the fill proportion for each prediction.
    List<double> predictionProportions = [];
    for(var leg in predictions) {
      var range = leg.worstPlace - leg.bestPlace + 1;
      List<double> proportions = [];
      for(var place = leg.bestPlace; place <= leg.worstPlace; place++) {
        proportions.add(requiredAtPlace[place]! / range);
      }
      predictionProportions.add(proportions.average);
    }
    return predictionProportions.average;
  }

  /// Return a factor from 0 to 1 representing how specific the parlay is.
  ///
  /// A specific parlay is one in which individual legs cover a smaller range
  /// than the overall range covered by the parlay. A 10-leg parlay where each
  /// leg predicts a top 10 finish has zero specificity, whereas a 10-leg parlay
  /// where each leg predicts a single place from 1 to 10 has specificity 1.0.
  static double parlaySpecificity(List<UserPrediction> predictions) {
    Map<int, bool> coversPlace = {};
    for(var leg in predictions) {
      for(var place = leg.bestPlace; place <= leg.worstPlace; place++) {
        coversPlace[place] = true;
      }
    }
    int rangeSize = coversPlace.length;

    List<double> predictionSpecificities = [];
    for(var leg in predictions) {
      var range = leg.worstPlace - leg.bestPlace + 1;
      var specificity = range / rangeSize;
      predictionSpecificities.add(1 - specificity);
    }
    var maximumSpecificity = 1 - (1 / rangeSize);
    var normalizedSpecificity = predictionSpecificities.average / maximumSpecificity;
    return normalizedSpecificity;
  }

}
