/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/util.dart';

enum ParlayValidity {
  valid,
  overfilled,
  trivialLeg,
  conflictingPredictions;

  bool get isValid => this == valid;

  String get shortDescription => switch(this) {
    valid => "Valid",
    overfilled => "Overfilled",
    trivialLeg => "Trivial leg",
    conflictingPredictions => "Conflicting predictions",
  };

  String get longDescription => switch(this) {
    valid => "The parlay is valid.",
    overfilled => "The parlay is impossible to satisfy: too many shooters are predicted to finish in the same place or range.",
    trivialLeg => "The parlay has a trivial leg: some predictions are necessarily true if the remaining predictions are also true.",
    conflictingPredictions => "The parlay has conflicting predictions: more than one prediction has been made for the same shooter (or pair of shooters, for spread predictions).",
  };
}

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

  Wager copyWith({
    UserPrediction? prediction,
    PredictionProbability? probability,
    double? amount,
  }) => Wager(
    prediction: prediction ?? this.prediction,
    probability: probability ?? this.probability,
    amount: amount ?? this.amount,
  );

  Wager deepCopy() => Wager(
    prediction: prediction.deepCopy(),
    probability: probability.copyWith(),
    amount: amount,
  );

  String get descriptiveString => prediction.descriptiveString;
  String? get tooltipString => prediction.tooltipString(probability.info);
}

class Parlay {
  final List<Wager> legs;
  final double amount;
  PredictionProbability get probability => PredictionProbability.fromParlayLegs(
    legs,
    houseEdgePerLeg: PredictionProbability.standardHouseEdge,
  );
  double get payout => amount * probability.decimalOdds;

  Parlay({
    required this.legs,
    required this.amount,
  });

  Parlay copyWith({
    List<Wager>? legs,
    double? amount,
  }) => Parlay(
    legs: legs ?? this.legs,
    amount: amount ?? this.amount,
  );

  Parlay deepCopy() => Parlay(
    legs: legs.map((leg) => leg.deepCopy()).toList(),
    amount: amount,
  );

  bool isPossible() {
    return Parlay.isParlayPossible(legs);
  }

  ParlayValidity checkValidity({int? fieldSize}) {
    return Parlay.checkParlayValidity(legs, fieldSize: fieldSize);
  }

  List<PlacePrediction> get placePredictions => legs.map((leg) => leg.prediction).where((prediction) => prediction is PlacePrediction).toList().cast<PlacePrediction>();
  List<PercentagePrediction> get percentagePredictions => legs.map((leg) => leg.prediction).where((prediction) => prediction is PercentagePrediction).toList().cast<PercentagePrediction>();

  double get fillProportion => Parlay.parlayFillProportion(placePredictions);
  double get specificity => Parlay.parlaySpecificity(placePredictions);

  static bool isParlayPossible(List<Wager> legs) {
    // Find the maximum place we need to consider
    var placePredictions = legs.where((leg) => leg.prediction is PlacePrediction).map((leg) => leg.prediction as PlacePrediction).toList();
    var maxPlace = placePredictions.map((p) => p.worstPlace).reduce(max);

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
    for (int place = (currentLeg.prediction as PlacePrediction).bestPlace; place <= (currentLeg.prediction as PlacePrediction).worstPlace; place++) {
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

  /// Return a factor from 0 to 1 representing how 'full' the parlay is,
  /// based on only its place components.
  ///
  /// A "full parlay" is one where each place covered by the parlay must be
  /// occupied by a prediction, e.g. a 10-leg parlay where each leg predicts
  /// a top 10 finish.
  ///
  /// Full parlays will have a value of 1.0. Parlays that fail the impossible
  /// parlays check will have a value greater than 1.0.
  static double  parlayFillProportion(List<PlacePrediction> predictions) {
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

    if(predictionProportions.isEmpty) {
      return 0.5;
    }
    return predictionProportions.average;
  }

  /// Return a factor from 0 to 1 representing how specific the parlay is,
  /// based on only its place components.
  ///
  /// A specific parlay is one in which individual legs cover a smaller range
  /// than the overall range covered by the parlay. A 10-leg parlay where each
  /// leg predicts a top 10 finish has zero specificity, whereas a 10-leg parlay
  /// where each leg predicts a single place from 1 to 10 has specificity 1.0.
  static double parlaySpecificity(List<PlacePrediction> predictions) {
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
    if(predictionSpecificities.isEmpty) {
      return 0.5;
    }
    var maximumSpecificity = 1 - (1 / rangeSize);
    var normalizedSpecificity = predictionSpecificities.average / maximumSpecificity;
    return normalizedSpecificity;
  }

  /// Check the validity of a parlay and return the reason.
  ///
  /// Returns [ParlayValidity.valid] if the parlay is valid, or one of the
  /// error reasons if it's not.
  ///
  /// [fieldSize] is the total number of competitors in the match. If not provided,
  /// trivial leg detection will be skipped (may return false negatives).
  static ParlayValidity checkParlayValidity(List<Wager> legs, {int? fieldSize}) {
    // Check for conflicting predictions first
    if (_hasConflictingPredictions(legs)) {
      return ParlayValidity.conflictingPredictions;
    }

    // Check if parlay is overfilled (impossible to satisfy)
    if (!isParlayPossible(legs)) {
      return ParlayValidity.overfilled;
    }

    // Check for trivial legs (requires field size)
    if (fieldSize != null && _isTrivialParlay(legs, fieldSize)) {
      return ParlayValidity.trivialLeg;
    }

    return ParlayValidity.valid;
  }

  /// Check if there are conflicting predictions (multiple predictions for the same shooter(s)).
  static bool _hasConflictingPredictions(List<Wager> legs) {
    var shooterPlacePredictions = <ShooterRating, int>{};
    var shooterPercentagePredictions = <ShooterRating, int>{};
    var spreadPredictions = <String, int>{};

    for (var leg in legs) {
      var prediction = leg.prediction;

      if (prediction is PlacePrediction) {
        shooterPlacePredictions[prediction.shooter] =
            (shooterPlacePredictions[prediction.shooter] ?? 0) + 1;
      }
      else if (prediction is PercentagePrediction) {
        shooterPercentagePredictions[prediction.shooter] =
            (shooterPercentagePredictions[prediction.shooter] ?? 0) + 1;
      }
      else if (prediction is PercentageSpreadPrediction) {
        // Create a canonical key for the pair (order-independent)
        var key = _canonicalSpreadKey(prediction.favorite, prediction.underdog);
        spreadPredictions[key] = (spreadPredictions[key] ?? 0) + 1;
      }
    }

    // Check for multiple place or percentage predictions for the same shooter
    for (var count in shooterPlacePredictions.values) {
      if (count > 1) {
        return true;
      }
    }
    for (var count in shooterPercentagePredictions.values) {
      if (count > 1) {
        return true;
      }
    }
    // Check for multiple spread predictions for the same pair
    for (var count in spreadPredictions.values) {
      if (count > 1) {
        return true;
      }
    }

    return false;
  }

  /// Create a canonical key for a spread prediction pair (order-independent).
  static String _canonicalSpreadKey(ShooterRating shooter1, ShooterRating shooter2) {
    // Use a consistent ordering based on shooter name
    // Compare names lexicographically to create a canonical order
    var name1 = shooter1.name;
    var name2 = shooter2.name;
    if (name1.compareTo(name2) < 0) {
      return "$name1|$name2";
    }
    else {
      return "$name2|$name1";
    }
  }

  /// Check if a parlay has trivial legs (redundant predictions).
  ///
  /// A parlay is trivial if a subset of predictions covers places 1..k,
  /// the remaining predictions only cover places k+1..maxPlace,
  /// and maxPlace equals the field size (meaning the entire field is covered).
  /// In this case, the remaining predictions are automatically true if
  /// the first subset is true.
  ///
  /// [fieldSize] is the total number of competitors in the match.
  static bool _isTrivialParlay(List<Wager> legs, int fieldSize) {
    var placeLegs = legs
        .where((leg) => leg.prediction is PlacePrediction)
        .toList();

    if (placeLegs.length < 2) {
      return false; // Need at least 2 place predictions
    }

    var placePredictions = placeLegs
        .map((leg) => leg.prediction as PlacePrediction)
        .toList();

    if (placePredictions.isEmpty) {
      return false;
    }

    var maxPlace = placePredictions.map((p) => p.worstPlace).reduce(max);

    // If maxPlace doesn't equal fieldSize, there are other competitors not covered,
    // so the remaining predictions are not necessarily trivial
    if (maxPlace < fieldSize) {
      return false;
    }

    // Try each possible partition point k
    // If we can cover 1..k with some predictions, and there's exactly one remaining
    // competitor whose prediction range starts at k (or k+1) and goes to maxPlace,
    // then that competitor's prediction is automatically true (they must finish in k+1..maxPlace)
    for (int k = 1; k < maxPlace; k++) {
      // Check if we can assign a subset of predictions to cover places 1..k exactly
      if (_canCoverRange(placeLegs, 1, k)) {
        // Get remaining predictions (those not needed for 1..k)
        var remainingLegs = _getRemainingLegs(placeLegs, 1, k);

        if (remainingLegs.isNotEmpty) {
          // Check if all remaining legs are for the same competitor
          var remainingShooters = remainingLegs
              .map((leg) => (leg.prediction as PlacePrediction).shooter)
              .toSet();

          // If there's exactly one remaining competitor
          if (remainingShooters.length == 1) {
            // Get the combined range of all remaining predictions for that competitor
            var combinedBestPlace = remainingLegs
                .map((leg) => (leg.prediction as PlacePrediction).bestPlace)
                .reduce(min);
            var combinedWorstPlace = remainingLegs
                .map((leg) => (leg.prediction as PlacePrediction).worstPlace)
                .reduce(max);

            // If the combined range starts at k or k+1 and goes to maxPlace,
            // and only covers k+1..maxPlace (no overlap with 1..k except possibly at k),
            // then it's trivial: this competitor must finish in k+1..maxPlace
            if (combinedBestPlace <= k + 1 &&
                combinedWorstPlace >= maxPlace &&
                _onlyCoversRange(remainingLegs, k + 1, maxPlace)) {
              return true; // Trivial: this competitor must finish in k+1..maxPlace
            }
          }
        }
      }
    }

    return false;
  }

  /// Check if we can assign predictions to cover places [startPlace]..[endPlace] exactly.
  static bool _canCoverRange(List<Wager> legs, int startPlace, int endPlace) {
    return _canAssignToRange(legs, 0, <int, Wager>{}, startPlace, endPlace);
  }

  /// Recursively try to assign predictions to cover a specific range.
  static bool _canAssignToRange(
    List<Wager> legs,
    int predictionIndex,
    Map<int, Wager> currentAssignment,
    int startPlace,
    int endPlace,
  ) {
    // Check if we've covered all places in the range
    if (currentAssignment.length == (endPlace - startPlace + 1)) {
      // Verify we covered exactly the range (no gaps, no extras)
      for (int place = startPlace; place <= endPlace; place++) {
        if (!currentAssignment.containsKey(place)) {
          return false;
        }
      }
      return true;
    }

    // If we've processed all predictions but haven't covered the range, fail
    if (predictionIndex >= legs.length) {
      return false;
    }

    var currentLeg = legs[predictionIndex];
    var pred = currentLeg.prediction as PlacePrediction;

    // Try each place in this prediction's range that's within our target range
    for (int place = pred.bestPlace; place <= pred.worstPlace; place++) {
      // Only consider places in our target range
      if (place < startPlace || place > endPlace) {
        continue;
      }

      // Skip if this place is already taken
      if (currentAssignment.containsKey(place)) {
        continue;
      }

      // Try assigning this prediction to this place
      currentAssignment[place] = currentLeg;

      // Recursively try to assign remaining predictions
      if (_canAssignToRange(legs, predictionIndex + 1, currentAssignment, startPlace, endPlace)) {
        return true;
      }

      // Backtrack
      currentAssignment.remove(place);
    }

    // Also try skipping this prediction entirely
    return _canAssignToRange(legs, predictionIndex + 1, currentAssignment, startPlace, endPlace);
  }

  /// Get the legs that are NOT needed to cover places [startPlace]..[endPlace].
  /// This finds one valid assignment and returns the unused legs.
  static List<Wager> _getRemainingLegs(List<Wager> legs, int startPlace, int endPlace) {
    var assignment = <int, Wager>{};
    _findOneAssignment(legs, 0, assignment, startPlace, endPlace);

    var usedLegs = assignment.values.toSet();
    return legs.where((leg) => !usedLegs.contains(leg)).toList();
  }

  /// Find one valid assignment (helper for _getRemainingLegs).
  static bool _findOneAssignment(
    List<Wager> legs,
    int predictionIndex,
    Map<int, Wager> assignment,
    int startPlace,
    int endPlace,
  ) {
    if (assignment.length == (endPlace - startPlace + 1)) {
      for (int place = startPlace; place <= endPlace; place++) {
        if (!assignment.containsKey(place)) {
          return false;
        }
      }
      return true;
    }

    if (predictionIndex >= legs.length) {
      return false;
    }

    var currentLeg = legs[predictionIndex];
    var pred = currentLeg.prediction as PlacePrediction;

    for (int place = pred.bestPlace; place <= pred.worstPlace; place++) {
      if (place < startPlace || place > endPlace) {
        continue;
      }
      if (assignment.containsKey(place)) {
        continue;
      }

      assignment[place] = currentLeg;
      if (_findOneAssignment(legs, predictionIndex + 1, assignment, startPlace, endPlace)) {
        return true;
      }
      assignment.remove(place);
    }

    return _findOneAssignment(legs, predictionIndex + 1, assignment, startPlace, endPlace);
  }

  /// Check if the given legs only cover places in the range [startPlace]..[endPlace].
  static bool _onlyCoversRange(List<Wager> legs, int startPlace, int endPlace) {
    for (var leg in legs) {
      var pred = leg.prediction as PlacePrediction;
      // If any prediction covers a place outside the range, return false
      if (pred.bestPlace < startPlace || pred.worstPlace > endPlace) {
        return false;
      }
    }
    return true;
  }

}
