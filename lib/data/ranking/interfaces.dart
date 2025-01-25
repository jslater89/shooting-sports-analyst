/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// A [Sport] that can provide match strength information for [Rater]'s
/// match strength mod should provide an implementation of this interface.
///
/// See uspsaSport for more. The math is tuned more or less to its values
/// (for now), so use something similar for other sports.
abstract interface class RatingStrengthProvider {
  /// Returns the strength for a given class.
  double strengthForClass(Classification? c);
  /// Returns the center strength for this sport.
  double get centerStrength;

  /// Returns a percentage multiplier for a given match level.
  double strengthBonusForMatchLevel(MatchLevel? level);
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

/// A [Sport] that can provide default rating groups for a rating history
/// should provide an implementation of this interface.
///
/// These rating groups WILL be persisted to the database. Use a constant
/// string ID for each group in the UUID property, of the form
/// `'sportname-groupname'`.
abstract interface class RatingGroupsProvider {
  List<RatingGroup> get builtinRatingGroups;
  List<RatingGroup> get divisionRatingGroups;
  List<RatingGroup> get defaultRatingGroups;
}

abstract interface class ConnectivityCalculator {
  /// The data required for this calculator to calculate
  /// a baseline connectivity score.
  /// 
  /// Only data requested in this list will be provided to
  /// [calculateConnectivityBaseline].
  List<ConnectivityRequiredData> get requiredBaselineData;
  
  /// Calculate the baseline connectivity score for a rating
  /// group. Data requsted in [requiredBaselineData] will be
  /// provided. Other data will be null.
  double calculateConnectivityBaseline({
    int? matchCount,
    int? competitorCount,
    double? connectivitySum,
    List<double>? connectivityScores,
  });

  /// The number of matches to use for the connectivity calculation.
  int get matchWindowCount;

  /// Calculate the connectivity score for a shooter.
  NewConnectivity calculateRatingConnectivity(DbShooterRating rating);

  /// Calculate the connectivity score for a match, given a list of
  /// connectivity scores.
  double calculateMatchConnectivity(List<double> connectivityScores);
  /// Calculate the scale factor for a given match connectivity vs. a baseline.
  /// 
  /// Clamp to [minScale] and [maxScale] if they are provided.
  double getScaleFactor({
    required double connectivity,
    required double baseline,
    double minScale = 0.8,
    double maxScale = 1.2,
  });

  /// The default baseline connectivity score.
  double get defaultBaselineConnectivity;
}

/// The data required for a connectivity calculator to calculate a baseline
/// connectivity score.
enum ConnectivityRequiredData {
  matchCount,
  competitorCount,
  connectivitySum,
  connectivityScores,
}

class NewConnectivity {
  final double connectivity;
  final double rawConnectivity;

  const NewConnectivity({
    required this.connectivity,
    required this.rawConnectivity,
  });
}