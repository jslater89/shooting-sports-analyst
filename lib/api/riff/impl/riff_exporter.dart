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

/// Implementation of AbstractRiffExporter.
class RiffExporter implements AbstractRiffExporter {
  static const String mimeType = "application/x-riff";
  static const String compressedMimeType = "application/x-riff+gzip";

  @override
  Result<List<int>, ResultErr> exportRegistrations(List<MatchRegistration> registrations) {
    try {
      var json = toJson(registrations);
      var jsonString = jsonEncode(json);
      var jsonBytes = utf8.encode(jsonString);
      var compressed = gzip.encode(jsonBytes);
      return Result.ok(compressed);
    } catch (e) {
      return Result.err(StringError("Failed to export registrations: $e"));
    }
  }

  /// Converts a list of MatchRegistration objects to RIFF JSON format.
  Map<String, dynamic> toJson(List<MatchRegistration> registrations) {
    return {
      "format": "riff",
      "version": "1.0",
      "registrations": registrations.map((registration) => _registrationToJson(registration)).toList(),
    };
  }

  Map<String, dynamic> _registrationToJson(MatchRegistration registration) {
    var json = <String, dynamic>{
      "matchId": registration.matchId,
      "entryId": registration.entryId,
    };

    if (registration.shooterName != null) {
      json["shooterName"] = registration.shooterName;
    }
    if (registration.shooterClassificationName != null) {
      json["shooterClassificationName"] = registration.shooterClassificationName;
    }
    if (registration.shooterDivisionName != null) {
      json["shooterDivisionName"] = registration.shooterDivisionName;
    }
    if (registration.shooterMemberNumber != null) {
      json["shooterMemberNumber"] = registration.shooterMemberNumber;
    }
    if (registration.squad != null) {
      json["squad"] = registration.squad;
    }

    return json;
  }
}

