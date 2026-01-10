/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'prediction_game.g.dart';

/// A prediction game is a collection of wagers and users.
@collection
class PredictionGame {
  Id id = Isar.autoIncrement;

  String name;

  String? description;

  @Backlink(to: 'games')
  /// The matches that are part of this game.
  final matchPreps = IsarLinks<MatchPrep>();

  /// The minimum number of competitors required in a rating group for that group to be
  /// eligible for the game.
  int minimumCompetitorsRequired;

  // TODO: a way to specify matchPrep -> allowed rating groups
  // and/or other ways to determine what we want to offer odds on
  // (e.g. Glicko-2 can say "we couldn't do accurate predictions because of too big a rating gap")

  /// Get the available rating groups for the prediction sets in a given match prep.
  ///
  /// Available rating groups are those that have at least [minimumCompetitorsRequired] competitors
  /// in a given prediction set.
  Map<PredictionSet, List<RatingGroup>> availableRatingGroups(MatchPrep prep) {
    if(!matchPreps.contains(prep)) {
      return {};
    }

    if(prep.predictionSets.isEmpty) {
      return {};
    }

    Map<PredictionSet, List<RatingGroup>> availableRatingGroups = {};
    var ratingGroups = prep.ratingProject.value!.groups;
    for(var predictionSet in prep.predictionSets) {
      for(var group in ratingGroups) {
        var registrations = predictionSet.algorithmPredictions.where((prediction) =>
          prediction.group.value == group).map((prediction) => prediction.rating.value).toList();
        if(registrations.length >= minimumCompetitorsRequired) {
          availableRatingGroups.addToList(predictionSet, group);
        }
      }
    }
    return availableRatingGroups;
  }

  @Backlink(to: 'game')
  final users = IsarLinks<PredictionGamePlayer>();

  @Backlink(to: 'game')
  final wagers = IsarLinks<DbWager>();

  @Backlink(to: 'game')
  final transactions = IsarLinks<PredictionGameTransaction>();

  DateTime created;
  DateTime? start;
  DateTime? end;

  PredictionGame({
    required this.name,
    this.description,
    required this.created,
    this.start,
    this.end,
    this.minimumCompetitorsRequired = 10,
  });
}