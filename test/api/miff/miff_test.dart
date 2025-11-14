/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_exporter.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_importer.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";

void main() {
  group("MIFF Tests", () {
    late AnalystDatabase db;

    setUp(() async {
      db = AnalystDatabase();
      await db.ready;
    });

    // Test matches with useful properties:
    // 1. ICORE match (has variable events)
    // 2. IDPA National Championship (large match, different sport)
    // 3. SIG Sauer Factory Gun Nationals (USPSA, large match)
    final testMatches = [
      "19d277bd-c7fb-4850-b14b-d8551d50343e", // Shooting Sports Analyst ICORE Feb 28, 2025
      "cc98089a-83ad-4898-9622-b7cd16e41ddb", // 2025 IDPA National Championship Presented by Beretta
      "44b2f321-a893-4ca3-b3cc-22ffcca0cb08", // The 2025 SIG Sauer Factory Gun Nationals presented by Vortex Optics
    ];

    test("Export match from database", () async {
      for (var matchId in testMatches) {
        var dbMatch = await db.getMatchByAnySourceId([matchId]);
        expect(dbMatch, isNotNull, reason: "Match $matchId should exist in database");
        
        var originalMatch = dbMatch!.hydrate().unwrap();
        
        // Export to MIFF
        var miffBytes = await exportToMiff(originalMatch);
        expect(miffBytes, isNotNull, reason: "MIFF export should produce bytes for $matchId");
        expect(miffBytes.length, greaterThan(0), reason: "MIFF export should not be empty for $matchId");
      }
    });

    test("Import match from MIFF and compare to database version", () async {
      for (var matchId in testMatches) {
        var dbMatch = await db.getMatchByAnySourceId([matchId]);
        expect(dbMatch, isNotNull, reason: "Match $matchId should exist in database");
        
        var originalMatch = dbMatch!.hydrate().unwrap();
        
        // Export to MIFF
        var miffBytes = await exportToMiff(originalMatch);
        
        // Import from MIFF
        var importedMatch = await importFromMiff(miffBytes);
        
        // Compare matches
        expectMatchesEqual(importedMatch, originalMatch, reason: "Match $matchId");
      }
    });

    test("Round-trip: export -> import -> export -> import", () async {
      for (var matchId in testMatches) {
        var dbMatch = await db.getMatchByAnySourceId([matchId]);
        expect(dbMatch, isNotNull, reason: "Match $matchId should exist in database");
        
        var originalMatch = dbMatch!.hydrate().unwrap();
        
        // First export/import cycle
        var miffBytes1 = await exportToMiff(originalMatch);
        var importedMatch1 = await importFromMiff(miffBytes1);
        
        // Second export/import cycle
        var miffBytes2 = await exportToMiff(importedMatch1);
        var importedMatch2 = await importFromMiff(miffBytes2);
        
        // Compare: original -> first import
        expectMatchesEqual(importedMatch1, originalMatch, reason: "Match $matchId first import");
        
        // Compare: first import -> second import
        expectMatchesEqual(importedMatch2, importedMatch1, reason: "Match $matchId second import");
      }
    });
  });
}

/// Exports a ShootingMatch to MIFF format.
/// 
/// Returns the gzip-compressed JSON bytes.
Future<List<int>> exportToMiff(ShootingMatch match) async {
  var exporter = MiffExporter();
  var result = exporter.exportMatch(match);
  if (result.isErr()) {
    throw result.unwrapErr();
  }
  return result.unwrap();
}

/// Imports a ShootingMatch from MIFF format.
/// 
/// Takes gzip-compressed JSON bytes and returns a ShootingMatch.
ShootingMatch importFromMiff(List<int> miffBytes) {
  var importer = MiffImporter();
  var result = importer.importMatch(miffBytes);
  if (result.isErr()) {
    throw result.unwrapErr();
  }
  return result.unwrap();
}

/// Compares two ShootingMatch objects for equality.
/// 
/// This function checks all relevant fields to ensure the matches are equivalent.
/// Note that some fields like databaseId may differ between database and imported matches.
void expectMatchesEqual(ShootingMatch actual, ShootingMatch expected, {String? reason}) {
  expect(actual.name, equals(expected.name), reason: reason != null ? "$reason: match name" : "match name");
  expect(actual.rawDate, equals(expected.rawDate), reason: reason != null ? "$reason: raw date" : "raw date");
  expect(actual.date, equals(expected.date), reason: reason != null ? "$reason: date" : "date");
  expect(actual.sourceCode, equals(expected.sourceCode), reason: reason != null ? "$reason: source code" : "source code");
  expect(actual.sourceIds, equals(expected.sourceIds), reason: reason != null ? "$reason: source IDs" : "source IDs");
  expect(actual.sport.name, equals(expected.sport.name), reason: reason != null ? "$reason: sport name" : "sport name");
  
  if (actual.level != null && expected.level != null) {
    expect(actual.level!.name, equals(expected.level!.name), reason: reason != null ? "$reason: level name" : "level name");
    expect(actual.level!.eventLevel, equals(expected.level!.eventLevel), reason: reason != null ? "$reason: event level" : "event level");
  } else {
    expect(actual.level, equals(expected.level), reason: reason != null ? "$reason: level" : "level");
  }
  
  // Compare stages
  expect(actual.stages.length, equals(expected.stages.length), reason: reason != null ? "$reason: stage count" : "stage count");
  for (var i = 0; i < actual.stages.length; i++) {
    expectStagesEqual(actual.stages[i], expected.stages[i], reason: reason);
  }
  
  // Compare local events
  expect(actual.localBonusEvents.length, equals(expected.localBonusEvents.length), reason: reason != null ? "$reason: local bonus events count" : "local bonus events count");
  expect(actual.localPenaltyEvents.length, equals(expected.localPenaltyEvents.length), reason: reason != null ? "$reason: local penalty events count" : "local penalty events count");
  
  // Compare shooters
  expect(actual.shooters.length, equals(expected.shooters.length), reason: reason != null ? "$reason: shooter count" : "shooter count");
  
  // Create maps by entry ID for easier comparison
  var actualShootersMap = {for (var s in actual.shooters) s.entryId: s};
  var expectedShootersMap = {for (var s in expected.shooters) s.entryId: s};
  
  for (var entryId in actualShootersMap.keys) {
    expect(expectedShootersMap.containsKey(entryId), isTrue, reason: reason != null ? "$reason: shooter $entryId exists" : "shooter $entryId exists");
    expectShootersEqual(actualShootersMap[entryId]!, expectedShootersMap[entryId]!, reason: reason);
  }
}

/// Compares two MatchStage objects for equality.
void expectStagesEqual(MatchStage actual, MatchStage expected, {String? reason}) {
  expect(actual.stageId, equals(expected.stageId), reason: reason != null ? "$reason: stage ID" : "stage ID");
  expect(actual.name, equals(expected.name), reason: reason != null ? "$reason: stage name" : "stage name");
  expect(actual.minRounds, equals(expected.minRounds), reason: reason != null ? "$reason: min rounds" : "min rounds");
  expect(actual.maxPoints, equals(expected.maxPoints), reason: reason != null ? "$reason: max points" : "max points");
  expect(actual.classifier, equals(expected.classifier), reason: reason != null ? "$reason: classifier" : "classifier");
  expect(actual.classifierNumber, equals(expected.classifierNumber), reason: reason != null ? "$reason: classifier number" : "classifier number");
  expect(actual.scoring.dbString, equals(expected.scoring.dbString), reason: reason != null ? "$reason: scoring type" : "scoring type");
  expect(actual.sourceId, equals(expected.sourceId), reason: reason != null ? "$reason: source ID" : "source ID");
  
  // Compare scoring overrides
  expect(actual.scoringOverrides.length, equals(expected.scoringOverrides.length), reason: reason != null ? "$reason: scoring overrides count" : "scoring overrides count");
  for (var key in actual.scoringOverrides.keys) {
    expect(expected.scoringOverrides.containsKey(key), isTrue, reason: reason != null ? "$reason: scoring override $key exists" : "scoring override $key exists");
    var actualOverride = actual.scoringOverrides[key]!;
    var expectedOverride = expected.scoringOverrides[key]!;
    expect(actualOverride.pointChangeOverride, equals(expectedOverride.pointChangeOverride), reason: reason != null ? "$reason: override $key points" : "override $key points");
    expect(actualOverride.timeChangeOverride, equals(expectedOverride.timeChangeOverride), reason: reason != null ? "$reason: override $key time" : "override $key time");
  }
  
  // Compare variable events
  expect(actual.variableEvents.length, equals(expected.variableEvents.length), reason: reason != null ? "$reason: variable events count" : "variable events count");
  for (var key in actual.variableEvents.keys) {
    expect(expected.variableEvents.containsKey(key), isTrue, reason: reason != null ? "$reason: variable events $key exists" : "variable events $key exists");
    var actualEvents = actual.variableEvents[key]!;
    var expectedEvents = expected.variableEvents[key]!;
    expect(actualEvents.length, equals(expectedEvents.length), reason: reason != null ? "$reason: variable events $key count" : "variable events $key count");
    for (var i = 0; i < actualEvents.length; i++) {
      expectScoringEventsEqual(actualEvents[i], expectedEvents[i], reason: reason);
    }
  }
}

/// Compares two MatchEntry objects for equality.
void expectShootersEqual(MatchEntry actual, MatchEntry expected, {String? reason}) {
  expect(actual.entryId, equals(expected.entryId), reason: reason != null ? "$reason: entry ID" : "entry ID");
  expect(actual.firstName, equals(expected.firstName), reason: reason != null ? "$reason: first name" : "first name");
  expect(actual.lastName, equals(expected.lastName), reason: reason != null ? "$reason: last name" : "last name");
  expect(actual.memberNumber, equals(expected.memberNumber), reason: reason != null ? "$reason: member number" : "member number");
  expect(actual.originalMemberNumber, equals(expected.originalMemberNumber), reason: reason != null ? "$reason: original member number" : "original member number");
  expect(actual.knownMemberNumbers, equals(expected.knownMemberNumbers), reason: reason != null ? "$reason: known member numbers" : "known member numbers");
  expect(actual.female, equals(expected.female), reason: reason != null ? "$reason: female" : "female");
  expect(actual.reentry, equals(expected.reentry), reason: reason != null ? "$reason: reentry" : "reentry");
  expect(actual.dq, equals(expected.dq), reason: reason != null ? "$reason: dq" : "dq");
  expect(actual.squad, equals(expected.squad), reason: reason != null ? "$reason: squad" : "squad");
  expect(actual.powerFactor.name, equals(expected.powerFactor.name), reason: reason != null ? "$reason: power factor" : "power factor");
  expect(actual.division?.name, equals(expected.division?.name), reason: reason != null ? "$reason: division" : "division");
  expect(actual.classification?.name, equals(expected.classification?.name), reason: reason != null ? "$reason: classification" : "classification");
  expect(actual.ageCategory?.name, equals(expected.ageCategory?.name), reason: reason != null ? "$reason: age category" : "age category");
  expect(actual.sourceId, equals(expected.sourceId), reason: reason != null ? "$reason: source ID" : "source ID");
  
  // Compare scores
  expect(actual.scores.length, equals(expected.scores.length), reason: reason != null ? "$reason: scores count" : "scores count");
  
  // Create maps by stage ID for easier comparison
  var actualScoresMap = {for (var entry in actual.scores.entries) entry.key.stageId: entry.value};
  var expectedScoresMap = {for (var entry in expected.scores.entries) entry.key.stageId: entry.value};
  
  for (var stageId in actualScoresMap.keys) {
    expect(expectedScoresMap.containsKey(stageId), isTrue, reason: reason != null ? "$reason: score for stage $stageId exists" : "score for stage $stageId exists");
    expectScoresEqual(actualScoresMap[stageId]!, expectedScoresMap[stageId]!, reason: reason);
  }
}

/// Compares two RawScore objects for equality.
/// 
/// Only checks nonzero event counts - events with count 0 may or may not be present.
void expectScoresEqual(RawScore actual, RawScore expected, {String? reason}) {
  expect(actual.scoring.dbString, equals(expected.scoring.dbString), reason: reason != null ? "$reason: scoring type" : "scoring type");
  expect(actual.rawTime, equals(expected.rawTime), reason: reason != null ? "$reason: raw time" : "raw time");
  expect(actual.dq, equals(expected.dq), reason: reason != null ? "$reason: dq" : "dq");
  expect(actual.stringTimes, equals(expected.stringTimes), reason: reason != null ? "$reason: string times" : "string times");
  
  // Compare target events - only check nonzero counts
  var actualNonZeroTargets = actual.targetEvents.entries.where((e) => e.value > 0).toList();
  var expectedNonZeroTargets = expected.targetEvents.entries.where((e) => e.value > 0).toList();
  String actualNonZeroTargetsString = actualNonZeroTargets.map((e) => "${e.key.name} ${e.value}").join(", ");
  String expectedNonZeroTargetsString = expectedNonZeroTargets.map((e) => "${e.key.name} ${e.value}").join(", ");
  expect(actualNonZeroTargets.length, equals(expectedNonZeroTargets.length), reason: reason != null ? "$reason: nonzero target events count (actual: $actualNonZeroTargetsString, expected: $expectedNonZeroTargetsString)" : "nonzero target events count (actual: $actualNonZeroTargetsString, expected: $expectedNonZeroTargetsString)");
  
  for (var entry in actualNonZeroTargets) {
    var event = entry.key;
    var count = entry.value;
    var matchingEvent = expectedNonZeroTargets.firstWhere(
      (e) => e.key.name == event.name && 
             e.key.pointChange == event.pointChange && 
             e.key.timeChange == event.timeChange,
      orElse: () => throw StateError("No matching event found for ${event.name}"),
    );
    expect(count, equals(matchingEvent.value), reason: reason != null ? "$reason: target event ${event.name} count" : "target event ${event.name} count");
  }
  
  // Compare penalty events - only check nonzero counts
  var actualNonZeroPenalties = actual.penaltyEvents.entries.where((e) => e.value > 0).toList();
  var expectedNonZeroPenalties = expected.penaltyEvents.entries.where((e) => e.value > 0).toList();
  expect(actualNonZeroPenalties.length, equals(expectedNonZeroPenalties.length), reason: reason != null ? "$reason: nonzero penalty events count" : "nonzero penalty events count");
  
  for (var entry in actualNonZeroPenalties) {
    var event = entry.key;
    var count = entry.value;
    var matchingEvent = expectedNonZeroPenalties.firstWhere(
      (e) => e.key.name == event.name && 
             e.key.pointChange == event.pointChange && 
             e.key.timeChange == event.timeChange,
      orElse: () => throw StateError("No matching event found for ${event.name}"),
    );
    expect(count, equals(matchingEvent.value), reason: reason != null ? "$reason: penalty event ${event.name} count" : "penalty event ${event.name} count");
  }
}

/// Compares two ScoringEvent objects for equality.
void expectScoringEventsEqual(ScoringEvent actual, ScoringEvent expected, {String? reason}) {
  expect(actual.name, equals(expected.name), reason: reason != null ? "$reason: event name" : "event name");
  expect(actual.shortName, equals(expected.shortName), reason: reason != null ? "$reason: short name" : "short name");
  expect(actual.pointChange, equals(expected.pointChange), reason: reason != null ? "$reason: point change" : "point change");
  expect(actual.timeChange, equals(expected.timeChange), reason: reason != null ? "$reason: time change" : "time change");
  expect(actual.bonus, equals(expected.bonus), reason: reason != null ? "$reason: bonus" : "bonus");
  expect(actual.bonusLabel, equals(expected.bonusLabel), reason: reason != null ? "$reason: bonus label" : "bonus label");
}

