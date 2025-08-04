/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/fantasy/fantasy_points_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_display_mode.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/match_prediction_mode.dart';

part 'preferences.g.dart';

@collection
class ApplicationPreferences {
  /// Application preferences are a database-backed singleton.
  final Id id = 1;

  /// Whether the welcome dialog for 8.0-alpha has been shown.
  bool welcome80Shown = false;

  /// Whether the welcome dialog for 8.0-beta has been shown.
  bool welcome80BetaShown = false;

  /// The ID of the last project that was loaded.
  int? lastProjectId;

  /// Whether penalties are counted towards the available points.
  bool availablePointsCountPenalties = true;

  /// True if available points on hit factor fixed time stages are calculated
  /// based on the maximum number of points achieved, rather than the number of
  /// points possible.
  bool improvedFixedTimeMax = true;

  /// The name of the last-selected fantasy points mode.
  String fantasyPointsModeName = FantasyPointsMode.off.name;
  @ignore
  FantasyPointsMode get fantasyPointsMode => FantasyPointsMode.values.firstWhereOrNull((e) => e.name == fantasyPointsModeName) ?? FantasyPointsMode.off;
  set fantasyPointsMode(FantasyPointsMode value) {
    fantasyPointsModeName = value.name;
  }

  /// The name of the last-selected rating display mode.
  String ratingDisplayModeName = RatingDisplayMode.preMatch.name;
  @ignore
  RatingDisplayMode get ratingDisplayMode => RatingDisplayMode.values.firstWhereOrNull((e) => e.name == ratingDisplayModeName) ?? RatingDisplayMode.preMatch;
  set ratingDisplayMode(RatingDisplayMode value) {
    ratingDisplayModeName = value.name;
  }

  /// The name of the last selected match prediction mode.
  String matchPredictionModeName = MatchPredictionMode.none.name;
  @ignore
  MatchPredictionMode get matchPredictionMode => MatchPredictionMode.values.firstWhereOrNull((e) => e.name == matchPredictionModeName) ?? MatchPredictionMode.none;
  set matchPredictionMode(MatchPredictionMode value) {
    matchPredictionModeName = value.name;
  }
}
