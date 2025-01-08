import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
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

  test("DataEntryFix similar numbers", () async {
    var project = DbRatingProject(
      name: "DataEntryFix Test Project",
      sportName: uspsaSport.name,
      settings: RatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(),
      )
    );

    var dbMatch = await db.getMatchByAnySourceId(["data-entry-fix-similar-numbers"]);
    project.matches.add(dbMatch!);

    await db.saveRatingProject(project);
    var deduplicator = USPSADeduplicator();
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

    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    
    var results = deduplication.unwrap();
    expect(reason: "number of results", results.length, equals(1));
    expect(reason: "number of causes", results[0].causes.length, equals(1));
    expect(reason: "cause is MultipleNumbersOfType", results[0].causes.first, isA<MultipleNumbersOfType>());
    expect(reason: "number of proposed actions", results[0].proposedActions.length, equals(1));
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

    var dbMatch = await db.getMatchByAnySourceId(["data-entry-fix-dissimilar-numbers"]);
    project.matches.add(dbMatch!);

    await db.saveRatingProject(project);
    var deduplicator = USPSADeduplicator();
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

    var deduplication = await deduplicator.deduplicateShooters(
      ratingProject: project,
      newRatings: newRatings,
      checkDataEntryErrors: true,
    );

    expect(deduplication.isOk(), isTrue);
    
    var results = deduplication.unwrap();
    expect(reason: "number of results", results.length, equals(1));
    expect(reason: "number of causes", results[0].causes.length, equals(1));
    expect(reason: "cause is MultipleNumbersOfType", results[0].causes.first, isA<MultipleNumbersOfType>());
    expect(reason: "number of proposed actions", results[0].proposedActions.length, equals(1));
    expect(reason: "proposed action is DataEntryFix", results[0].proposedActions.first, isA<Blacklist>());
    var fix = results[0].proposedActions.first as Blacklist;
    expect(reason: "target number", fix.targetNumber, equals("A123456"));
    expect(reason: "source number", fix.sourceNumber, equals("A76691"));
  });
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

  var futures = [
    db.saveMatch(simpleDataEntryMatch),
    db.saveMatch(simpleBlacklistMatch),
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