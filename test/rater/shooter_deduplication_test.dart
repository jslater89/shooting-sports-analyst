import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:uuid/uuid.dart';

void main() async {
  var db = AnalystDatabase.test();

  setUpAll(() async {
    print("Setting up test data");
    await setupTestDb(db);
  });

  // #region Tests

  test("DataEntryFix similar numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Test Project",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-similar-numbers");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", results[0].proposedActions.first, isA<DataEntryFix>());
    var fix = results[0].proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A123457"));
  });

  test("DataEntryFix dissimilar numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Test Project 2",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "data-entry-fix-dissimilar-numbers");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", results[0].proposedActions.first, isA<Blacklist>());
    var fix = results[0].proposedActions.first as Blacklist;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A76691"));
  });

  test("AutoMapping A->L", () async {
    var project = DbRatingProject(
      name: "AutoMapping A->L",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "auto-mapping-a-l");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("L1234"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456"]));
  });

  test("AutoMapping A->RD", () async {
    var project = DbRatingProject(
      name: "AutoMapping A->L",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "auto-mapping-a-rd");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("RD12"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["A123456", "L1234", "B123"]));
  });

  test("AutoMapping L->RD", () async {
    var project = DbRatingProject(
      name: "AutoMapping L->RD",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "auto-mapping-l-rd");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var fix = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", fix.targetNumber, equals("RD12"));
    expect(reason: "source numbers", fix.sourceNumbers, unorderedEquals(["L1234"]));
  });
  
  test("AmbiguousMapping Resolvable", () async {
    var project = DbRatingProject(
      name: "AmbiguousMapping Resolvable",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "ambiguous-mapping-resolvable");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var multipleNumbersCause = results[0].causes.firstWhereOrNull((e) => e is MultipleNumbersOfType) as MultipleNumbersOfType;
    var ambiguousMappingCause = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "has multiple numbers cause", multipleNumbersCause, isNotNull);
    expect(reason: "has ambiguous mapping cause", ambiguousMappingCause, isNotNull);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    var dataEntryFix = results[0].proposedActions.firstWhereOrNull((e) => e is DataEntryFix) as DataEntryFix;
    var autoMapping = results[0].proposedActions.firstWhereOrNull((e) => e is AutoMapping) as AutoMapping;
    expect(reason: "has data entry fix", dataEntryFix, isNotNull);
    expect(reason: "has auto mapping", autoMapping, isNotNull);
    expect(reason: "data entry fix source number", dataEntryFix.sourceNumber, equals("A123457"));
    expect(reason: "data entry fix target number", dataEntryFix.targetNumber, equals("A123456"));
    expect(reason: "auto mapping target number", autoMapping.targetNumber, equals("L1234"));
    expect(reason: "auto mapping source numbers", autoMapping.sourceNumbers, unorderedEquals(["A123456"]));
  });
  
  test("AmbiguousMapping Unresolvable", () async {
    var project = DbRatingProject(
      name: "AmbiguousMapping Unresolvable",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "ambiguous-mapping-unresolvable");
    var deduplicator = USPSADeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(2));
    var multipleNumbersCause = results[0].causes.firstWhereOrNull((e) => e is MultipleNumbersOfType) as MultipleNumbersOfType;
    var ambiguousMappingCause = results[0].causes.firstWhereOrNull((e) => e is AmbiguousMapping) as AmbiguousMapping;
    expect(reason: "has multiple numbers cause", multipleNumbersCause, isNotNull);
    expect(reason: "has ambiguous mapping cause", ambiguousMappingCause, isNotNull);
    expect(reason: "ambiguous mapping indicates source conflicts", ambiguousMappingCause.sourceConflicts, isTrue);
    expect(reason: "ambiguous mapping does not indicate target conflicts", ambiguousMappingCause.targetConflicts, isFalse);
    expect(reason: "ambiguous mapping has correct source numbers", ambiguousMappingCause.sourceNumbers, unorderedEquals(["A123456", "A76691"]));
    expect(reason: "ambiguous mapping has correct target numbers", ambiguousMappingCause.targetNumbers, unorderedEquals(["L1234"]));
    expect(reason: "ambiguous mapping has correct conflicting types", ambiguousMappingCause.conflictingTypes, unorderedEquals([MemberNumberType.standard]));
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    var blacklist = results[0].proposedActions.firstWhereOrNull((e) => e is Blacklist) as Blacklist;
    expect(reason: "has blacklist", blacklist, isNotNull);
    var n1 = blacklist.sourceNumber;
    var n2 = blacklist.targetNumber;
    expect(reason: "blacklist numbers", [n1, n2], unorderedEquals(["A123456", "A76691"]));
  });
  // #endregion
}

Future<List<DbShooterRating>> addMatchToTest(AnalystDatabase db, DbRatingProject project, String matchId) async {
  var dbMatch = await db.getMatchByAnySourceId([matchId]);
  project.matches.add(dbMatch!);

  await db.saveRatingProject(project);
  var match = dbMatch.hydrate().unwrap();

  List<DbShooterRating> newRatings = [];
  for(var competitor in match.shooters) {
    var r = DbShooterRating(
      sportName: uspsaSport.name,
      firstName: competitor.firstName,
      lastName: competitor.lastName,
      rating: 1000,
      memberNumber: competitor.memberNumber,
      female: competitor.female,
      error: 0,
      connectedness: 0,
      firstSeen: match.date,
      lastSeen: match.date,
    );
    r.copyVitalsFrom(competitor);
    newRatings.add(r);
  }

  return newRatings;
}


Future<void> setupTestDb(AnalystDatabase db) async {
  db.isar.writeTxn(() async {
    await db.isar.clear();
  });

  var competitorMap = generateCompetitors();

  var simpleDataEntryMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A123457"]!],
    date: DateTime(2024, 1, 1),
    matchName: "Simple DataEntryFix",
    matchId: "data-entry-fix-similar-numbers",
  );

  var simpleBlacklistMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A76691"]!],
    date: DateTime(2024, 1, 7),
    matchName: "Simple Blacklist",
    matchId: "data-entry-fix-dissimilar-numbers",
  );

  var simpleAutoMappingMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 1, 14),
    matchName: "Simple AutoMapping A->L",
    matchId: "auto-mapping-a-l",
  );

  var simpleAutoMappingMatch2 = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["L1234"]!, competitorMap["B123"]!, competitorMap["RD12"]!],
    date: DateTime(2024, 1, 21),
    matchName: "Simple AutoMapping A->RD",
    matchId: "auto-mapping-a-rd",
  );

  var simpleAutoMappingMatch3 = generateMatch(
    shooters: [competitorMap["L1234"]!, competitorMap["RD12"]!],
    date: DateTime(2024, 1, 28),
    matchName: "Simple AutoMapping L->RD",
    matchId: "auto-mapping-l-rd",
  );

  var simpleAmbiguousMappingMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A123457"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 2, 4),
    matchName: "AmbiguousMapping Resolvable",
    matchId: "ambiguous-mapping-resolvable",
  );

  var simpleAmbiguousMappingUnresolvableMatch = generateMatch(
    shooters: [competitorMap["A123456"]!, competitorMap["A76691"]!, competitorMap["L1234"]!],
    date: DateTime(2024, 2, 4),
    matchName: "AmbiguousMapping Unresolvable",
    matchId: "ambiguous-mapping-unresolvable",
  );

  var futures = [
    db.saveMatch(simpleDataEntryMatch),
    db.saveMatch(simpleBlacklistMatch),
    db.saveMatch(simpleAutoMappingMatch),
    db.saveMatch(simpleAutoMappingMatch2),
    db.saveMatch(simpleAutoMappingMatch3),
    db.saveMatch(simpleAmbiguousMappingMatch),
    db.saveMatch(simpleAmbiguousMappingUnresolvableMatch),
  ];
  await Future.wait(futures);
}

/// Generates a list of competitors useful for deduplication testing.
Map<String, Shooter> generateCompetitors() {
  Map<String, Shooter> competitors = {};

  // John Deduplicator, first through fifth of his name
  competitors["A123456"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "A123456",
  );
  competitors["A123457"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "A123457",
  );
  competitors["L1234"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "L1234",
  );
  competitors["B123"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "B123",
  );
  competitors["RD12"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "RD12",
  );

  /// An unrelated John Deduplicator
  competitors["A76691"] = Shooter(
    firstName: "John",
    lastName: "Deduplicator",
    memberNumber: "A76691",
  );

  competitors["A124456"] = Shooter(
    firstName: "Vaughn",
    lastName: "Deduplicator",
    memberNumber: "A124456",
  );

  return competitors;
}

ShootingMatch generateMatch({required List<Shooter> shooters, int stageCount = 5, String matchName = "Test Match", required DateTime date, String? matchId}) {
  var r = Random();
  var stages = List.generate(stageCount, (index) {
    int roundCount = r.nextInt(20) + 12;
    return MatchStage(
      stageId: index + 1, name: "Stage ${index + 1}", scoring: HitFactorScoring(),
      minRounds: roundCount, maxPoints: roundCount * 5,
    );
  });

  var entries = List.generate(shooters.length, (index) {
    var shooter = shooters[index];

    Map<MatchStage, RawScore> scores = {};

    for(var stage in stages) {
      Map<ScoringEvent, int> hitCounts = {};
      for(int i = 0; i < stage.minRounds; i++) {
        int hitDie = r.nextInt(100);
        if(hitDie > 10) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("A")!);
        }
        else if(hitDie > 5) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("C")!);
        }
        else if(hitDie > 3) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("D")!);
        }
        else if(hitDie > 0) {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("M")!);
        }
        else {
          hitCounts.increment(uspsaMinorPF.targetEvents.lookupByName("NS")!);
        }
      }

      // Time is between 0.4 and 0.6 times the number of rounds.
      var time = stage.minRounds * 0.5 * (1 - ((r.nextDouble() - 0.5) * 0.2));

      scores[stage] = RawScore(
        scoring: stage.scoring,
        targetEvents: hitCounts,
        rawTime: time,
      );
    }

    var entry = MatchEntry(
      entryId: index,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      powerFactor: uspsaMinorPF,
      scores: scores,
    );

    entry.copyVitalsFrom(shooter);

    return entry;
  });

  var match = ShootingMatch(
    stages: stages,
    name: matchName,
    rawDate: date.toIso8601String(),
    date: date,
    sport: uspsaSport,
    shooters: entries,
    sourceIds: [matchId ?? Uuid().v4()],
    sourceCode: "test-autogen",
  );

  return match;
}