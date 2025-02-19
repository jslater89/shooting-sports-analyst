/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/ordinal_power_law_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/power_law_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/sigmoid_model.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

/// A model for distributing marbles based on the results of a match.
abstract interface class MarbleModel {
  /// The name of the model.
  String get name;

  /// Distribute marbles based on the results of a rating.
  /// 
  /// Add changes to the relevant entries in the [changes] map.
  /// 
  /// The [results] map contains the results of the rating event.
  /// 
  /// The [stakes] map contains the stakes of the competitors.
  /// 
  /// The [totalStake] is the total stake of the match.
  Map<ShooterRating, RatingChange> distributeMarbles({
    required Map<ShooterRating, RatingChange> changes,
    required Map<ShooterRating, RelativeScore> results,
    required Map<ShooterRating, int> stakes,
    required int totalStake,
  });

  static MarbleModel fromName(String name, {required MarbleSettings settings}) => switch(name) {
    PowerLawModel.modelName => PowerLawModel.fromSettings(settings),
    SigmoidModel.modelName => SigmoidModel.fromSettings(settings),
    OrdinalPowerLawModel.modelName => OrdinalPowerLawModel.fromSettings(settings),
    String() => throw ArgumentError("Unknown marble model: $name"),
  };
}