/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:shooting_sports_analyst/api/riff/riff.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/match.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart";
import "package:shooting_sports_analyst/util.dart";

/// Implementation of AbstractRiffImporter.
class RiffImporter implements AbstractRiffImporter {

  /// Import a RIFF to a FutureMatch.
  ///
  /// Note that the registrations object on the new match will be unset until the match
  /// is saved; parsed registrations go into [FutureMatch.newRegistrations].
  @override
  Result<FutureMatch, ResultErr> importMatch(List<int> riffBytes) {
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

      // Parse match
      var matchJson = json["match"] as Map<String, dynamic>;
      var matchResult = _parseMatch(matchJson);
      if (matchResult.isErr()) {
        return Result.err(matchResult.unwrapErr());
      }
      var match = matchResult.unwrap();

      // Parse registrations
      var registrationsJson = json["registrations"] as List;
      var registrations = <MatchRegistration>[];
      for (var registrationJson in registrationsJson) {
        var registration = _parseRegistration(registrationJson as Map<String, dynamic>, match.matchId);
        if (registration.isErr()) {
          return Result.err(registration.unwrapErr());
        }
        registrations.add(registration.unwrap());
      }

      // Attach registrations to match
      match.newRegistrations = registrations;

      return Result.ok(match);
    } catch (e) {
      return Result.err(StringError("Failed to import match: $e"));
    }
  }

  Result<FutureMatch, ResultErr> _parseMatch(Map<String, dynamic> json) {
    try {
      // Required field
      var matchId = json["matchId"] as String;

      // Optional fields
      var eventName = json["eventName"] as String? ?? "";
      var dateStr = json["date"] as String?;
      DateTime date;
      if (dateStr != null) {
        try {
          date = DateTime.parse(dateStr);
        } catch (e) {
          return Result.err(StringError("Invalid date format: $dateStr"));
        }
      } else {
        date = practicalShootingZeroDate;
      }
      var sportName = json["sportName"] as String? ?? "unknown";
      var sourceCode = json["sourceCode"] as String?;
      List<String>? sourceIds;
      if (json.containsKey("sourceIds")) {
        var sourceIdsList = json["sourceIds"] as List;
        sourceIds = sourceIdsList.map((e) => e.toString()).toList();
      }

      var match = FutureMatch(
        matchId: matchId,
        eventName: eventName,
        date: date,
        sportName: sportName,
        sourceCode: sourceCode,
        sourceIds: sourceIds,
      );

      return Result.ok(match);
    } catch (e) {
      return Result.err(StringError("Failed to parse match: $e"));
    }
  }

  Result<MatchRegistration, ResultErr> _parseRegistration(Map<String, dynamic> json, String matchId) {
    try {
      // Required fields
      var entryId = json["entryId"] as String;

      // Optional fields
      var shooterName = json["shooterName"] as String?;
      var shooterClassificationName = json["shooterClassificationName"] as String?;
      var shooterDivisionName = json["shooterDivisionName"] as String?;
      List<String> shooterMemberNumbers = [];
      if (json.containsKey("shooterMemberNumbers")) {
        var memberNumbersList = json["shooterMemberNumbers"] as List;
        shooterMemberNumbers = memberNumbersList.map((e) => e.toString()).toList();
      }
      var squad = json["squad"] as String?;

      var registration = MatchRegistration(
        matchId: matchId,
        entryId: entryId,
        shooterName: shooterName,
        shooterClassificationName: shooterClassificationName,
        shooterDivisionName: shooterDivisionName,
        shooterMemberNumbers: shooterMemberNumbers,
        squad: squad,
      );

      return Result.ok(registration);
    } catch (e) {
      return Result.err(StringError("Failed to parse registration: $e"));
    }
  }
}

