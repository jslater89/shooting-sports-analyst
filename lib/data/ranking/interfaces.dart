/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
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

  RatingGroup? getGroup(String uuid);
}

class DivisionRatingGroupProvider implements RatingGroupsProvider {
  final List<Division> divisions;

  DivisionRatingGroupProvider(String sportName,this.divisions) :
    divisionRatingGroups = divisions.mapIndexed((index, d) => RatingGroup(
      uuid: "${sportName.toLowerCase()}-${d.name.toLowerCase().replaceAll(" ", "-")}",
      sortOrder: index,
      sportName: sportName,
      name: d.name,
      displayName: d.shortDisplayName,
      divisionNames: [d.name],
    )).toList()
  {
    builtinRatingGroups = divisionRatingGroups;
    defaultRatingGroups = divisionRatingGroups;
  }

  @override
  final List<RatingGroup> divisionRatingGroups;

  @override
  late final List<RatingGroup> builtinRatingGroups;

  @override
  late final List<RatingGroup> defaultRatingGroups;

  @override
  RatingGroup? getGroup(String uuid) {
    return divisionRatingGroups.firstWhereOrNull((d) => d.uuid == uuid);
  }
}

abstract interface class ConnectivityCalculator {
  /// The data required for this calculator to calculate
  /// a baseline connectivity score.
  ///
  /// Only data requested in this list will be provided to
  /// [calculateConnectivityBaseline].
  List<BaselineConnectivityRequiredData> get requiredBaselineData;

  /// The data required for this calculator to calculate
  /// a competitor connectivity score. This is used primarily by
  /// the project rollback system to determine what data is necessary
  /// to provide to [rollbackCompetitorData].
  List<CompetitorConnectivityRequiredData> get requiredCompetitorData;

  /// Calculate the baseline connectivity score for a rating
  /// group. Data requsted in [requiredBaselineData] will be
  /// provided. Other data will be null.
  double calculateConnectivityBaseline({
    int? matchCount,
    int? competitorCount,
    double? connectivitySum,
    List<double>? connectivityScores,
  });

  /// The number of matches to use for the competitor connectivity calculation.
  int get matchWindowCount;

  /// The number of matches to use for the baseline connectivity calculation.
  int get baselineMatchWindowCount;

  /// Calculate the connectivity score for a shooter.
  NewConnectivity calculateRatingConnectivity(DbShooterRating rating);

  /// Update the data structures on DbShooterRating that this calculator requires.
  ///
  /// Data not requested in [requiredCompetitorData] may be null.
  ///
  /// Return true if the project loader needs to save the rating after this call.
  /// Project loaders may batch updates, so updates made here may not be immediately
  /// persisted.
  ///
  /// [competitors] is a list of all competitors in the match.
  bool updateCompetitorData({
    required DbShooterRating rating,
    ShootingMatch? match,
    Iterable<DbShooterRating>? competitors,
    int? competitorCount,
    List<MatchPointer>? matchPointers,
  });

  /// Rollback the data structures on DbShooterRating that this calculator requires.
  ///
  /// Data not requested in [requiredCompetitorData] may be null.
  ///
  /// Return true if the project loader needs to save the rating after this call.
  /// Project loaders may batch updates, so updates made here may not be immediately
  /// persisted.
  ///
  /// Unlike [updateCompetitorData], this method is called with a list of matches,
  /// since step-by-step rollback may be computationally expensive.
  bool rollbackCompetitorData({
    required DbShooterRating rating,
    List<ShootingMatch>? matchesRemoved,
    List<MatchPointer>? matchPointers,
    Iterable<Iterable<DbShooterRating>>? competitorsRemoved,
    Iterable<int>? competitorCountsRemoved,
  });

  /// Whether to use historical connectivity data for rollback.
  ///
  /// If true, the connectivity calculator expects the rollback system to
  /// use the historical connectivity data to update the rating's connectivity and
  /// rawConnectivity prior to calling [rollbackCompetitorData].
  bool get useHistoryForRollback;

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
enum BaselineConnectivityRequiredData {
  matchCount,
  competitorCount,
  connectivitySum,
  connectivityScores,
}

/// The data required for a connectivity calculator to calculate a competitor
/// connectivity score.
enum CompetitorConnectivityRequiredData {
  /// A simple count of competitors in the match, according to the relevant filters.
  /// This will include unrated/non-rateable competitors, but requires no database lookups.
  competitorCount,
  /// An iterable of the rating objects for each competitor in the match.
  competitorRatings,
  /// The match being added, or matches being rolled back.
  match,
  /// The list of match pointers for the rating project. When rolling back, this list will
  /// contain the match pointers after removing the rolled-back matches.
  matchPointers,
}

class NewConnectivity {
  final double connectivity;
  final double rawConnectivity;

  const NewConnectivity({
    required this.connectivity,
    required this.rawConnectivity,
  });
}
