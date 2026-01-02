/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_report.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

enum DataSourceError implements ResultErr {
  /// Error in the transport layer, i.e. if a network request
  /// fails.
  transport,
  /// Error in the database layer, i.e. if a database operation
  /// returns an error.
  database,
  /// A request that cannot be fulfilled because it is invalid
  /// in some user-visible way.
  invalidRequest,
  /// A request that cannot be fulfilled because the requested
  /// information is not present in the data source.
  notFound;

  String get message => switch(this) {
    transport => "Error downloading data",
    database => "Error retrieving data",
    invalidRequest => "Request invalid",
    notFound => "Not found"
  };
}

class DataSourceResult<T> extends Result<T, DataSourceError> {
  DataSourceResult.ok(super.result) : super.ok();
  DataSourceResult.err(super.err) : super.err();

}

/// A RatingDataSource is a view into a rating project sufficient for the UI
/// to display it and interact with it.
///
///
abstract interface class RatingDataSource {
  /// Returns the ID of the rating project.
  Future<DataSourceResult<int>> getProjectId();
  Future<DataSourceResult<Sport>> getSport();
  Future<DataSourceResult<String>> getProjectName();
  Future<DataSourceResult<RatingProjectSettings>> getSettings();
  Future<DataSourceResult<List<RatingGroup>>> getGroups();

  /// Get the group for a division, returning the most specific group for that
  /// division (i.e. the group containing [division] that has the fewest total
  /// divisions).
  Future<DataSourceResult<RatingGroup?>> groupForDivision(Division? division);
  Future<DataSourceResult<List<int>>> getMatchDatabaseIds();
  Future<DataSourceResult<List<MatchPointer>>> getMatchPointers();
  Future<DataSourceResult<List<String>>> getMatchSourceIds();
  Future<DataSourceResult<DbShootingMatch>> getLatestMatch();

  /// Look up a shooter rating in [group] by [memberNumber].
  ///
  /// If [allPossibleMemberNumbers] is true and the sport supports calculating
  /// alternate member number forms, this will search by all equivalent member
  /// numbers for the competitor, not only those that they actually entered under.
  ///
  /// Returns Result.ok(null) if no rating is found.
  Future<DataSourceResult<DbShooterRating?>> lookupRating(RatingGroup group, String memberNumber, {bool allPossibleMemberNumbers = false});

  /// Find shooter ratings by name search.
  ///
  /// Returns an empty list if fewer than three characters are provided.
  Future<DataSourceResult<List<DbShooterRating>>> findShooterRatings(RatingGroup group, String name, {int limit = 10});

  Future<DataSourceResult<ShooterRating>> wrapDbRating(DbShooterRating rating);

  Future<DataSourceResult<List<DbShooterRating>>> getRatings(RatingGroup group);

  Future<DataSourceResult<List<RatingReport>>> getAllReports();
  Future<DataSourceResult<List<RatingReport>>> getRecentReports();
}

/// A PreloadedRatingDataSource is a rating data source that has precached its data locally.
abstract interface class PreloadedRatingDataSource {
  Sport getSportSync();
  RatingProjectSettings getSettingsSync();
  DbShooterRating? lookupRatingSync(RatingGroup group, String memberNumber);
  ShooterRating? wrapDbRatingSync(DbShooterRating rating);
  RatingGroup? groupForDivisionSync(Division? division);
  List<DbShooterRating> findShooterRatingsSync(RatingGroup group, String name, {int limit = 10});
}

/// An EditableRatingDataSource is a view into a rating project sufficient to
/// add matches to it.
abstract interface class EditableRatingDataSource {

}
