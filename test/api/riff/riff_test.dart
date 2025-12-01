/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_exporter.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_importer.dart";
import "package:shooting_sports_analyst/api/riff/impl/riff_validator.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart";
import "package:shooting_sports_analyst/flutter_native_providers.dart";
import "package:shooting_sports_analyst/server/providers.dart";

void main() {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  group("RIFF Tests", () {
    late RiffValidator validator;

    setUp(() {
      validator = RiffValidator();
    });

    test("Export and import registrations", () {
      var registrations = [
        MatchRegistration(
          matchId: "test-match-1",
          entryId: "entry-1",
          shooterName: "John Doe",
          shooterClassificationName: "GM",
          shooterDivisionName: "Limited",
          shooterMemberNumber: "A12345",
          squad: "Squad 1",
        ),
        MatchRegistration(
          matchId: "test-match-1",
          entryId: "entry-2",
          shooterName: "Jane Smith",
          shooterClassificationName: "M",
          shooterDivisionName: "Production",
          shooterMemberNumber: "A67890",
          squad: "Squad 2",
        ),
        MatchRegistration(
          matchId: "test-match-1",
          entryId: "entry-3",
          shooterName: "Bob Johnson",
          shooterMemberNumber: "A11111",
        ),
      ];

      // Export to RIFF
      var riffBytes = exportToRiff(registrations);
      expect(riffBytes, isNotNull);
      expect(riffBytes.length, greaterThan(0));

      // Validate exported RIFF
      var validationResult = validator.validate(riffBytes);
      expect(validationResult.isOk(), isTrue, reason: "Exported RIFF should be valid");

      // Import from RIFF
      var importedRegistrations = importFromRiff(riffBytes);
      expect(importedRegistrations.length, equals(registrations.length));

      // Compare registrations
      for (var i = 0; i < registrations.length; i++) {
        expectRegistrationsEqual(importedRegistrations[i], registrations[i], reason: "Registration $i");
      }
    });

    test("Round-trip: export -> import -> export -> import", () {
      var originalRegistrations = [
        MatchRegistration(
          matchId: "test-match-2",
          entryId: "entry-1",
          shooterName: "Alice Brown",
          shooterClassificationName: "A",
          shooterDivisionName: "Open",
          shooterMemberNumber: "B12345",
          squad: "Squad A",
        ),
        MatchRegistration(
          matchId: "test-match-2",
          entryId: "entry-2",
          shooterName: "Charlie Davis",
          shooterDivisionName: "Limited",
        ),
      ];

      // First export/import cycle
      var riffBytes1 = exportToRiff(originalRegistrations);
      var validationResult1 = validator.validate(riffBytes1);
      expect(validationResult1.isOk(), isTrue, reason: "First export should be valid");
      var importedRegistrations1 = importFromRiff(riffBytes1);

      // Second export/import cycle
      var riffBytes2 = exportToRiff(importedRegistrations1);
      var validationResult2 = validator.validate(riffBytes2);
      expect(validationResult2.isOk(), isTrue, reason: "Second export should be valid");
      var importedRegistrations2 = importFromRiff(riffBytes2);

      // Compare: original -> first import
      expect(importedRegistrations1.length, equals(originalRegistrations.length));
      for (var i = 0; i < originalRegistrations.length; i++) {
        expectRegistrationsEqual(importedRegistrations1[i], originalRegistrations[i], reason: "First import registration $i");
      }

      // Compare: first import -> second import
      expect(importedRegistrations2.length, equals(importedRegistrations1.length));
      for (var i = 0; i < importedRegistrations1.length; i++) {
        expectRegistrationsEqual(importedRegistrations2[i], importedRegistrations1[i], reason: "Second import registration $i");
      }
    });

    test("Export and import with minimal data", () {
      var registrations = [
        MatchRegistration(
          matchId: "minimal-match",
          entryId: "minimal-entry",
        ),
      ];

      var riffBytes = exportToRiff(registrations);
      var validationResult = validator.validate(riffBytes);
      expect(validationResult.isOk(), isTrue, reason: "Minimal RIFF should be valid");

      var importedRegistrations = importFromRiff(riffBytes);
      expect(importedRegistrations.length, equals(1));
      expectRegistrationsEqual(importedRegistrations[0], registrations[0]);
    });

    test("Export and import with all optional fields", () {
      var registrations = [
        MatchRegistration(
          matchId: "full-match",
          entryId: "full-entry",
          shooterName: "Full Name",
          shooterClassificationName: "GM",
          shooterDivisionName: "Open",
          shooterMemberNumber: "A99999",
          squad: "Squad 5",
        ),
      ];

      var riffBytes = exportToRiff(registrations);
      var validationResult = validator.validate(riffBytes);
      expect(validationResult.isOk(), isTrue, reason: "Full RIFF should be valid");

      var importedRegistrations = importFromRiff(riffBytes);
      expect(importedRegistrations.length, equals(1));
      expectRegistrationsEqual(importedRegistrations[0], registrations[0]);
    });

    test("Validator: valid RIFF files pass validation", () {
      var registrations = [
        MatchRegistration(
          matchId: "validator-test",
          entryId: "validator-entry",
          shooterName: "Test Shooter",
        ),
      ];

      var riffBytes = exportToRiff(registrations);

      // Test validate() method
      var result = validator.validate(riffBytes);
      expect(result.isOk(), isTrue, reason: "RIFF should validate successfully");

      // Test validateJson() method
      var exporter = RiffExporter();
      var jsonData = exporter.toJson(registrations);
      var jsonResult = validator.validateJson(jsonData);
      expect(jsonResult.isOk(), isTrue, reason: "RIFF JSON should validate successfully");
    });

    test("Validator: missing required root fields", () {
      // Missing format
      var json1 = {
        "version": "1.0",
        "registrations": []
      };
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("format"));

      // Missing version
      var json2 = {
        "format": "riff",
        "registrations": []
      };
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("version"));

      // Missing registrations
      var json3 = {
        "format": "riff",
        "version": "1.0",
      };
      var result3 = validator.validateJson(json3);
      expect(result3.isErr(), isTrue);
      expect(result3.unwrapErr().message, contains("registrations"));
    });

    test("Validator: invalid root field types", () {
      // Wrong format value
      var json1 = {
        "format": "not-riff",
        "version": "1.0",
        "registrations": []
      };
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("format"));

      // Wrong version format
      var json2 = {
        "format": "riff",
        "version": "2.0",
        "registrations": []
      };
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("version"));

      // Wrong registrations type
      var json3 = {
        "format": "riff",
        "version": "1.0",
        "registrations": "not-an-array"
      };
      var result3 = validator.validateJson(json3);
      expect(result3.isErr(), isTrue);
      expect(result3.unwrapErr().message, contains("registrations"));
    });

    test("Validator: missing required registration fields", () {
      var baseJson = {
        "format": "riff",
        "version": "1.0",
        "registrations": []
      };

      // Missing matchId
      var json1 = Map<String, dynamic>.from(baseJson);
      json1["registrations"] = [
        {"entryId": "entry-1"}
      ];
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("matchId"));

      // Missing entryId
      var json2 = Map<String, dynamic>.from(baseJson);
      json2["registrations"] = [
        {"matchId": "match-1"}
      ];
      var result2 = validator.validateJson(json2);
      expect(result2.isErr(), isTrue);
      expect(result2.unwrapErr().message, contains("entryId"));
    });

    test("Validator: invalid registration field types", () {
      // Invalid matchId type
      var json1 = {
        "format": "riff",
        "version": "1.0",
        "registrations": [
          {
            "matchId": 123,
            "entryId": "test-entry"
          }
        ]
      };
      var result1 = validator.validateJson(json1);
      expect(result1.isErr(), isTrue);
      expect(result1.unwrapErr().message, contains("matchId"));

      // Invalid entryId type
      var json2 = {
        "format": "riff",
        "version": "1.0",
        "registrations": [
          {
            "matchId": "test-match",
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
        "registrations": [
          {
            "matchId": "test-match",
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
        "registrations": [
          {
            "matchId": "test-match",
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
        "registrations": [
          {
            "matchId": "test-match",
            "entryId": "test-entry",
            "shooterDivisionName": ["array"]
          }
        ]
      };
      var result5 = validator.validateJson(json5);
      expect(result5.isErr(), isTrue);
      expect(result5.unwrapErr().message, contains("shooterDivisionName"));

      // Invalid shooterMemberNumber type
      var json6 = {
        "format": "riff",
        "version": "1.0",
        "registrations": [
          {
            "matchId": "test-match",
            "entryId": "test-entry",
            "shooterMemberNumber": {"object": "value"}
          }
        ]
      };
      var result6 = validator.validateJson(json6);
      expect(result6.isErr(), isTrue);
      expect(result6.unwrapErr().message, contains("shooterMemberNumber"));

      // Invalid squad type
      var json7 = {
        "format": "riff",
        "version": "1.0",
        "registrations": [
          {
            "matchId": "test-match",
            "entryId": "test-entry",
            "squad": 42
          }
        ]
      };
      var result7 = validator.validateJson(json7);
      expect(result7.isErr(), isTrue);
      expect(result7.unwrapErr().message, contains("squad"));
    });

    test("Validator: invalid registration array element type", () {
      var json = {
        "format": "riff",
        "version": "1.0",
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
        "registrations": []
      };
      var result = validator.validateJson(json);
      expect(result.isOk(), isTrue);
    });

    test("Validator: multiple registrations with same matchId and entryId", () {
      // Note: This is technically valid JSON structure, even if it might not be semantically valid
      // The validator only checks structure, not semantic validity
      var json = {
        "format": "riff",
        "version": "1.0",
        "registrations": [
          {
            "matchId": "same-match",
            "entryId": "same-entry",
            "shooterName": "First"
          },
          {
            "matchId": "same-match",
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

/// Exports a list of MatchRegistration objects to RIFF format.
///
/// Returns the gzip-compressed JSON bytes.
List<int> exportToRiff(List<MatchRegistration> registrations) {
  var exporter = RiffExporter();
  var result = exporter.exportRegistrations(registrations);
  if (result.isErr()) {
    throw result.unwrapErr();
  }
  return result.unwrap();
}

/// Imports a list of MatchRegistration objects from RIFF format.
///
/// Takes gzip-compressed JSON bytes and returns a list of MatchRegistration objects.
List<MatchRegistration> importFromRiff(List<int> riffBytes) {
  var importer = RiffImporter();
  var result = importer.importRegistrations(riffBytes);
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
  expect(actual.shooterMemberNumber, equals(expected.shooterMemberNumber), reason: reason != null ? "$reason: shooterMemberNumber" : "shooterMemberNumber");
  expect(actual.squad, equals(expected.squad), reason: reason != null ? "$reason: squad" : "squad");
}

