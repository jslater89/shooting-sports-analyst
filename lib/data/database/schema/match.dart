/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match_database.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match.g.dart';

// Thinking: store various sport properties like PowerFactor etc. as

/// An Isar DB ID for parent/child entities in different collections.
typedef ExternalId = int;

@collection
class DbShootingMatch {
  Id id = Isar.autoIncrement;
  String eventName;

  @Index(name: AnalystDatabase.eventNameIndex, type: IndexType.value, caseSensitive: false)
  List<String> get eventNameParts => Isar.splitWords(eventName);

  String rawDate;

  @Index(name: AnalystDatabase.dateIndex)
  DateTime date;
  String? matchLevelName;

  /// A list of IDs this match is known by at its source.
  ///
  /// The [MatchDatabase] utility class will not allow matches without a source ID to be saved to
  /// the underlying database.
  ///
  /// See the note on [ShootingMatch.sourceIds] regarding collisions between matches from multiple
  /// The [MatchDatabase] utility class will not allow matches without a source ID to be saved to
  /// the underlying database.
  ///
  /// See the note on [ShootingMatch.sourceIds] regarding collisions between matches from multiple
  /// sources.
  @Index(name: AnalystDatabase.sourceIdsIndex, unique: true, replace: true, type: IndexType.value)
  List<String> sourceIds;

  /// The code of the match source for which sourceIds is valid.
  String sourceCode;

  @enumerated
  EventLevel matchEventLevel;
  String sportName;

  List<DbMatchStage> stages;
  List<DbMatchEntry> shooters;

  DbShootingMatch({
    this.id = Isar.autoIncrement,
    required this.eventName,
    required this.rawDate,
    required this.date,
    required this.matchLevelName,
    required this.matchEventLevel,
    required this.sportName,
    required this.sourceIds,
    required this.sourceCode,
    required this.stages,
    required this.shooters,
  });

  DbShootingMatch.from(ShootingMatch match) :
    id = match.databaseId ?? Isar.autoIncrement,
    eventName = match.name,
    rawDate = match.rawDate,
    date = match.date,
    matchLevelName = match.level?.name,
    matchEventLevel = match.level?.eventLevel ?? EventLevel.local,
    sourceIds = []..addAll(match.sourceIds),
    sourceCode = match.sourceCode,
    sportName = match.sport.name,
    shooters = []..addAll(match.shooters.map((s) => DbMatchEntry.from(s))),
    stages = []..addAll(match.stages.map((s) => DbMatchStage.from(s)));

  Result<ShootingMatch, ResultErr> hydrate() {
    var sport = SportRegistry().lookup(sportName);
    if(sport == null) {
      return Result.err(StringError("sport not found"));
    }

    MatchLevel? matchLevel = null;
    if(matchLevelName != null && sport.hasEventLevels) {
      matchLevel = sport.eventLevels.lookupByName(matchLevelName!);
    }

    List<MatchStage> hydratedStages = stages.map((s) => s.hydrate()).toList();
    Map<int, MatchStage> stagesById = Map.fromEntries(hydratedStages.map((e) => MapEntry(e.stageId, e)));
    List<Result<MatchEntry, ResultErr>> hydratedShooters = shooters.map((s) => s.hydrate(sport, stagesById)).toList();
    var firstError = hydratedShooters.firstWhereOrNull((e) => e.isErr());
    if(firstError != null) return Result.err(firstError.unwrapErr());

    return Result.ok(ShootingMatch(
      databaseId: this.id,
      name: this.eventName,
      rawDate: this.rawDate,
      date: this.date,
      stages: hydratedStages,
      sport: sport,
      shooters: hydratedShooters.map((e) => e.unwrap()).toList(),
      level: matchLevel,
      sourceIds: []..addAll(this.sourceIds),
    ));
  }
}

@embedded
class DbMatchStage {
  int stageId;
  String name;
  int minRounds;
  int maxPoints;
  bool classifier;
  String classifierNumber;
  String scoringType;

  DbMatchStage({
    this.name = "(invalid name)",
    this.stageId = -1,
    this.minRounds = 0,
    this.maxPoints = 0,
    this.classifier = false,
    this.classifierNumber = "",
    this.scoringType = "(invalid)",
  });

  DbMatchStage.from(MatchStage stage) :
    name = stage.name,
    stageId = stage.stageId,
    minRounds = stage.minRounds,
    maxPoints = stage.maxPoints,
    classifier = stage.classifier,
    classifierNumber = stage.classifierNumber,
    scoringType = stage.scoring.dbString;

  MatchStage hydrate() {
    return MatchStage(
      name: name,
      stageId: stageId,
      minRounds: minRounds,
      maxPoints: maxPoints,
      classifier: classifier,
      classifierNumber: classifierNumber,
      scoring: StageScoring.fromDbString(scoringType),
    );
  }
}

@embedded
class DbMatchEntry {
  int entryId;
  String firstName;
  String lastName;
  String memberNumber;
  String originalMemberNumber;
  List<String> knownMemberNumbers;
  bool female;
  bool reentry;
  bool dq;
  int? squad;
  String powerFactorName;
  String? divisionName;
  String? classificationName;
  String? ageCategoryName;
  List<DbRawScore> scores;

  DbMatchEntry({
    this.entryId = -1,
    this.firstName = "(invalid)",
    this.lastName = "(invalid)",
    this.memberNumber = "(invalid)",
    this.originalMemberNumber = "(invalid)",
    this.knownMemberNumbers = const [],
    this.female = false,
    this.dq = false,
    this.reentry = false,
    this.powerFactorName = "(invalid)",
    this.divisionName,
    this.classificationName,
    this.ageCategoryName,
    this.squad,
    this.scores = const [],
  });

  DbMatchEntry.from(MatchEntry entry) :
    entryId = entry.entryId,
    firstName = entry.firstName,
    lastName = entry.lastName,
    memberNumber = entry.memberNumber,
    originalMemberNumber = entry.originalMemberNumber,
    knownMemberNumbers = entry.knownMemberNumbers.toList(),
    female = entry.female,
    dq = entry.dq,
    squad = entry.squad,
    reentry = entry.reentry,
    powerFactorName = entry.powerFactor.name,
    divisionName = entry.division?.name,
    classificationName = entry.classification?.name,
    scores = entry.scores.keys.map((stage) {
      return DbRawScore.from(stage.stageId, entry.scores[stage]!);
    }).toList();

  Result<MatchEntry, ResultErr> hydrate(Sport sport, Map<int, MatchStage> stagesById) {
    Division? division = null;
    if(sport.hasDivisions) {
      if(divisionName == null && !sport.hasDivisionFallback) return Result.err(StringError("bad division: $firstName $lastName $divisionName"));

      division = sport.divisions.lookupByName(divisionName ?? "no division");
      if(division == null) return Result.err(StringError("bad division: $firstName $lastName $divisionName"));
    }

    Classification? classification = null;
    if(sport.hasClassifications) {
      if(classificationName == null && !sport.hasClassificationFallback) return Result.err(StringError("bad classification: $firstName $lastName $classificationName"));

      classification = sport.classifications.lookupByName(classificationName ?? "no classification");
      if(division == null) return Result.err(StringError("bad classification: $firstName $lastName $classificationName"));
    }

    AgeCategory? category;
    if(sport.hasAgeCategories) {
      if(ageCategoryName != null) {
        category = sport.ageCategories.lookupByName(ageCategoryName!);
      }
    }

    PowerFactor pf = sport.powerFactors.values.first;
    if(sport.hasPowerFactors) {
      var foundPf = sport.powerFactors.lookupByName(powerFactorName);
      if(foundPf == null) return Result.err(StringError("bad power factor: $firstName $lastName $powerFactorName"));
      pf = foundPf;
    }

    Map<MatchStage, Result<RawScore, ResultErr>> hydratedScores = Map.fromEntries(scores.map((dbScore) => MapEntry(stagesById[dbScore.stageId]!, dbScore.hydrate(pf))));
    var firstError = hydratedScores.values.firstWhereOrNull((element) => element.isErr());
    if(firstError != null) return Result.err(firstError.unwrapErr());

    return Result.ok(MatchEntry(
      entryId: entryId,
      firstName: firstName,
      lastName: lastName,
      memberNumber: memberNumber,
      female: female,
      dq: dq,
      squad: squad,
      reentry: reentry,
      powerFactor: pf,
      division: division,
      classification: classification,
      ageCategory: category,
      scores: hydratedScores.map((stage, result) => MapEntry(stage, result.unwrap())),
    )
        ..originalMemberNumber = originalMemberNumber
        ..knownMemberNumbers = ({}..addAll(knownMemberNumbers))
    );
  }
}

@embedded
class DbRawScore {
  String scoringType;
  int stageId;
  double rawTime;
  List<DbScoringEventCount> scoringEvents;
  List<DbScoringEventCount> penaltyEvents;
  List<double> stringTimes;

  DbRawScore({
    this.stageId = -1,
    this.scoringType = "(invalid)",
    this.rawTime = 0,
    this.scoringEvents = const [],
    this.penaltyEvents = const [],
    this.stringTimes = const [],
  });

  DbRawScore.from(int stageId, RawScore score) :
    stageId = stageId,
    scoringType = score.scoring.dbString,
    rawTime = score.rawTime,
    stringTimes = []..addAll(score.stringTimes),
    scoringEvents = score.targetEvents.keys.map((event) => DbScoringEventCount(name: event.name, count: score.targetEvents[event]!)).toList(),
    penaltyEvents = score.penaltyEvents.keys.map((event) => DbScoringEventCount(name: event.name, count: score.penaltyEvents[event]!)).toList();

  Result<RawScore, ResultErr> hydrate(PowerFactor pf) {
    for(var event in scoringEvents) {
      if(pf.targetEvents.lookupByName(event.name) == null) return Result.err(StringError("invalid scoring event ${event.name}"));
    }
    for(var event in penaltyEvents) {
      if(pf.penaltyEvents.lookupByName(event.name) == null) return Result.err(StringError("invalid penalty event ${event.name}"));
    }

    return Result.ok(RawScore(
      scoring: StageScoring.fromDbString(scoringType),
      rawTime: rawTime,
      stringTimes: []..addAll(stringTimes),
      targetEvents: Map.fromEntries(scoringEvents.map((event) => MapEntry(pf.targetEvents.lookupByName(event.name)!, event.count))),
      penaltyEvents: Map.fromEntries(penaltyEvents.map((event) => MapEntry(pf.penaltyEvents.lookupByName(event.name)!, event.count))),
    ));
  }
}

@embedded
class DbScoringEventCount {
  String name;
  int count;

  DbScoringEventCount({
    this.name = "(invalid)",
    this.count = -1,
  });
}