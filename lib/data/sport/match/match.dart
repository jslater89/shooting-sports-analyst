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
import 'package:shooting_sports_analyst/data/sport/scoring/stage_scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

/// A class that provides information about the match source used
/// to download or create a match.
abstract interface class SourceIdsProvider {
  String get sourceCode;
  List<String> get sourceIds;
}

class BareSourceIdsProvider implements SourceIdsProvider {
  String sourceCode;
  List<String> sourceIds;

  bool get hasSourceCode => sourceCode != "(n/a)";

  BareSourceIdsProvider({
    this.sourceCode = "(n/a)",
    required this.sourceIds,
  });
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

  /// A map of IDs to bonus scoring events local to this match, which
  /// are not part of the sport's default set of scoring events.
  ///
  /// The IDs are synthetic, and are not guaranteed to correspond to
  /// the ordering (if any) of match-local bonuses from a match source.
  ///
  /// In [RawScore] objects, these will be included in [targetEvents].
  List<ScoringEvent> localBonusEvents = [];

  /// A map of IDs to penalty scoring events local to this match, which
  /// are not part of the sport's default set of scoring events.
  ///
  /// The IDs are synthetic, and are not guaranteed to correspond to
  /// the ordering (if any) of match-local penalties from a match source.
  ///
  /// In [RawScore] objects, these will be included in [penaltyEvents].
  List<ScoringEvent> localPenaltyEvents = [];

  Set<int> squadNumbers = {};
  List<int> get sortedSquadNumbers => squadNumbers.toList()..sort();

  /// Whether a match is in progress for score display purposes.
  ///
  /// 6 days is as long as the longest matches in the US—staff Wed-Thu, main match
  /// Fri-Sun.
  bool get inProgress => DateTime.now().isBefore(date.add(Duration(days: 6)));

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
    this.localBonusEvents = const [],
    this.localPenaltyEvents = const [],
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

  MatchStage? lookupStageById(int stageId) {
    return stages.firstWhereOrNull((s) => s.stageId == stageId);
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
      sourceIds: [...sourceIds],
      level: level,
      databaseId: databaseId,
      shooters: [...shooters.map((s) => s.copy(stageCopies))],
      stages: [...stageCopies],
      localBonusEvents: [...localBonusEvents],
      localPenaltyEvents: [...localPenaltyEvents],
    );
  }
}

class MatchStage {
  /// A unique-per-match int identifier for this stage.
  ///
  /// Note that PractiScore does not enforce per-match uniqueness on this number.
  int stageId;

  /// The name of this stage.
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

  /// A map of scoring event names to their overrides for this stage.
  ///
  /// For instance, in ICORE, an X-ring hit might be a -1s bonus on one stage, but a -0.5s bonus
  /// on another. This map contains the data necessary for the scoring system to apply the correct
  /// value when scoring this stage.
  ///
  /// Scoring event overrides are only considered if the scoring event
  /// has [ScoringEvent.variesByStage] set to true.
  Map<String, ScoringEventOverride> scoringOverrides;

  /// A map of event names to a list of events of variable value for that event.
  ///
  /// This is only used in the event that a scoring event by a single name has multiple possible
  /// values on a stage. For instance, ICORE does not restrict X-ring hits to a single bonus value
  /// even within one stage, so in the event that a stage has more than one distinct value for X
  /// hits, this map will contain X: <list of differently-valued X events>.
  ///
  /// This matching is done by name, and will apply to all power factors equally—that is, multiple
  /// sets of different scoring values for different power factors for events with the same name
  /// on the same stage will not be supported. Please, please, please do not write any shooting
  /// sports rules that require this. The base event from the default power factor will be used
  /// when loading matches with variable events from the database.
  ///
  /// [variableEvents] is only considered if both [ScoringEvent.variableValue] is true for scoring
  /// events whose names are contained in the map, and [scoringOverrides] does not contain an
  /// override for the scoring event.
  ///
  /// This is a super-annoying feature to support, and [scoringOverrides] should be preferred when
  /// at all possible.
  Map<String, List<ScoringEvent>> variableEvents;

  /// A list of match-local bonuses that are available for this stage.
  List<ScoringEvent> availableMatchBonuses = [];

  /// A list of match-local penalties that are available for this stage.
  List<ScoringEvent> availableMatchPenalties = [];

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
    this.scoringOverrides = const {},
    this.variableEvents = const {},
    this.availableMatchBonuses = const [],
    this.availableMatchPenalties = const [],
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
      scoringOverrides: scoringOverrides,
      variableEvents: variableEvents,
      availableMatchBonuses: []..addAll(availableMatchBonuses),
      availableMatchPenalties: []..addAll(availableMatchPenalties),
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
