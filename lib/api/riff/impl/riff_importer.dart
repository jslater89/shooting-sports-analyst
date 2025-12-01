/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:shooting_sports_analyst/api/riff/riff.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart";
import "package:shooting_sports_analyst/util.dart";

/// Implementation of AbstractRiffImporter.
class RiffImporter implements AbstractRiffImporter {
  @override
  Result<List<MatchRegistration>, ResultErr> importRegistrations(List<int> riffBytes) {
    try {
      // Decompress gzip
      var decompressed = gzip.decode(riffBytes);
      var jsonString = utf8.decode(decompressed);
      var json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate format
      if (json["format"] != "riff") {
        return Result.err(StringError("Invalid format: expected 'riff', got '${json["format"]}'"));
      }

      // Validate version
      var version = json["version"] as String?;
      if (version == null || !version.startsWith("1.")) {
        return Result.err(StringError("Unsupported version: $version"));
      }

      // Parse registrations
      var registrationsJson = json["registrations"] as List;
      var registrations = <MatchRegistration>[];
      for (var registrationJson in registrationsJson) {
        var registration = _parseRegistration(registrationJson as Map<String, dynamic>);
        if (registration.isErr()) {
          return Result.err(registration.unwrapErr());
        }
        registrations.add(registration.unwrap());
      }

      return Result.ok(registrations);
    } catch (e) {
      return Result.err(StringError("Failed to import registrations: $e"));
    }
  }

  Result<MatchRegistration, ResultErr> _parseRegistration(Map<String, dynamic> json) {
    try {
      // Required fields
      var matchId = json["matchId"] as String;
      var entryId = json["entryId"] as String;

      // Optional fields
      var shooterName = json["shooterName"] as String?;
      var shooterClassificationName = json["shooterClassificationName"] as String?;
      var shooterDivisionName = json["shooterDivisionName"] as String?;
      var shooterMemberNumber = json["shooterMemberNumber"] as String?;
      var squad = json["squad"] as String?;

      var registration = MatchRegistration(
        matchId: matchId,
        entryId: entryId,
        shooterName: shooterName,
        shooterClassificationName: shooterClassificationName,
        shooterDivisionName: shooterDivisionName,
        shooterMemberNumber: shooterMemberNumber,
        squad: squad,
      );

      return Result.ok(registration);
    } catch (e) {
      return Result.err(StringError("Failed to parse registration: $e"));
    }
  }
}

