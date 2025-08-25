// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/match_prediction_mode.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/ui/booth/global_card_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/score_utils.dart';

part 'scorecard_model.g.dart';

@JsonSerializable(constructor: 'json')
class ScorecardModel {
  @JsonKey(includeFromJson: false, includeToJson: false)
  late BroadcastBoothModel parent;

  @JsonKey(defaultValue: 0)
  int id;
  String name;

  // We're switching to full filters for scoring, but we keep the old FilterSet-only
  // score filters for backward compatibility.
  FilterSet scoreFilters;
  ScorecardFilters? newScoreFilters;

  TableTextSize tableTextSize;

  @JsonKey(includeFromJson: false, includeToJson: false)
  ScorecardFilters get fullScoreFilters {
    if(newScoreFilters == null) {
      return ScorecardFilters(
        filterSet: scoreFilters,
      );
    }
    return newScoreFilters!;
  }
  void setFullScoreFilters(ScorecardFilters filters) {
    newScoreFilters = filters;
    if(filters.filterSet == null) {
      scoreFilters = filters.filterSet!;
    }
  }

  ScorecardFilters displayFilters;

  // Time warp settings
  DateTime? scoresAfter;
  DateTime? scoresBefore;

  @JsonKey(defaultValue: MatchPredictionMode.none)
  MatchPredictionMode predictionMode;

  @JsonKey(includeFromJson: false, includeToJson: false)
  bool get scoresMultipleDivisions => (fullScoreFilters.filterSet?.activeDivisions.length ?? 0) > 1;

  bool hasHorizontalScrollbar;

  ScorecardModel({
    required this.id,
    required this.name,
    required this.scoreFilters,
    required this.displayFilters,
    required this.parent,
    this.newScoreFilters,
    this.tableTextSize = TableTextSize.normal,
    this.scoresAfter,
    this.scoresBefore,
    this.predictionMode = MatchPredictionMode.none,
    this.hasHorizontalScrollbar = false,
  }) {
    if(newScoreFilters == null) {
      newScoreFilters = ScorecardFilters(filterSet: scoreFilters);
    }
  }

  // parent is set by the parent model
  ScorecardModel.json(
    this.id,
    this.name,
    this.scoreFilters,
    this.newScoreFilters,
    this.displayFilters,
    {
      this.tableTextSize = TableTextSize.normal,
      required this.predictionMode,
      this.scoresAfter,
      this.scoresBefore,
      this.hasHorizontalScrollbar = false,
    }
  );

  ScorecardModel copy() {
    if(newScoreFilters == null) {
      newScoreFilters = ScorecardFilters(filterSet: scoreFilters);
    }
    return ScorecardModel(
      id: id,
      name: name,
      scoreFilters: scoreFilters.copy(),
      newScoreFilters: newScoreFilters?.copy(),
      displayFilters: displayFilters.copy(),
      parent: parent,
      scoresAfter: scoresAfter,
      scoresBefore: scoresBefore,
      predictionMode: predictionMode,
      tableTextSize: tableTextSize,
      hasHorizontalScrollbar: hasHorizontalScrollbar,
    );
  }

  void copyFrom(ScorecardModel other) {
    name = other.name;
    scoreFilters = other.scoreFilters.copy();
    newScoreFilters = other.newScoreFilters?.copy();
    displayFilters = other.displayFilters.copy();
    scoresAfter = other.scoresAfter;
    scoresBefore = other.scoresBefore;
    predictionMode = other.predictionMode;
    tableTextSize = other.tableTextSize;
    hasHorizontalScrollbar = other.hasHorizontalScrollbar;
  }

  void copyGlobalSettingsFrom(GlobalScorecardSettingsModel settings) {
    predictionMode = settings.predictionMode;
    tableTextSize = settings.tableTextSize;
    hasHorizontalScrollbar = settings.hasHorizontalScrollbar;
  }

  factory ScorecardModel.fromJson(Map<String, dynamic> json) => _$ScorecardModelFromJson(json);
  Map<String, dynamic> toJson() => _$ScorecardModelToJson(this);

  String toString() => name;

  // These fields are used so that when we generate new BoothScorecard widgets,
  // we don't need to recalculate scores if time/settings haven't changed.

  @JsonKey(includeFromJson: false, includeToJson: false)
  int lastScorecardCount = 0;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime lastScoresCalculated = DateTime(0);
  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime? lastScoresBefore;
  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime? lastScoresAfter;
  @JsonKey(includeFromJson: false, includeToJson: false)
  MatchPredictionMode lastPredictionMode = MatchPredictionMode.none;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<MatchEntry, RelativeMatchScore> scores = {};
  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<MatchEntry, MatchScoreChange> scoreChanges = {};

  @JsonKey(includeFromJson: false, includeToJson: false)
  List<MatchEntry> displayedShooters = [];
}

/// Filters for a scorecard, either for scoring or display.
///
/// [filterSet] is standard Analyst match filters.
/// [entryIds] and [entryUuids] are used to filter down to specific
/// match entries. For PractiScore, entryUuids is preferred because
/// entryIds is unstable between full tablet syncs, apparently.
/// [topN] applies to display only, and limits the number of entries
/// shown on a scorecard.
@JsonSerializable()
class ScorecardFilters {
  FilterSet? filterSet;
  List<int>? entryIds;
  List<String>? entryUuids;
  int? topN;

  ScorecardFilters({
    this.filterSet,
    this.entryIds,
    this.entryUuids,
    this.topN,
  });

  ScorecardFilters copy() {
    return ScorecardFilters(
      filterSet: filterSet?.copy(),
      entryIds: entryIds?.toList(),
      entryUuids: entryUuids?.toList(),
      topN: topN,
    );
  }

  List<MatchEntry> apply(ShootingMatch match) {
    if(filterSet == null && entryIds == null) {
      return [];
    }

    List<MatchEntry> entries;
    if(filterSet != null) {
      entries = match.applyFilterSet(filterSet!);
    } else {
      entries = [...match.shooters];
    }

    if(entryIds != null) {
      entries.retainWhere((e) => entryIds!.contains(e.entryId));
    }

    if(entryUuids != null) {
      entries.retainWhere((e) => entryUuids!.contains(e.sourceId));
    }

    return entries;
  }

  bool get isEmpty => filterSet == null && entryIds == null && topN == null;

  factory ScorecardFilters.fromJson(Map<String, dynamic> json) => _$ScorecardFiltersFromJson(json);
  Map<String, dynamic> toJson() => _$ScorecardFiltersToJson(this);
}
