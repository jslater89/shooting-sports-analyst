/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

/// A prediction from a user for a shooter's finish.
class UserPrediction {
  final ShooterRating shooter;
  final int bestPlace;
  final int worstPlace;

  UserPrediction({
    required this.shooter,
    required this.bestPlace,
    required this.worstPlace,
  }) {
    if (bestPlace > worstPlace) {
      throw ArgumentError("Best place must be less than worst place");
    }
  }

  UserPrediction.exactPlace(this.shooter, this.bestPlace) : this.worstPlace = bestPlace;

  /// Return a copy of the prediction with the given fields updated.
  ///
  /// This is also a deep copy; [shooter] should not be modified, and
  /// the other fields are copied by value.
  UserPrediction copyWith({
    ShooterRating? shooter,
    int? bestPlace,
    int? worstPlace,
  }) => UserPrediction(
    shooter: shooter ?? this.shooter,
    bestPlace: bestPlace ?? this.bestPlace,
    worstPlace: worstPlace ?? this.worstPlace,
  );
}
