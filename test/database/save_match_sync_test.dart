/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/api/miff/impl/miff_importer.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/server/providers.dart";

void main() {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();

  group("AnalystDatabase.saveMatchSync Tests", () {
    late AnalystDatabase db;

    setUp(() async {
      db = AnalystDatabase.test();
      await db.ready;
      // Clear the test database before each test
      await db.isar.writeTxn(() async {
        await db.isar.clear();
      });
    });

    tearDown(() async {
      await db.isar.writeTxn(() async {
        await db.isar.clear();
      });
    });

    test("sidecar competitor storage", () async {
      // Load the MIFF file from data/test
      var miffFile = File("data/test/2025-ipsc-handgun-world-shoot-949e40673709d62673eec10da85451c7899d477a.miff.gz");
      expect(miffFile.existsSync(), isTrue, reason: "MIFF file should exist at ${miffFile.path}");

      // Import the match from MIFF
      var importer = MiffImporter();
      var miffBytes = miffFile.readAsBytesSync();
      var importResult = importer.importMatch(miffBytes);
      expect(importResult.isOk(), isTrue, reason: "MIFF import should succeed");
      var match = importResult.unwrap();

      // Verify the match has required fields and competitors before saving
      expect(match.sourceIds, isNotEmpty, reason: "Match should have source IDs");
      expect(match.sourceCode, isNotEmpty, reason: "Match should have a source code");
      expect(match.shooters, isNotEmpty, reason: "Imported match should have shooters");
      var originalShooterCount = match.shooters.length;

      // Save the match asynchronously
      var saveResultAsync = await db.saveMatch(match);
      expect(saveResultAsync.isOk(), isTrue, reason: "saveMatch should succeed: ${saveResultAsync.isErr() ? saveResultAsync.unwrapErr().message : ""}");
      var savedDbMatchAsync = saveResultAsync.unwrap();
      expect(savedDbMatchAsync.id, greaterThan(0), reason: "Saved match should have a database ID");

      var retrievedMatchAsync = await db.getMatch(savedDbMatchAsync.id);
      expect(retrievedMatchAsync, isNotNull, reason: "Retrieved match should be retrievable by database ID");
      expect(retrievedMatchAsync!.eventName, equals(match.name), reason: "Retrieved match name should match");

      var hydratedResultAsync = retrievedMatchAsync.hydrate();
      expect(hydratedResultAsync.isOk(), isTrue, reason: "Match should hydrate successfully");
      var hydratedMatchAsync = hydratedResultAsync.unwrap();
      expect(hydratedMatchAsync.shooters, isNotEmpty, reason: "Hydrated match should have competitors after saveMatchSync");
      expect(hydratedMatchAsync.shooters.length, equals(originalShooterCount), reason: "Hydrated match should have the same number of competitors as the original ($originalShooterCount)");

      // Save the match synchronously
      var saveResult = db.saveMatchSync(match);
      expect(saveResult.isOk(), isTrue, reason: "saveMatchSync should succeed: ${saveResult.isErr() ? saveResult.unwrapErr().message : ""}");

      var savedDbMatch = saveResult.unwrap();
      expect(savedDbMatch.id, greaterThan(0), reason: "Saved match should have a database ID");

      // Verify the match can be retrieved by source ID
      var retrievedMatch = db.getMatchByAnySourceIdSync(match.sourceIds);
      expect(retrievedMatch, isNotNull, reason: "Match should be retrievable by source ID after saveMatchSync");
      expect(retrievedMatch!.eventName, equals(match.name), reason: "Retrieved match name should match");

      // KEY CHECK: Load the match from database, hydrate it, and verify it has competitors
      var hydratedResult = retrievedMatch.hydrate();
      expect(hydratedResult.isOk(), isTrue, reason: "Match should hydrate successfully");
      var hydratedMatch = hydratedResult.unwrap();
      expect(hydratedMatch.shooters, isNotEmpty, reason: "Hydrated match should have competitors after saveMatchSync");
      expect(hydratedMatch.shooters.length, equals(originalShooterCount),
          reason: "Hydrated match should have the same number of competitors as the original ($originalShooterCount)");

      // Verify the match can be retrieved by database ID
      var retrievedById = await db.getMatch(savedDbMatch.id);
      expect(retrievedById, isNotNull, reason: "Match should be retrievable by database ID");
      expect(retrievedById!.eventName, equals(match.name), reason: "Retrieved match name should match");

      // Also hydrate and check the one retrieved by ID
      var hydratedByIdResult = retrievedById.hydrate();
      expect(hydratedByIdResult.isOk(), isTrue, reason: "Match retrieved by ID should hydrate successfully");
      var hydratedById = hydratedByIdResult.unwrap();
      expect(hydratedById.shooters, isNotEmpty, reason: "Hydrated match (by ID) should have competitors");
      expect(hydratedById.shooters.length, equals(originalShooterCount),
          reason: "Hydrated match (by ID) should have the same number of competitors");

      // Verify hasMatchByAnySourceIdSync returns true
      var hasMatch = db.hasMatchByAnySourceIdSync(match.sourceIds);
      expect(hasMatch, isTrue, reason: "hasMatchByAnySourceIdSync should return true after save");
    });

    test("saveMatchSync updates an existing match", () async {
      // Load the MIFF file
      var miffFile = File("data/test/2025-ipsc-handgun-world-shoot-949e40673709d62673eec10da85451c7899d477a.miff.gz");
      var importer = MiffImporter();
      var miffBytes = miffFile.readAsBytesSync();
      var importResult = importer.importMatch(miffBytes);
      expect(importResult.isOk(), isTrue);
      var match = importResult.unwrap();

      // Save the match first time
      var firstSaveResult = db.saveMatchSync(match);
      expect(firstSaveResult.isOk(), isTrue);
      var firstId = firstSaveResult.unwrap().id;

      // Re-import and save again (simulating an update)
      var importResult2 = importer.importMatch(miffBytes);
      var match2 = importResult2.unwrap();
      var secondSaveResult = db.saveMatchSync(match2);
      expect(secondSaveResult.isOk(), isTrue, reason: "Second saveMatchSync should succeed");
      var secondId = secondSaveResult.unwrap().id;

      // The match should be updated, not duplicated
      expect(secondId, equals(firstId), reason: "Match ID should remain the same after update");

      // Verify there is only one match with this source ID
      var allMatches = await db.getAllMatches();
      var matchesWithSourceId = allMatches.where((m) =>
        m.sourceIds.any((id) => match.sourceIds.contains(id))
      ).toList();
      expect(matchesWithSourceId.length, equals(1), reason: "There should be exactly one match with the source ID");
    });

    test("saveMatchSync handles large match with many shooters", () async {
      // The World Shoot is a large match that tests the shootersStoredSeparately functionality
      var miffFile = File("data/test/2025-ipsc-handgun-world-shoot-949e40673709d62673eec10da85451c7899d477a.miff.gz");
      var importer = MiffImporter();
      var miffBytes = miffFile.readAsBytesSync();
      var importResult = importer.importMatch(miffBytes);
      expect(importResult.isOk(), isTrue);
      var match = importResult.unwrap();

      // This match should be large enough to potentially use separate shooter storage
      expect(match.shooters.length, greaterThan(100), reason: "World Shoot should have many shooters");

      // Save the match
      var saveResult = db.saveMatchSync(match);
      expect(saveResult.isOk(), isTrue, reason: "saveMatchSync should handle large matches");

      // Retrieve and verify shooter count
      var retrievedMatch = db.getMatchByAnySourceIdSync(match.sourceIds);
      expect(retrievedMatch, isNotNull);

      // Hydrate the match to access shooters
      var hydratedResult = retrievedMatch!.hydrate();
      expect(hydratedResult.isOk(), isTrue, reason: "Match should hydrate successfully");
      var hydratedMatch = hydratedResult.unwrap();
      expect(hydratedMatch.shooters.length, equals(match.shooters.length),
          reason: "Retrieved match should have same number of shooters");
    });
  });
}

