/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/util.dart';

enum DataSourceError implements ResultErr {
  transport,
  database,
  invalidRequest;

  String get message => switch(this) {
    transport => "Error downloading data",
    database => "Error retrieving data",
    invalidRequest => "Request invalid"
  };
}

class DataSourceResult<T> extends Result<T, DataSourceError> {
  DataSourceResult.ok(super.result) : super.ok();
  DataSourceResult.err(super.err) : super.err();

}

/// A RatingDataSource is a view into a rating project sufficient for the UI
/// to display it and interact with it.
abstract interface class RatingDataSource {
  Future<DataSourceResult<RatingProjectSettings>> getSettings();
  Future<DataSourceResult<List<DbRatingGroup>>> getGroups();
  Future<DataSourceResult<List<int>>> getMatchDatabaseIds();
  Future<DataSourceResult<List<String>>> matchSourceIds();
}

/// An EditableRatingDataSource is a view into a rating project sufficient to
/// add matches to it.
abstract interface class EditableRatingDataSource {

}