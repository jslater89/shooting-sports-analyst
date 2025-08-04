/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/typo_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:uuid/uuid.dart';

void main() async {
  var db = AnalystDatabase.test();
  var ratingGroup = idpaSport.builtinRatingGroupsProvider!.builtinRatingGroups.first;

  setUp(() async {
    await setupTestDb(db);
  });

  tearDown(() async {
    await db.isar.writeTxn(() async {
      await db.isar.clear();
    });
  });

  test("Typo Fix", () async {
    var project = DbRatingProject(
      name: "Typo Fix",
      sportName: idpaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "typo-fix");
    var deduplicator = idpaSport.shooterDeduplicator!;
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var dedup = results[0];
    expect(reason: "number of causes", dedup.causes, hasLength(1));
    expect(reason: "cause is MultipleNumbersOfType", dedup.causes.first, isA<MultipleNumbersOfType>());
    expect(reason: "number of proposed actions", dedup.proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", dedup.proposedActions.first, isA<DataEntryFix>());
    var fix = dedup.proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix.targetNumber, equals("A1002675"));
    expect(reason: "source number", fix.sourceNumber, equals("A1002676"));
  });

  test("Typo Blacklist", () async {
    var project = DbRatingProject(
      name: "Typo Blacklist",
      sportName: idpaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "typo-blacklist");
    var deduplicator = idpaSport.shooterDeduplicator!;
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var dedup = results[0];
    expect(reason: "number of causes", dedup.causes, hasLength(1));
    expect(reason: "cause is MultipleNumbersOfType", dedup.causes.first, isA<MultipleNumbersOfType>());
    expect(reason: "number of proposed actions", dedup.proposedActions, hasLength(1));
    expect(reason: "proposed action is Blacklist", dedup.proposedActions.first, isA<Blacklist>());
    var blacklist = dedup.proposedActions.first as Blacklist;
    expect(reason: "target number", blacklist.targetNumber, equals("A864200"));
    expect(reason: "source number", blacklist.sourceNumber, equals("A1002675"));
  });

  test("Typo Invalid Number Fix", () async {
    var project = DbRatingProject(
      name: "Typo Invalid Number Fix",
      sportName: idpaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "typo-invalid-number");
    var deduplicator = idpaSport.shooterDeduplicator!;
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    var dedup = results[0];
    expect(reason: "number of causes", dedup.causes, hasLength(1));
    expect(reason: "cause is MultipleNumbersOfType", dedup.causes.first, isA<MultipleNumbersOfType>());
    expect(reason: "number of proposed actions", dedup.proposedActions, hasLength(1));
    expect(reason: "proposed action is DataEntryFix", dedup.proposedActions.first, isA<DataEntryFix>());
    var fix = dedup.proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix.targetNumber, equals("A1002675"));
    expect(reason: "source number", fix.sourceNumber, equals("XXXXXXX"));
  });
}

Future<List<DbShooterRating>> addMatchToTest(AnalystDatabase db, DbRatingProject project, String matchId) async {
  var dbMatch = await db.getMatchByAnySourceId([matchId]);
  project.matchPointers.add(MatchPointer.fromDbMatch(dbMatch!));

  await db.saveRatingProject(project);
  var match = dbMatch.hydrate().unwrap();

  List<DbShooterRating> newRatings = [];
  for(var competitor in match.shooters) {
    var r = DbShooterRating(
      sportName: idpaSport.name,
      firstName: competitor.firstName,
      lastName: competitor.lastName,
      rating: 1000,
      memberNumber: competitor.memberNumber,
      female: competitor.female,
      error: 0,
      connectivity: 0,
      rawConnectivity: 0,
      firstSeen: match.date,
      lastSeen: match.date,
    );
    r.copyVitalsFrom(competitor);
    newRatings.add(r);
  }

  return newRatings;
}

Future<void> setupTestDb(AnalystDatabase db) async {
  if(db.isar.name != "test-database") {
    throw Exception("Database is not a test database");
  }

  var competitorMap = generateCompetitors();

  var typoFix = generateMatch(
    shooters: [competitorMap["A1002675"]!, competitorMap["A1002676"]!],
    date: DateTime(2024, 1, 1),
    matchName: "Typo Fix",
    matchId: "typo-fix",
  );

  var typoBlacklist = generateMatch(
    shooters: [competitorMap["A1002675"]!, competitorMap["A864200"]!],
    date: DateTime(2024, 1, 2),
    matchName: "Typo Blacklist",
    matchId: "typo-blacklist",
  );

  var invalidNumber = generateMatch(
    shooters: [competitorMap["A1002675"]!, competitorMap["XXXXXXX"]!],
    date: DateTime(2024, 1, 3),
    matchName: "Typo Invalid Number",
    matchId: "typo-invalid-number",
  );

  var futures = [
    db.saveMatch(typoFix),
    db.saveMatch(typoBlacklist),
    db.saveMatch(invalidNumber),
  ];
  await Future.wait(futures);
}

Map<String, Shooter> generateCompetitors() {
  Map<String, Shooter> competitors = {};

  competitors["A1002675"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "A1002675",
  );

  competitors["A1002676"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "A1002676",
  );

  competitors["A864200"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "A864200",
  );

  competitors["XXXXXXX"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "XXXXXXX",
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

  var sport = idpaSport;
  var powerFactor = sport.defaultPowerFactor;

  var entries = List.generate(shooters.length, (index) {
    var shooter = shooters[index];

    Map<MatchStage, RawScore> scores = {};

    for(var stage in stages) {
      Map<ScoringEvent, int> hitCounts = {};
      for(int i = 0; i < stage.minRounds; i++) {
        int hitDie = r.nextInt(100);
        if(hitDie > 93) {
          hitCounts.increment(powerFactor.targetEvents.lookupByName("-1")!);
        }
        if(hitDie > 98) {
          hitCounts.increment(powerFactor.targetEvents.lookupByName("-3")!);
        }
      }

      // Time is between 0.6 and 0.8 times the number of rounds.
      var time = stage.minRounds * 0.7 * (1 - ((r.nextDouble() - 0.5) * 0.2));

      scores[stage] = RawScore(
        scoring: stage.scoring,
        targetEvents: hitCounts,
        rawTime: time,
      );
    }

    var entry = MatchEntry(
      entryId: index,
      division: sport.divisions.lookupByName("CO")!,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      powerFactor: powerFactor,
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
    sport: sport,
    shooters: entries,
    sourceIds: [matchId ?? Uuid().v4()],
    sourceCode: "test-autogen",
  );

  return match;
}
