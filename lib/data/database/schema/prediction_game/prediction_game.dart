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
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
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

  /// The IDs of match preps that are attached to this game but disabled/unavailable for wagers.
  List<int> disabledMatchPreps = [];

  /// The minimum number of competitors required in a rating group at a match for that
  /// match/group to be eligible for the game.
  int minimumCompetitorsRequired;

  /// The minimum finish ratio required (using the center of the range, however the prediction
  /// algorithm defines 'center') for a competitor to be eligible for wagers. If null,
  /// all competitors are eligible.
  double? minimumWagerableCompetitorFinishRatio;

  /// The minimum number of stages required in a competitor's history for them to be eligible for wagers.
  /// If null, all competitors are eligible.
  int? minimumWagerableStageCount;

  /// The minimum number of matches required in a competitor's history for them to be eligible for wagers.
  /// If null, all competitors are eligible.
  int? minimumWagerableMatchCount;

  /// The maximum number of days since a competitor's last rating activity for them to be eligible for wagers.
  /// If null, all competitors are eligible.
  int? maximumWagerableRatingAgeDays;

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

  @ignore
  /// Whether this game is currently active.
  bool get isActive => hasStarted && !hasEnded;

  @ignore
  bool get hasStarted => start == null || start!.isBefore(DateTime.now());

  @ignore
  bool get hasEnded => end != null && end!.isBefore(DateTime.now());

  PredictionGame({
    required this.name,
    this.description,
    required this.created,
    this.start,
    this.end,
    this.minimumCompetitorsRequired = 10,
  });

  /// Check if a competitor is eligible for a wager.
  WagerIneligibilityReason? checkValidity(AlgorithmPrediction prediction, {required int competitorCount}) {
    var ratingStageCount = prediction.shooter.stageCount;
    var ratingMatchCount = prediction.shooter.matchCount;
    var lastActivity = prediction.shooter.lastSeen;
    var daysSinceLastActivity = DateTime.now().difference(lastActivity).inDays;

    if(minimumWagerableCompetitorFinishRatio != null && prediction.hasRatioPredictions && prediction.ratioCenter! < minimumWagerableCompetitorFinishRatio!) {
      return WagerIneligibilityReason.insufficientFinishRatio;
    }
    if(minimumWagerableStageCount != null && ratingStageCount != null && ratingStageCount < minimumWagerableStageCount!) {
      return WagerIneligibilityReason.insufficientStageCount;
    }
    if(minimumWagerableMatchCount != null && ratingMatchCount != null && ratingMatchCount < minimumWagerableMatchCount!) {
      return WagerIneligibilityReason.insufficientMatchCount;
    }
    if(maximumWagerableRatingAgeDays != null && daysSinceLastActivity > maximumWagerableRatingAgeDays!) {
      return WagerIneligibilityReason.staleRating;
    }
    if(competitorCount < minimumCompetitorsRequired) {
      return WagerIneligibilityReason.insufficientCompetitorsInGroup;
    }

    return null;
  }
}

/// The reasons a competitor may be ineligible for a wager.
enum WagerIneligibilityReason {
  /// The competitor's finish ratio is below the minimum required.
  insufficientFinishRatio,
  /// The competitor does not have enough stage count in their history.
  insufficientStageCount,
  /// The competitor does not have enough match count in their history.
  insufficientMatchCount,
  /// The competitor does not have enough competitors in the rating group.
  insufficientCompetitorsInGroup,
  /// The competitor has not been seen recently enough.
  staleRating;

  /// Get a human-readable description of the reason for ineligibility.
  ///
  /// If [game] is provided, the description includes the minimum required values for the game.
  String uiDescription([PredictionGame? game]) {
    if(game != null) {
      var minimumFinishRatioSentenceEnd = game.minimumWagerableCompetitorFinishRatio != null ? "the minimum requirement of ${game.minimumWagerableCompetitorFinishRatio?.asPercentage(decimals: 2, includePercent: true) ?? "unknown"}" : "the minimum requirement";
      var minimumStageCountSentenceEnd = game.minimumWagerableStageCount != null ? " (minimum ${game.minimumWagerableStageCount} required)." : ".";
      var minimumMatchCountSentenceEnd = game.minimumWagerableMatchCount != null ? " (minimum ${game.minimumWagerableMatchCount} required)." : ".";
      var minimumCompetitorCountSentenceEnd = game.minimumCompetitorsRequired > 0 ? " (minimum of ${game.minimumCompetitorsRequired} required)." : ".";
      var staleRatingSentenceEnd = game.maximumWagerableRatingAgeDays != null ? " (maximum of ${game.maximumWagerableRatingAgeDays} since last activity)." : ".";
      return switch(this) {
        insufficientFinishRatio => "The competitor is not projected to finish above $minimumFinishRatioSentenceEnd.",
        insufficientStageCount => "The competitor does not have enough stages in their history$minimumStageCountSentenceEnd",
        insufficientMatchCount => "The competitor does not have enough matches in their history$minimumMatchCountSentenceEnd",
        insufficientCompetitorsInGroup => "There are not enough competitors in this rating group at the match$minimumCompetitorCountSentenceEnd",
        staleRating => "The competitor has not been seen recently enough$staleRatingSentenceEnd"
      };
    }
    return switch(this) {
      insufficientFinishRatio => "The competitor is not projected to finish above the minimum requirement.",
      insufficientStageCount => "The competitor does not have enough stages in their history.",
      insufficientMatchCount => "The competitor does not have enough matches in their history.",
      insufficientCompetitorsInGroup => "There are not enough competitors in this rating group at the match.",
      staleRating => "The competitor has not been seen recently enough."
    };
  }

  String get uiShortDescription {
    return switch(this) {
      insufficientFinishRatio => "Projected finish too low",
      insufficientStageCount => "Insufficient stage history",
      insufficientMatchCount => "Insufficient match history",
      insufficientCompetitorsInGroup => "Too few competitors in group",
      staleRating => "Not seen recently"
    };
  }
}