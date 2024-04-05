/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';

/// A RatingDataSource is a view into a rating project sufficient for the UI
/// to display it and interact with it.
abstract interface class RatingDataSource {
  Future<RatingProjectSettings> getSettings();
  Future<List<int>> getMatchDatabaseIds();
  Future<List<String>> matchSourceIds();
}

/// An EditableRatingDataSource is a view into a rating project sufficient to
/// add matches to it.
abstract interface class EditableRatingDataSource {

}