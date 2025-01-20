/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart' as oldschema;
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/match/translator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

abstract interface class SourceIdsProvider {
  List<String> get sourceIds;
}

enum FilterMode {
  or, and,
}



/// A match in some shooting event.
class ShootingMatch implements SourceIdsProvider {
  /// The identifier corresponding to this match in the local database.
  int? databaseId;

  /// The identifier or identifiers corresponding to this match in the
  /// source it came from.
  ///
  /// If match IDs are likely to overlap with IDs from other sources, and those IDs
  /// do not point to the same match (if, e.g., two sources identify matches with
  /// an incrementing integer ID), source IDs should be prefixed with sourceCode
  /// to prevent database collisions.
  ///
  /// This is not necessary if a match source identifies matches by collision-resistant
  /// IDs like UUID.
  List<String> sourceIds;

  /// The name of the source this match came from.
  String sourceCode;

  String name;
  String rawDate;
  DateTime date;
  MatchLevel? level;

  /// The sport whose rules govern this match.
  Sport sport;

  /// Stages in this match. For sports without stages,
  /// this will contain one pseudo-stage that includes
  /// the match scores.
  List<MatchStage> stages;

  /// Shooters in this match.
  List<MatchEntry> shooters;

  Set<int> squadNumbers = {};
  List<int> get sortedSquadNumbers => squadNumbers.toList()..sort();

  /// Whether a match is in progress for score display purposes.
  bool get inProgress => DateTime.now().isBefore(date.add(Duration(days: 7)));
  int get maxPoints => stages.map((s) => s.maxPoints).sum;

  ShootingMatch({
    this.databaseId,
    this.sourceIds = const [],
    this.sourceCode = "",
    required this.name,
    required this.rawDate,
    required this.date,
    this.level,
    required this.sport,
    required this.stages,
    required this.shooters,
  }) {
    updateSquadNumbers();
  }

  void updateSquadNumbers() {
    squadNumbers.clear();
    for(MatchEntry s in shooters) {
      if(s.squad != null) {
        squadNumbers.add(s.squad!);
      }
    }
  }

  factory ShootingMatch.fromOldMatch(oldschema.PracticalMatch match) {
    var newMatch = MatchTranslator.shootingMatchFrom(match);
    newMatch.updateSquadNumbers();
    return newMatch;
  }

  /// Calculate scores for shooters in this match, according to a provided FilterSet.
  ///
  /// If [shooterUuids] or [shooterIds] are provided, they will be applied after
  /// the FilterSet.
  Map<MatchEntry, RelativeMatchScore> getScoresFromFilters(FilterSet filters, {
    List<String>? shooterUuids,
    List<int>? shooterIds,
    List<MatchStage>? stages,
    DateTime? scoresAfter,
    DateTime? scoresBefore,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    PreloadedRatingDataSource? ratings,
  }) {
    var innerShooters = applyFilterSet(filters);
    if(shooterUuids != null) {
      innerShooters.retainWhere((s) => shooterUuids.contains(s.sourceId));
    }
    if(shooterIds != null) {
      innerShooters.retainWhere((s) => shooterIds.contains(s.entryId));
    }

    return getScores(
      shooters: innerShooters,
      stages: stages,
      scoreDQ: filters.scoreDQs,
      predictionMode: predictionMode,
      ratings: ratings,
      scoresAfter: scoresAfter,
      scoresBefore: scoresBefore,
    );
  }

  /// Calculate scores for shooters in this match.
  /// 
  /// [shooters] and [stages] default to all shooters and stages in this match.
  /// 
  /// [scoreDQ] calculates partial scores for shooters who have been disqualified.
  /// 
  /// [predictionMode], if not [MatchPredictionMode.none], assigns predicted scores
  /// to shooters on stages they have not yet completed.
  /// 
  /// [ratings] supports rating-based [predictionMode]s.
  /// 
  /// [scoresAfter] and [scoresBefore], if used, will drop scores that occur
  /// before [scoresAfter] and after [scoresBefore].
  Map<MatchEntry, RelativeMatchScore> getScores({
    List<MatchEntry>? shooters,
    List<MatchStage>? stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    PreloadedRatingDataSource? ratings,
    /// Include only scores occurring after this time.
    DateTime? scoresAfter,
    /// Include only scores occurring before this time.
    DateTime? scoresBefore,
  }) {
    var innerShooters = shooters ?? this.shooters;
    var innerStages = stages ?? this.stages;

    return sport.matchScoring.calculateMatchScores(
      match: this,
      shooters: innerShooters,
      stages: innerStages,
      scoreDQ: scoreDQ,
      predictionMode: predictionMode,
      ratings: ratings,
      scoresAfter: scoresAfter,
      scoresBefore: scoresBefore,
    );
  }

  /// Look up a stage by name.
  ///
  /// (This looks useless, but is used for finding the stage represented
  /// by a dropdown in an editable/copied match.)
  MatchStage? lookupStage(MatchStage stage) {
    return lookupStageByName(stage.name);
  }

  MatchStage? lookupStageByName(String? stage) {
    if(stage == null) return null;

    for(MatchStage s in stages) {
      if(stage == s.name) return s;
    }

    return null;
  }

  List<MatchEntry> applyFilterSet(FilterSet filters) {
    return filterShooters(
      filterMode: filters.mode,
      divisions: filters.activeDivisions.toList(),
      powerFactors: filters.activePowerFactors.toList(),
      classes: filters.activeClassifications.toList(),
      squads: filters.squads,
      ladyOnly: filters.femaleOnly,
      ageCategories: filters.activeAgeCategories.toList(),
    );
  }

  /// Filters shooters by division, power factor, and classification.
  ///
  /// By default, uses [FilterMode.and], and allows all values. To filter
  /// by e.g. division alone, set [divisions] to the desired division(s).
  List<MatchEntry> filterShooters({
    FilterMode? filterMode,
    bool allowReentries = true,
    List<Division>? divisions,
    List<PowerFactor>? powerFactors,
    List<Classification>? classes,
    List<int>? squads,
    bool ladyOnly = false,
    List<AgeCategory>? ageCategories,
  }) {
    List<MatchEntry> filteredShooters = [];

    if(divisions == null) divisions = sport.divisions.values.toList();
    if(powerFactors == null) powerFactors = sport.powerFactors.values.toList();
    if(classes == null) classes = sport.classifications.values.toList();

    for(MatchEntry s in shooters) {
      if(filterMode == FilterMode.or) {
        if (
            (!sport.hasDivisions || divisions.contains(s.division))
                || powerFactors.contains(s.powerFactor)
                || (!sport.hasClassifications || classes.contains(s.classification))
        ) {
          if(allowReentries || !s.reentry) filteredShooters.add(s);
        }
      }
      else {
        if ((!sport.hasDivisions || divisions.contains(s.division)) && powerFactors.contains(s.powerFactor) && (!sport.hasClassifications || classes.contains(s.classification))) {
          if(allowReentries || !s.reentry) filteredShooters.add(s);
        }
      }
    }

    if(ladyOnly) {
      filteredShooters.retainWhere((s) => s.female);
    }

    if(ageCategories != null && ageCategories.isNotEmpty) {
      filteredShooters.retainWhere((s) => ageCategories.contains(s.ageCategory));
    }

    if(squads != null && squads.isNotEmpty) {
      filteredShooters.retainWhere((s) => squads.contains(s.squad));
    }

    return filteredShooters;
  }

  @override
  String toString() {
    return name;
  }

  static int Function(ShootingMatch a, ShootingMatch b) dateComparator = (a, b) {
    // Sort remaining matches by date descending, then by name ascending
    var dateSort = b.date.compareTo(a.date);
    if (dateSort != 0) return dateSort;

    return a.name.compareTo(b.name);
  };

  ShootingMatch copy() {
    var stageCopies = <MatchStage>[]..addAll(stages.map((s) => s.copy()));
    return ShootingMatch(
      name: name,
      sport: sport,
      rawDate: rawDate,
      date: date,
      sourceCode: sourceCode,
      sourceIds: []..addAll(sourceIds),
      level: level,
      databaseId: databaseId,
      shooters: []..addAll(shooters.map((s) => s.copy(stageCopies))),
      stages: []..addAll(stageCopies),
    );
  }
}

class MatchStage {
  int stageId;
  String name;

  /// The minimum number of scoring events required to
  /// complete this stage. In USPSA, for instance, this is
  /// the minimum number of rounds required to complete the stage:
  /// every shot will either be a hit, a miss, or a no-penalty miss.
  ///
  /// If it cannot be determined, or this is not a valid concept in the
  /// sport, use '0'. IDPA or ICORE parsed from Practiscore HTML, for example,
  /// would use '0', because we don't have stage information beyond raw time,
  /// points down, and penalties.
  ///
  /// In e.g. sporting clays, the minimum number of scoring events, if
  /// the scoring event is '1 bird', is 0.
  int minRounds;

  /// The maximum number of points available on this stage, or 0
  /// if 'maximum points' is not a valid concept in the sport.
  int maxPoints;

  bool classifier;
  String classifierNumber;
  StageScoring scoring;

  /// An optional source-specific identifier for this stage.
  String? sourceId;

  MatchStage({
    required this.stageId,
    required this.name,
    required this.scoring,
    this.minRounds = 0,
    this.maxPoints = 0,
    this.classifier = false,
    this.classifierNumber = "",
    this.sourceId,
  });

  MatchStage copy() {
    return MatchStage(
      stageId: stageId,
      name: name,
      scoring: scoring,
      minRounds: minRounds,
      maxPoints: maxPoints,
      classifier: classifier,
      classifierNumber: classifierNumber,
    );
  }

  @override
  String toString() {
    return "$name ($stageId)";
  }
}

extension SourceIdsMatch on List<String> {
  bool containsAny(List<String> other) => this.any(other.contains);
}