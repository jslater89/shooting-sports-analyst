/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// A [Sport] that can provide match strength information for [Rater]'s
/// match strength mod should provide an implementation of this interface.
///
/// See uspsaSport for more. The math is tuned more or less to its values
/// (for now), so use something similar for other sports.
abstract interface class RatingStrengthProvider {
  /// Return the strength for a given class.
  double strengthForClass(Classification? c);
  /// Return the center strength for this sport.
  double get centerStrength;
}

/// A [Sport] that can provide pubstomp information for [Rater]'s
/// pubstomp multiplier should provide an implementation of this interface.
///
/// See uspsaSport for more.
abstract interface class PubstompProvider {
  bool isPubstomp({
    required RelativeMatchScore firstScore,
    required RelativeMatchScore secondScore,
    Classification? firstClass,
    Classification? secondClass,
    required ShooterRating firstRating,
    required ShooterRating secondRating,
  });
}