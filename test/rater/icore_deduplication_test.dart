/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/icore_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:uuid/uuid.dart';

void main() async {
  var db = AnalystDatabase.test();
  var ratingGroup = icoreSport.builtinRatingGroupsProvider!.divisionRatingGroups.firstWhere((e) => e.name == "Open");

  setUpAll(() async {
    print("Setting up test data");
    await setupTestDb(db);
  });

  // #region Tests

  test("Standard to Life", () async {
    var project = DbRatingProject(
      name: "Standard to Life",
      sportName: icoreSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "standard-to-life");
    var deduplicator = IcoreDeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var mapping = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", mapping.targetNumber, equals("LPA4532"));
    expect(reason: "source numbers", mapping.sourceNumbers, equals(["PA4532"]));
  });

  test("Standard to Vanity Life", () async {
    var project = DbRatingProject(
      name: "Standard to Vanity Life",
      sportName: icoreSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "standard-to-vanity-life");
    var deduplicator = IcoreDeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is ManualReviewRecommended", results[0].causes.first, isA<ManualReviewRecommended>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var mapping = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", mapping.targetNumber, equals("LPASTATSGEEK"));
    expect(reason: "source numbers", mapping.sourceNumbers, equals(["PA4532"]));
  });

  test("Standard to Life Typo", () async {
    var project = DbRatingProject(
      name: "Standard to Life Typo",
      sportName: icoreSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "standard-to-life-typo");
    var deduplicator = IcoreDeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    expect(reason: "proposed action 1 is DataEntryFix", results[0].proposedActions.first, isA<DataEntryFix>());
    var fix = results[0].proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix.targetNumber, equals("PA4532"));
    expect(reason: "source number", fix.sourceNumber, equals("PA4533"));
    expect(reason: "proposed action 2 is AutoMapping", results[0].proposedActions.last, isA<AutoMapping>());
    var mapping = results[0].proposedActions.last as AutoMapping;
    expect(reason: "target number", mapping.targetNumber, equals("LPA4532"));
    expect(reason: "source numbers", mapping.sourceNumbers, equals(["PA4532"]));
  });

  test("Reversed Standard to Life Typo", () async {
    var project = DbRatingProject(
      name: "Reversed Standard to Life Typo",
      sportName: icoreSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "reversed-standard-to-life-typo");
    var deduplicator = IcoreDeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, isEmpty);
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(2));
    expect(reason: "proposed action is DataEntryFix", results[0].proposedActions.first, isA<DataEntryFix>());
    var fix = results[0].proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix.targetNumber, equals("PA4533"));
    expect(reason: "source number", fix.sourceNumber, equals("PA4532"));
    expect(reason: "proposed action 2 is AutoMapping", results[0].proposedActions.last, isA<AutoMapping>());
    var mapping = results[0].proposedActions.last as AutoMapping;
    expect(reason: "target number", mapping.targetNumber, equals("LPA4533"));
    expect(reason: "source numbers", mapping.sourceNumbers, equals(["PA4533"]));
  });

  test("Typo Removal Standard to Vanity", () async {
    var project = DbRatingProject(
      name: "Typo Removal Standard to Vanity",
      sportName: icoreSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "typo-removal-standard-to-vanity");
    var deduplicator = IcoreDeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is ManualReviewRecommended", results[0].causes.first, isA<ManualReviewRecommended>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(3));
    expect(reason: "proposed action 1 is DataEntryFix", results[0].proposedActions.first, isA<DataEntryFix>());
    expect(reason: "proposed action 2 is DataEntryFix", results[0].proposedActions[1], isA<DataEntryFix>());
    expect(reason: "proposed action 3 is AutoMapping", results[0].proposedActions.last, isA<AutoMapping>());
    var fix1 = results[0].proposedActions.first as DataEntryFix;
    expect(reason: "target number", fix1.targetNumber, equals("PA4532"));
    expect(reason: "source number", fix1.sourceNumber, equals("PA4533"));
    var fix2 = results[0].proposedActions[1] as DataEntryFix;
    expect(reason: "target number", fix2.targetNumber, equals("LPASTATSGEEK"));
    expect(reason: "source number", fix2.sourceNumber, equals("LPASTATSGEKE"));
    var mapping = results[0].proposedActions.last as AutoMapping;
    expect(reason: "target number", mapping.targetNumber, equals("LPASTATSGEEK"));
    expect(reason: "source numbers", mapping.sourceNumbers, equals(["PA4532"]));
  });

  test("Three Step Mapping", () async {
    var project = DbRatingProject(
      name: "Three Step Mapping",
      sportName: icoreSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var newRatings = await addMatchToTest(db, project, "three-step-mapping");
    var deduplicator = IcoreDeduplicator();
    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      group: ratingGroup,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    var results = deduplication.unwrap();
    expect(reason: "number of results", results, hasLength(1));
    expect(reason: "number of causes", results[0].causes, hasLength(1));
    expect(reason: "cause is ManualReviewRecommended", results[0].causes.first, isA<ManualReviewRecommended>());
    expect(reason: "number of proposed actions", results[0].proposedActions, hasLength(1));
    expect(reason: "proposed action is AutoMapping", results[0].proposedActions.first, isA<AutoMapping>());
    var mapping = results[0].proposedActions.first as AutoMapping;
    expect(reason: "target number", mapping.targetNumber, equals("LPASTATSGEEK"));
    expect(reason: "source numbers", mapping.sourceNumbers, equals(["PA4532", "LPA4532"]));
  });
  

  // #endregion
}

Future<List<DbShooterRating>> addMatchToTest(AnalystDatabase db, DbRatingProject project, String matchId) async {
  var dbMatch = await db.getMatchByAnySourceId([matchId]);
  project.matchPointers.add(MatchPointer.fromDbMatch(dbMatch!));

  await db.saveRatingProject(project);
  var match = dbMatch.hydrate().unwrap();

  List<DbShooterRating> newRatings = [];
  for(var competitor in match.shooters) {
    var r = DbShooterRating(
      sportName: icoreSport.name,
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
  db.isar.writeTxn(() async {
    await db.isar.clear();
  });

  var competitorMap = generateCompetitors();

  var standardToLife = generateMatch(
    shooters: [competitorMap["PA4532"]!, competitorMap["LPA4532"]!],
    date: DateTime(2024, 1, 1),
    matchName: "Standard to Life",
    matchId: "standard-to-life",
  );

  var standardToVanityLife = generateMatch(
    shooters: [competitorMap["PA4532"]!, competitorMap["LPASTATSGEEK"]!],
    date: DateTime(2024, 1, 2),
    matchName: "Standard to Vanity Life",
    matchId: "standard-to-vanity-life",
  );

  var lifeToVanityLife = generateMatch(
    shooters: [competitorMap["LPASTATSGEEK"]!, competitorMap["LPA4532"]!],
    date: DateTime(2024, 1, 3),
    matchName: "Life to Vanity Life",
    matchId: "life-to-vanity-life",
  );

  var threeStepMapping = generateMatch(
    shooters: [competitorMap["PA4532"]!, competitorMap["LPA4532"]!, competitorMap["LPASTATSGEEK"]!],
    date: DateTime(2024, 1, 4),
    matchName: "Three Step Mapping",
    matchId: "three-step-mapping",
  );

  var standardToLifeTypo = generateMatch(
    shooters: [competitorMap["PA4533"]!, competitorMap["LPA4532"]!],
    date: DateTime(2024, 1, 5),
    matchName: "Standard to Life Typo",
    matchId: "standard-to-life-typo",
  );

  var reversedStandardToLifeTypo = generateMatch(
    shooters: [competitorMap["PA4532"]!, competitorMap["LPA4533"]!],
    date: DateTime(2024, 1, 6),
    matchName: "Reversed Standard to Life Typo",
    matchId: "reversed-standard-to-life-typo",
  );

  var typoRemovalStandardToVanity = generateMatch(
    shooters: [competitorMap["PA4532"]!, competitorMap["PA4533"]!, competitorMap["LPASTATSGEEK"]!, competitorMap["LPASTATSGEKE"]!],
    date: DateTime(2024, 1, 7),
    matchName: "Typo Removal Standard to Vanity",
    matchId: "typo-removal-standard-to-vanity",
  );

  var futures = [
    db.saveMatch(standardToLife),
    db.saveMatch(standardToVanityLife),
    db.saveMatch(lifeToVanityLife),
    db.saveMatch(threeStepMapping),
    db.saveMatch(standardToLifeTypo),
    db.saveMatch(reversedStandardToLifeTypo),
    db.saveMatch(typoRemovalStandardToVanity),
  ];
  await Future.wait(futures);
}

/// Generates a list of competitors useful for deduplication testing.
Map<String, Shooter> generateCompetitors() {
  Map<String, Shooter> competitors = {};

  /// Me!
  competitors["PA4532"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "PA4532",
  );

  /// Also me!
  competitors["LPA4532"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "LPA4532",
  );

  /// Me with a vanity number!
  competitors["LPASTATSGEEK"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "LPASTATSGEEK",
  );

  /// Me with a typo.
  competitors["PA4533"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "PA4533",
  );

  /// Also me with a typo.
  competitors["LPA4533"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "LPA4533",
  );

  /// Also me with a vanity number typo.
  competitors["LPASTATSGEKE"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "LPASTATSGEKE",
  );

  /// An imitator.
  competitors["AZ2512"] = Shooter(
    firstName: "Jay",
    lastName: "Slater",
    memberNumber: "AZ2512",
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
        if(hitDie > 8) {
          hitCounts.increment(icoreStandardPowerFactor.targetEvents.lookupByName("A")!);
        }
        else if(hitDie > 4) {
          hitCounts.increment(icoreStandardPowerFactor.targetEvents.lookupByName("B")!);
        }
        else if(hitDie > 3) {
          hitCounts.increment(icoreStandardPowerFactor.targetEvents.lookupByName("C")!);
        }
        else if(hitDie > 2) {
          hitCounts.increment(icoreStandardPowerFactor.targetEvents.lookupByName("M")!);
        }
        else {
          hitCounts.increment(icoreStandardPowerFactor.targetEvents.lookupByName("NS")!);
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
      division: icoreOpen,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      powerFactor: icoreStandardPowerFactor,
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
    sport: icoreSport,
    shooters: entries,
    sourceIds: [matchId ?? Uuid().v4()],
    sourceCode: "test-autogen",
  );

  return match;
}