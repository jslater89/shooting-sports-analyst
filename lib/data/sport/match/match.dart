/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart' as oldschema;
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/sport/match/translator.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

enum FilterMode {
  or, and,
}

/// A match in some shooting event.
class ShootingMatch {
  /// The identifier corresponding to this match in the local database.
  int? databaseId;

  /// The identifier or identifiers corresponding to this match in the
  /// source it came from.
  List<String> sourceIds;

  String eventName;
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

  bool get inProgress => false;
  int get maxPoints => stages.map((s) => s.maxPoints).sum;

  ShootingMatch({
    this.databaseId,
    this.sourceIds = const [],
    required this.eventName,
    required this.rawDate,
    required this.date,
    this.level,
    required this.sport,
    required this.stages,
    required this.shooters,
  });

  factory ShootingMatch.fromOldMatch(oldschema.PracticalMatch match) {
    return MatchTranslator.shootingMatchFrom(match);
  }

  Map<MatchEntry, RelativeMatchScore> getScores({
    List<MatchEntry>? shooters,
    List<MatchStage>? stages,
    bool scoreDQ = true,
    MatchPredictionMode predictionMode = MatchPredictionMode.none,
    Map<RaterGroup, Rater>? ratings,
  }) {
    var innerShooters = shooters ?? this.shooters;
    var innerStages = stages ?? this.stages;

    return sport.matchScoring.calculateMatchScores(
      shooters: innerShooters,
      stages: innerStages,
      scoreDQ: scoreDQ,
      predictionMode: predictionMode
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
    bool ladyOnly = false,
  }) {
    List<MatchEntry> filteredShooters = [];

    if(divisions == null) divisions = sport.divisions.values.toList();
    if(powerFactors == null) powerFactors = sport.powerFactors.values.toList();
    if(classes == null) classes = sport.classifications.values.toList();

    for(MatchEntry s in shooters) {
      if(filterMode == FilterMode.or) {
        if ((!sport.hasDivisions || divisions.contains(s.division)) || powerFactors.contains(s.powerFactor) || (!sport.hasClassifications || classes.contains(s.classification))) {
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

    return filteredShooters;
  }

  @override
  String toString() {
    return eventName;
  }

  static int Function(ShootingMatch a, ShootingMatch b) dateComparator = (a, b) {
    // Sort remaining matches by date descending, then by name ascending
    var dateSort = b.date.compareTo(a.date);
    if (dateSort != 0) return dateSort;

    return a.eventName.compareTo(b.eventName);
  };

  ShootingMatch copy() {
    var stageCopies = <MatchStage>[]..addAll(stages.map((s) => s.copy()));
    return ShootingMatch(
      eventName: eventName,
      sport: sport,
      rawDate: rawDate,
      date: date,
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

  MatchStage({
    required this.stageId,
    required this.name,
    required this.scoring,
    this.minRounds = 0,
    this.maxPoints = 0,
    this.classifier = false,
    this.classifierNumber = "",
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