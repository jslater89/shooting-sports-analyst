/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_exporter.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_importer.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_validator.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/match_prep.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/match.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/server/providers.dart";

void main() {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  group("RIFF Tests", () {
    late RiffValidator validator;
    late AnalystDatabase db;

    setUp(() async {
      validator = RiffValidator();
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

    test("Export and import registrations", () async {
      var registrations = [
        MatchRegistration(
          matchId: "test-match-1",
          entryId: "entry-1",
          shooterName: "John Doe",
          shooterClassificationName: "GM",
          shooterDivisionName: "Limited",
          shooterMemberNumbers: ["A12345"],
          squad: "Squad 1",
        ),
        MatchRegistration(
          matchId: "test-match-1",
          entryId: "entry-2",
          shooterName: "Jane Smith",
          shooterClassificationName: "M",
          shooterDivisionName: "Production",
          shooterMemberNumbers: ["A67890"],
          squad: "Squad 2",
        ),
        MatchRegistration(
          matchId: "test-match-1",
          entryId: "entry-3",
          shooterName: "Bob Johnson",
          shooterMemberNumbers: ["A11111"],
        ),
      ];

      var match = await createFutureMatchFromRegistrations(db, "test-match-1", registrations);

      // Export to RIFF
      var riffBytes = exportToRiff(match);
      expect(riffBytes, isNotNull);
      expect(riffBytes.length, greaterThan(0));

      // Validate exported RIFF
      var validationResult = validator.validate(riffBytes);
      expect(validationResult.isOk(), isTrue, reason: "Exported RIFF should be valid");

      // Import from RIFF
      var importedMatch = importFromRiff(riffBytes);
      // Save imported match to database so links work
      await db.saveFutureMatch(importedMatch, updateLinks: [MatchPrepLinkTypes.registrations]);
      var reloadedImportedMatch = await db.getFutureMatchByMatchId(importedMatch.matchId);
      expect(reloadedImportedMatch!.registrations.length, equals(registrations.length));

      // Compare registrations
      var importedRegistrations = reloadedImportedMatch.registrations.toList();
      registrations.sort((a, b) => a.entryId.compareTo(b.entryId));
      importedRegistrations.sort((a, b) => a.entryId.compareTo(b.entryId));
      for (var i = 0; i < registrations.length; i++) {
        expectRegistrationsEqual(importedRegistrations[i], registrations[i], reason: "Registration $i");
      }
    });

    test("Round-trip: export -> import -> export -> import", () async {
      var originalRegistrations = [
        MatchRegistration(
          matchId: "test-match-2",
          entryId: "entry-1",
          shooterName: "Alice Brown",
          shooterClassificationName: "A",
          shooterDivisionName: "Open",
          shooterMemberNumbers: ["B12345"],
          squad: "Squad A",
        ),
        MatchRegistration(
          matchId: "test-match-2",
          entryId: "entry-2",
          shooterName: "Charlie Davis",
          shooterDivisionName: "Limited",
        ),
      ];

      var originalMatch = await createFutureMatchFromRegistrations(db, "test-match-2", originalRegistrations);

      // First export/import cycle
      var riffBytes1 = exportToRiff(originalMatch);
      var validationResult1 = validator.validate(riffBytes1);
      expect(validationResult1.isOk(), isTrue, reason: "First export should be valid");
      var importedMatch1 = importFromRiff(riffBytes1);
      // Save imported match to database so links work
      await db.saveFutureMatch(importedMatch1, newRegistrations: originalRegistrations, updateLinks: [MatchPrepLinkTypes.registrations]);
      var reloadedMatch1 = await db.getFutureMatchByMatchId(importedMatch1.matchId);
      await reloadedMatch1!.registrations.load();

      // Second export/import cycle
      var riffBytes2 = exportToRiff(reloadedMatch1!);
      var validationResult2 = validator.validate(riffBytes2);
      expect(validationResult2.isOk(), isTrue, reason: "Second export should be valid");
      var importedMatch2 = importFromRiff(riffBytes2);

      // Compare: original -> first import
      var importedRegistrations1 = reloadedMatch1.registrations.toList();
      originalRegistrations.sort((a, b) => a.entryId.compareTo(b.entryId));
      importedRegistrations1.sort((a, b) => a.entryId.compareTo(b.entryId));
      expect(importedRegistrations1.length, equals(originalRegistrations.length));
      for (var i = 0; i < originalRegistrations.length; i++) {
        expectRegistrationsEqual(importedRegistrations1[i], originalRegistrations[i], reason: "First import registration $i");
      }

      // Compare: first import -> second import
      // Save imported match2 to database so links work
      await db.saveFutureMatch(importedMatch2, newRegistrations: importedRegistrations1, updateLinks: [MatchPrepLinkTypes.registrations]);
      var reloadedMatch2 = await db.getFutureMatchByMatchId(importedMatch2.matchId);
      await reloadedMatch2!.registrations.load();
      var importedRegistrations2 = reloadedMatch2.registrations.toList();
      importedRegistrations2.sort((a, b) => a.entryId.compareTo(b.entryId));
      expect(importedRegistrations2.length, equals(importedRegistrations1.length));
      for (var i = 0; i < importedRegistrations1.length; i++) {
        expectRegistrationsEqual(importedRegistrations2[i], importedRegistrations1[i], reason: "Second import registration $i");
      }
    });

    test("Export and import with minimal data", () async {
      var registrations = [
        MatchRegistration(
          matchId: "minimal-match",
          entryId: "minimal-entry",
        ),
      ];

      var match = await createFutureMatchFromRegistrations(db, "minimal-match", registrations);
      var riffBytes = exportToRiff(match);
      var validationResult = validator.validate(riffBytes);
      expect(validationResult.isOk(), isTrue, reason: "Minimal RIFF should be valid");

      var importedMatch = importFromRiff(riffBytes);
      // Save imported match to database so links work
      await db.saveFutureMatch(importedMatch, newRegistrations: registrations, updateLinks: [MatchPrepLinkTypes.registrations]);
      var reloadedImportedMatch = await db.getFutureMatchByMatchId(importedMatch.matchId);
      await reloadedImportedMatch!.registrations.load();
      expect(reloadedImportedMatch.registrations.length, equals(1));
      expectRegistrationsEqual(reloadedImportedMatch.registrations.first, registrations[0]);
    });

    test("Export and import with all optional fields", () async {
      var registrations = [
        MatchRegistration(
          matchId: "full-match",
          entryId: "full-entry",
          shooterName: "Full Name",
          shooterClassificationName: "GM",
          shooterDivisionName: "Open",
          shooterMemberNumbers: ["A99999"],
          squad: "Squad 5",
        ),
      ];

      var match = await createFutureMatchFromRegistrations(db, "full-match", registrations);
      var riffBytes = exportToRiff(match);
      var validationResult = validator.validate(riffBytes);
      expect(validationResult.isOk(), isTrue, reason: "Full RIFF should be valid");

      var importedMatch = importFromRiff(riffBytes);
      // Save imported match to database so links work
      await db.saveFutureMatch(importedMatch, newRegistrations: registrations, updateLinks: [MatchPrepLinkTypes.registrations]);
      var reloadedImportedMatch = await db.getFutureMatchByMatchId(importedMatch.matchId);
      await reloadedImportedMatch!.registrations.load();
      expect(reloadedImportedMatch.registrations.length, equals(1));
      expectRegistrationsEqual(reloadedImportedMatch.registrations.first, registrations[0]);
    });

    test("Validator: valid RIFF files pass validation", () async {
      var registrations = [
        MatchRegistration(
          matchId: "validator-test",
          entryId: "validator-entry",
          shooterName: "Test Shooter",
        ),
      ];

      var match = await createFutureMatchFromRegistrations(db, "validator-test", registrations);
      var riffBytes = exportToRiff(match);

      // Test validate() method
      var result = validator.validate(riffBytes);
      expect(result.isOk(), isTrue, reason: "RIFF should validate successfully");

      // Test validateJson() method
      var exporter = RiffExporter();
      var jsonData = exporter.toJson(match);
      var jsonResult = validator.validateJson(jsonData);
      expect(jsonResult.isOk(), isTrue, reason: "RIFF JSON should validate successfully");
    });

    test("Validator: missing required root fields", () {
      // Missing format
      var json1 = {
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": []
      };
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("format"));

      // Missing version
      var json2 = {
        "format": "riff",
        "match": {"matchId": "test-match"},
        "registrations": []
      };
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("version"));

      // Missing match
      var json3 = {
        "format": "riff",
        "version": "1.0",
        "registrations": []
      };
      var result3 = validator.validateJson(json3);
      expect(result3.isErr(), isTrue);
      expect(result3.unwrapErr().message, contains("match"));

      // Missing registrations
      var json4 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
      };
      var result4 = validator.validateJson(json4);
      expect(result4.isErr(), isTrue);
      expect(result4.unwrapErr().message, contains("registrations"));
    });

    test("Validator: invalid root field types", () {
      // Wrong format value
      var json1 = {
        "format": "not-riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": []
      };
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("format"));

      // Wrong version format
      var json2 = {
        "format": "riff",
        "version": "2.0",
        "match": {"matchId": "test-match"},
        "registrations": []
      };
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("version"));

      // Wrong match type
      var json3 = {
        "format": "riff",
        "version": "1.0",
        "match": "not-an-object",
        "registrations": []
      };
      var result3 = validator.validateJson(json3);
      expect(result3.isErr(), isTrue);
      expect(result3.unwrapErr().message, contains("match"));

      // Wrong registrations type
      var json4 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": "not-an-array"
      };
      var result4 = validator.validateJson(json4);
      expect(result4.isErr(), isTrue);
      expect(result4.unwrapErr().message, contains("registrations"));
    });

    test("Validator: missing required match fields", () {
      var baseJson = {
        "format": "riff",
        "version": "1.0",
        "match": {},
        "registrations": []
      };

      // Missing matchId
      var json1 = Map<String, dynamic>.from(baseJson);
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("matchId"));
    });

    test("Validator: missing required registration fields", () {
      var baseJson = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": []
      };

      // Missing entryId
      var json1 = Map<String, dynamic>.from(baseJson);
      json1["registrations"] = [
        {}
      ];
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("entryId"));
    });

    test("Validator: invalid match field types", () {
      // Invalid matchId type
      var json1 = {
        "format": "riff",
        "version": "1.0",
        "match": {
          "matchId": 123
        },
        "registrations": []
      };
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("matchId"));

      // Invalid eventName type
      var json2 = {
        "format": "riff",
        "version": "1.0",
        "match": {
          "matchId": "test-match",
          "eventName": 456
        },
        "registrations": []
      };
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("eventName"));

      // Invalid date format
      var json3 = {
        "format": "riff",
        "version": "1.0",
        "match": {
          "matchId": "test-match",
          "date": "invalid-date"
        },
        "registrations": []
      };
      var result3 = validator.validateJson(json3);
      expect(result3.isErr(), isTrue);
      expect(result3.unwrapErr().message, contains("date"));
    });

    test("Validator: invalid registration field types", () {
      // Invalid entryId type
      var json2 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": 456
          }
        ]
      };
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("entryId"));

      // Invalid shooterName type
      var json3 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "test-entry",
            "shooterName": 789
          }
        ]
      };
      var result3 = validator.validateJson(json3);
      expect(result3.isErr(), isTrue);
      expect(result3.unwrapErr().message, contains("shooterName"));

      // Invalid shooterClassificationName type
      var json4 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "test-entry",
            "shooterClassificationName": true
          }
        ]
      };
      var result4 = validator.validateJson(json4);
      expect(result4.isErr(), isTrue);
      expect(result4.unwrapErr().message, contains("shooterClassificationName"));

      // Invalid shooterDivisionName type
      var json5 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "test-entry",
            "shooterDivisionName": ["array"]
          }
        ]
      };
      var result5 = validator.validateJson(json5);
      expect(result5.isErr(), isTrue);
      expect(result5.unwrapErr().message, contains("shooterDivisionName"));

      // Invalid shooterMemberNumbers type (not an array)
      var json6 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "test-entry",
            "shooterMemberNumbers": {"object": "value"}
          }
        ]
      };
      var result6 = validator.validateJson(json6);
      expect(result6.isErr(), isTrue);
      expect(result6.unwrapErr().message, contains("shooterMemberNumbers"));

      // Invalid shooterMemberNumbers array element type
      var json7 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "test-entry",
            "shooterMemberNumbers": ["A12345", 123]
          }
        ]
      };
      var result7 = validator.validateJson(json7);
      expect(result7.isErr(), isTrue);
      expect(result7.unwrapErr().message, contains("shooterMemberNumbers"));

      // Invalid squad type
      var json9 = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "test-entry",
            "squad": 42
          }
        ]
      };
      var result9 = validator.validateJson(json9);
      expect(result9.isErr(), isTrue);
      expect(result9.unwrapErr().message, contains("squad"));
    });

    test("Validator: invalid registration array element type", () {
      var json = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          "not-an-object"
        ]
      };
      var result = validator.validateJson(json);
      expect(result.isErr(), isTrue);
      expect(result.unwrapErr().message, contains("Registrations[0]"));
    });

    test("Validator: empty registrations array is valid", () {
      var json = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": []
      };
      var result = validator.validateJson(json);
      expect(result.isOk(), isTrue);
    });

    test("Validator: multiple registrations with same entryId", () {
      // Note: This is technically valid JSON structure, even if it might not be semantically valid
      // The validator only checks structure, not semantic validity
      var json = {
        "format": "riff",
        "version": "1.0",
        "match": {"matchId": "test-match"},
        "registrations": [
          {
            "entryId": "same-entry",
            "shooterName": "First"
          },
          {
            "entryId": "same-entry",
            "shooterName": "Second"
          }
        ]
      };
      var result = validator.validateJson(json);
      expect(result.isOk(), isTrue, reason: "Structure is valid even if semantically duplicate");
    });
  });
}

/// Creates a FutureMatch from a list of registrations for testing purposes.
/// The match is saved to the database so that IsarLinks work correctly.
Future<FutureMatch> createFutureMatchFromRegistrations(AnalystDatabase db, String matchId, List<MatchRegistration> registrations) async {
  var match = FutureMatch(
    matchId: matchId,
    eventName: "Test Match",
    date: DateTime.now(),
    sportName: "uspsa",
    sourceCode: null,
    sourceIds: null,
  );
  match.registrations.addAll(registrations);
  await db.saveFutureMatch(match, updateLinks: [MatchPrepLinkTypes.registrations]);

  return match;
}

/// Exports a FutureMatch to RIFF format.
///
/// Returns the gzip-compressed JSON bytes.
List<int> exportToRiff(FutureMatch match) {
  var exporter = RiffExporter();
  var result = exporter.exportMatch(match);
  if (result.isErr()) {
    throw result.unwrapErr();
  }
  return result.unwrap();
}

/// Imports a FutureMatch from RIFF format.
///
/// Takes gzip-compressed JSON bytes and returns a FutureMatch.
FutureMatch importFromRiff(List<int> riffBytes) {
  var importer = RiffImporter();
  var result = importer.importMatch(riffBytes);
  if (result.isErr()) {
    throw result.unwrapErr();
  }
  return result.unwrap();
}

/// Compares two MatchRegistration objects for equality.
///
/// This function checks all relevant fields to ensure the registrations are equivalent.
void expectRegistrationsEqual(MatchRegistration actual, MatchRegistration expected, {String? reason}) {
  expect(actual.matchId, equals(expected.matchId), reason: reason != null ? "$reason: matchId" : "matchId");
  expect(actual.entryId, equals(expected.entryId), reason: reason != null ? "$reason: entryId" : "entryId");
  expect(actual.shooterName, equals(expected.shooterName), reason: reason != null ? "$reason: shooterName" : "shooterName");
  expect(actual.shooterClassificationName, equals(expected.shooterClassificationName), reason: reason != null ? "$reason: shooterClassificationName" : "shooterClassificationName");
  expect(actual.shooterDivisionName, equals(expected.shooterDivisionName), reason: reason != null ? "$reason: shooterDivisionName" : "shooterDivisionName");
  expect(actual.shooterMemberNumbers, equals(expected.shooterMemberNumbers), reason: reason != null ? "$reason: shooterMemberNumbers" : "shooterMemberNumbers");
  expect(actual.squad, equals(expected.squad), reason: reason != null ? "$reason: squad" : "squad");
}

