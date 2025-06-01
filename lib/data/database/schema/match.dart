/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/scoring_events.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match.g.dart';

SSALogger _log = SSALogger("DbShootingMatch");

/// An Isar DB ID for parent/child entities in different collections.
typedef ExternalId = int;

@collection
class DbShootingMatch with DbSportEntity implements SourceIdsProvider {
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
  /// The [AnalystDatabase] utility class will not allow matches without a source ID to be saved to
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

  List<DbScoringEvent> localBonusEvents;
  List<DbScoringEvent> localPenaltyEvents;

  @Index(name: AnalystDatabase.memberNumbersAppearingIndex, type: IndexType.value)
  /// A list of member numbers that appear in this match, for quick filtering by competitor.
  List<String> memberNumbersAppearing;

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
    required this.memberNumbersAppearing,
    required this.localBonusEvents,
    required this.localPenaltyEvents,
  });

  DbShootingMatch.dbPlaceholder(this.id) :
    eventName = "(invalid)",
    rawDate = "(invalid)",
    date = DateTime.now(),
    matchLevelName = "(invalid)",
    matchEventLevel = EventLevel.local,
    sportName = "(invalid)",
    sourceIds = [],
    sourceCode = "(invalid)",
    stages = [],
    shooters = [],
    memberNumbersAppearing = [],
    localBonusEvents = [],
    localPenaltyEvents = [];

  DbShootingMatch.sourcePlaceholder({
    required Sport sport,
    required this.sourceCode,
    required this.sourceIds,
  }) :
    id = Isar.autoIncrement,
    eventName = "(invalid)",
    rawDate = "(invalid)",
    date = DateTime.now(),
    matchLevelName = "(invalid)",
    matchEventLevel = EventLevel.local,
    sportName = sport.name,
    stages = [],
    shooters = [],
    memberNumbersAppearing = [],
    localBonusEvents = [],
    localPenaltyEvents = [];

  factory DbShootingMatch.from(ShootingMatch match) {
    Set<Division> divisionsAppearing = {};
    Set<String> memberNumbersAppearing = {};
    for(var shooter in match.shooters) {
      if(shooter.division != null) {
        divisionsAppearing.add(shooter.division!);
      }
      if(shooter.memberNumber.isNotEmpty) {
        memberNumbersAppearing.add(shooter.memberNumber);
      }
    }
    Map<MatchEntry, RelativeMatchScore> shooterScores = {};

    if(divisionsAppearing.length > 1) {
      // For each division, filter shooters and calculate match scores
      for(var division in divisionsAppearing) {
        var shooters = match.filterShooters(divisions: [division], filterMode: FilterMode.or);

        try {
          var scores = match.getScores(shooters: shooters);
          for(var entry in scores.entries) {
              shooterScores[entry.key] = entry.value;
          }
        }
        catch(e, stackTrace) {
          _log.e("Error getting scores for ${match.name} (${match.sourceCode}: ${match.sourceIds.first})", error: e, stackTrace: stackTrace);
          rethrow;
        }
      }
    }
    else {
      // No need to filter, just calculate overall scores
      var scores = match.getScores();
      for(var entry in scores.entries) {
        shooterScores[entry.key] = entry.value;
      }
    }

    List<DbMatchEntry> dbEntries = [];
    for(var entry in match.shooters) {
      var score = shooterScores[entry];
      if(score == null) {
        _log.w("shooter score for ${entry.firstName} ${entry.lastName} not found, leaving out");
      }
      dbEntries.add(DbMatchEntry.from(entry, score));
    }

    return DbShootingMatch(
      id: match.databaseId ?? Isar.autoIncrement,
      eventName: match.name,
      rawDate: match.rawDate,
      date: match.date,
      matchLevelName: match.level?.name,
      matchEventLevel: match.level?.eventLevel ?? EventLevel.local,
      sourceIds: []..addAll(match.sourceIds),
      sourceCode: match.sourceCode,
      sportName: match.sport.name,
      shooters: dbEntries,
      stages: []..addAll(match.stages.map((s) => DbMatchStage.from(s))),
      memberNumbersAppearing: memberNumbersAppearing.toList(),
      localBonusEvents: match.localBonusEvents.map((e) => DbScoringEvent.fromScoringEvent(e)).toList(),
      localPenaltyEvents: match.localPenaltyEvents.map((e) => DbScoringEvent.fromScoringEvent(e)).toList(),
    );
  }

  Result<ShootingMatch, ResultErr> hydrate({bool useCache = false}) {
    if(useCache) {
      var cached = HydratedMatchCache().get(this);
      if(cached.isOk()) return Result.ok(cached.unwrap());
    }

    var sport = SportRegistry().lookup(sportName);
    if(sport == null) {
      return Result.err(StringError("sport not found"));
    }

    MatchLevel? matchLevel = null;
    if(matchLevelName != null && sport.hasEventLevels) {
      matchLevel = sport.eventLevels.lookupByName(matchLevelName!);
    }

    List<ScoringEvent> localBonusEvents = this.localBonusEvents.map((e) => e.toScoringEvent()).toList();
    List<ScoringEvent> localPenaltyEvents = this.localPenaltyEvents.map((e) => e.toScoringEvent()).toList();

    List<MatchStage> hydratedStages = stages.map((s) => s.hydrate(sport)).toList();
    Map<int, MatchStage> stagesById = Map.fromEntries(hydratedStages.map((e) => MapEntry(e.stageId, e)));
    List<Result<MatchEntry, ResultErr>> hydratedShooters = shooters.map((s) =>
      s.hydrate(sport, stagesById, localBonusEvents, localPenaltyEvents)).toList();
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
      sourceCode: this.sourceCode,
      sourceIds: []..addAll(this.sourceIds),
      localBonusEvents: localBonusEvents,
      localPenaltyEvents: localPenaltyEvents,
    ));
  }

  static int Function(DbShootingMatch a, DbShootingMatch b) dateComparator = (a, b) {
    // Sort remaining matches by date descending, then by name ascending
    var dateSort = b.date.compareTo(a.date);
    if (dateSort != 0) return dateSort;

    return a.eventName.compareTo(b.eventName);
  };

  @override
  String toString() {
    return "$eventName ($id) (${sourceIds.firstOrNull})";
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
  String? sourceId;
  List<DbScoringEventOverride> scoringOverrides;
  List<DbScoringEventOverride> variableEvents;

  DbMatchStage({
    this.name = "(invalid name)",
    this.stageId = -1,
    this.minRounds = 0,
    this.maxPoints = 0,
    this.classifier = false,
    this.classifierNumber = "",
    this.scoringType = "(invalid)",
    this.sourceId,
    this.scoringOverrides = const [],
    this.variableEvents = const [],
  });

  DbMatchStage.from(MatchStage stage) :
    name = stage.name,
    stageId = stage.stageId,
    minRounds = stage.minRounds,
    maxPoints = stage.maxPoints,
    classifier = stage.classifier,
    classifierNumber = stage.classifierNumber,
    scoringType = stage.scoring.dbString,
    sourceId = stage.sourceId,
    scoringOverrides = stage.scoringOverrides.values.map((e) => DbScoringEventOverride.from(e.name, e)).toList(),
    variableEvents = stage.variableEvents.values.map((eventList) => eventList.map((e) => DbScoringEventOverride.fromVariableEvent(e.name, e)).toList()).flattened.toList();

  MatchStage hydrate(Sport sport) {
    Map<String, ScoringEventOverride> overrides = {};
    for(var override in scoringOverrides) {
      overrides[override.name] = override.hydrate();
    }
    Map<String, List<ScoringEvent>> varEventsMap = {};
    for(var override in variableEvents) {
      var actualEvent = sport.defaultPowerFactor.allEvents.lookupByName(override.name);
      if(actualEvent == null) {
        _log.w("base event not found for variable event ${override.name}, skipping");
      }
      else {
        varEventsMap.addToListIfMissing(override.name, actualEvent);
      }
    }
    var stageScoring = StageScoring.fromDbString(scoringType);
    return MatchStage(
      name: name,
      stageId: stageId,
      minRounds: minRounds,
      maxPoints: maxPoints,
      classifier: classifier,
      classifierNumber: classifierNumber,
      scoring: stageScoring,
      sourceId: sourceId,
      scoringOverrides: overrides,
      variableEvents: varEventsMap,
    );
  }

  @override
  String toString() {
    return "$stageId - $name";
  }
}

@embedded
class DbScoringEventOverride {
  String name;
  int? pointChangeOverride;
  double? timeChangeOverride;

  int get points => pointChangeOverride ?? 0;
  double get time => timeChangeOverride ?? 0;

  DbScoringEventOverride({
    this.name = "(invalid)",
    this.pointChangeOverride,
    this.timeChangeOverride,
  });

  DbScoringEventOverride.from(String name, ScoringEventOverride override) :
    name = name,
    pointChangeOverride = override.pointChangeOverride,
    timeChangeOverride = override.timeChangeOverride;

  DbScoringEventOverride.fromVariableEvent(String name, ScoringEvent event) :
    name = name,
    pointChangeOverride = event.pointChange,
    timeChangeOverride = event.timeChange {
      if(!event.variableValue) {
        throw ArgumentError("event $name is not a variable event");
      }
    }

  ScoringEventOverride hydrate() {
    return ScoringEventOverride(
      name: name,
      pointChangeOverride: pointChangeOverride,
      timeChangeOverride: timeChangeOverride,
    );
  }

  @override
  String toString() {
    return "$name (pts: $pointChangeOverride, time: $timeChangeOverride)";
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
  DbMatchScore? precalculatedScore;
  String? sourceId;

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
    this.precalculatedScore,
    this.sourceId,
  });

  factory DbMatchEntry.from(MatchEntry entry, RelativeMatchScore? score) {
    return DbMatchEntry(
      entryId: entry.entryId,
      firstName: entry.firstName,
      lastName: entry.lastName,
      memberNumber: entry.memberNumber,
      originalMemberNumber: entry.originalMemberNumber,
      knownMemberNumbers: entry.knownMemberNumbers.toList(),
      female: entry.female,
      dq: entry.dq,
      squad: entry.squad,
      reentry: entry.reentry,
      powerFactorName: entry.powerFactor.name,
      divisionName: entry.division?.name,
      classificationName: entry.classification?.name,
      ageCategoryName: entry.ageCategory?.name,
      scores: entry.scores.keys.map((stage) {
        return DbRawScore.from(stage.stageId, entry.scores[stage]!);
      }).toList(),
      precalculatedScore: DbMatchScore.from(score),
      sourceId: entry.sourceId,
    );
  }

  Result<MatchEntry, ResultErr> hydrate(Sport sport, Map<int, MatchStage> stagesById, List<ScoringEvent> localBonusEvents, List<ScoringEvent> localPenaltyEvents) {
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

    Map<MatchStage, Result<RawScore, ResultErr>> hydratedScores = Map.fromEntries(scores.map((dbScore) =>
      MapEntry(stagesById[dbScore.stageId]!, dbScore.hydrate(stagesById[dbScore.stageId]!, pf, localBonusEvents, localPenaltyEvents))));
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
      sourceId: sourceId,
    )
        ..originalMemberNumber = originalMemberNumber
        ..knownMemberNumbers = ({}..addAll(knownMemberNumbers))
    );
  }

  @override
  String toString() {
    return "$entryId - $firstName $lastName";
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
  DateTime? modified;

  DbRawScore({
    this.stageId = -1,
    this.scoringType = "(invalid)",
    this.rawTime = 0,
    this.scoringEvents = const [],
    this.penaltyEvents = const [],
    this.stringTimes = const [],
    this.modified,
  });

  DbRawScore.from(int stageId, RawScore score) :
    stageId = stageId,
    scoringType = score.scoring.dbString,
    rawTime = score.rawTime,
    stringTimes = []..addAll(score.stringTimes),
    scoringEvents = score.targetEvents.keys.map((event) {
      if(event.nondefaultPoints || event.nondefaultTime) {
        return DbScoringEventCount.fromNondefault(event, count: score.targetEvents[event]!);
      }
      return DbScoringEventCount(name: event.name, count: score.targetEvents[event]!);
    }).toList(),
    penaltyEvents = score.penaltyEvents.keys.map((event) {
      if(event.nondefaultPoints || event.nondefaultTime) {
        return DbScoringEventCount.fromNondefault(event, count: score.penaltyEvents[event]!);
      }
      return DbScoringEventCount(name: event.name, count: score.penaltyEvents[event]!);
    }).toList(),
    modified = score.modified;

  Result<RawScore, ResultErr> hydrate(MatchStage stage, PowerFactor pf, List<ScoringEvent> localBonusEvents, List<ScoringEvent> localPenaltyEvents) {
    return Result.ok(RawScore(
      scoring: StageScoring.fromDbString(scoringType),
      rawTime: rawTime,
      stringTimes: []..addAll(stringTimes),
      scoringOverrides: stage.scoringOverrides,
      targetEvents: Map.fromEntries(scoringEvents.map((event) {
        var targetEvent = pf.targetEvents.lookupByName(event.name);
        if(targetEvent == null) {
          if(localBonusEvents.lookupByName(event.name) != null) {
            targetEvent = localBonusEvents.lookupByName(event.name);
          }
          else if(localPenaltyEvents.lookupByName(event.name) != null) {
            targetEvent = localPenaltyEvents.lookupByName(event.name);
          }
        }
        if(targetEvent == null) {
          return Result.err(StringError("unknown target event ${event.name}"));
        }
        if(event.nondefaultValues) {
          var adHocEvent = targetEvent.copyWith(pointChange: event.pointsOverride, timeChange: event.timeOverride);
          return MapEntry(adHocEvent, event.count);
        }
        return MapEntry(targetEvent, event.count);
      }).whereType<MapEntry<ScoringEvent, int>>()),
      penaltyEvents: Map.fromEntries(penaltyEvents.map((event) {
        var targetEvent = pf.penaltyEvents.lookupByName(event.name);
        if(targetEvent == null) {
          if(localBonusEvents.lookupByName(event.name) != null) {
            targetEvent = localBonusEvents.lookupByName(event.name);
          }
          else if(localPenaltyEvents.lookupByName(event.name) != null) {
            targetEvent = localPenaltyEvents.lookupByName(event.name);
          }
        }
        if(targetEvent == null) {
          return Result.err(StringError("unknown penalty event ${event.name}"));
        }
        if(event.nondefaultValues) {
          var adHocEvent = targetEvent.copyWith(pointChange: event.pointsOverride, timeChange: event.timeOverride);
          return MapEntry(adHocEvent, event.count);
        }
        return MapEntry(targetEvent, event.count);
      }).whereType<MapEntry<ScoringEvent, int>>()),
      modified: modified,
    ));
  }

  @override
  String toString() {
    return "$stageId - $rawTime";
  }
}

@embedded
class DbScoringEventCount {
  String name;
  int count;
  int? pointsOverride;
  double? timeOverride;

  @ignore
  bool get nondefaultValues => pointsOverride != null || timeOverride != null;

  DbScoringEventCount({
    this.name = "(invalid)",
    this.count = -1,
  });

  DbScoringEventCount.fromNondefault(ScoringEvent event, {
    required this.count
  }) :
    name = event.name,
    pointsOverride = event.nondefaultPoints ? event.pointChange : null,
    timeOverride = event.nondefaultTime ? event.timeChange : null;

  @override
  String toString() {
    var overrideString = "";
    if(nondefaultValues) {
      overrideString = " (";
      List<String> overrides = [];
      if(pointsOverride != null) overrides.add("pts: $pointsOverride");
      if(timeOverride != null) overrides.add("time: $timeOverride");
      overrideString += overrides.join(", ");
      overrideString += ")";
    }
    return "$count $name ($overrideString)";
  }
}

@embedded
class DbMatchScore extends BareRelativeScore {
  /// The stage ID for this score, or -1 if this is a match score.
  DbMatchScore.empty() : stageScores = [], super(place: 0, ratio: 0, points: 0);
  DbMatchScore({super.place = 0, super.ratio = 0, super.points = 0, this.stageScores = const []});
  DbMatchScore.match({required super.place, required super.ratio, required super.points, required this.stageScores});

  factory DbMatchScore.from(RelativeMatchScore? score) {
    if(score == null) {
      return DbMatchScore.empty();
    }
    var stageScores = score.stageScores.keys.map((stage) => DbStageScore.from(stage, score.stageScores[stage]!)).toList();
    return DbMatchScore(
      place: score.place,
      ratio: score.ratio,
      points: score.points,
      stageScores: stageScores,
    );
  }

  List<DbStageScore> stageScores;
}

@embedded
class DbStageScore extends BareRelativeScore {
  int stageId;
  DbStageScore.empty() : stageId = -1, super(place: 0, ratio: 0, points: 0);
  DbStageScore({super.place = 0, super.ratio = 0, super.points = 0, this.stageId = -1});

  DbStageScore.from(MatchStage stage, RelativeStageScore score) :
    stageId = stage.stageId,
    super(place: score.place, ratio: score.ratio, points: score.points);
}
