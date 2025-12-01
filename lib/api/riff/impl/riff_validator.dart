/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:shooting_sports_analyst/api/riff/riff.dart";
import "package:shooting_sports_analyst/util.dart";

/// Implementation of AbstractRiffValidator.
class RiffValidator implements AbstractRiffValidator {
  @override
  Result<void, ResultErr> validate(List<int> riffBytes) {
    try {
      // Decompress gzip
      var decompressed = gzip.decode(riffBytes);
      var jsonString = utf8.decode(decompressed);
      var json = jsonDecode(jsonString) as Map<String, dynamic>;

      return validateJson(json);
    } on FormatException catch (e) {
      return Result.err(StringError("Invalid JSON: $e"));
    } catch (e) {
      return Result.err(StringError("Failed to decompress or parse RIFF file: $e"));
    }
  }

  @override
  Result<void, ResultErr> validateJson(Map<String, dynamic> jsonData) {
    // Validate root object
    var rootErr = _validateRoot(jsonData);
    if (rootErr != null) {
      return Result.err(rootErr);
    }

    // Validate match object
    var matchJson = Map<String, dynamic>.from(jsonData["match"] as Map);
    var matchErr = _validateMatch(matchJson);
    if (matchErr != null) {
      return Result.err(matchErr);
    }

    var registrationsJson = jsonData["registrations"] as List;
    var registrationsErr = _validateRegistrations(registrationsJson);
    if (registrationsErr != null) {
      return Result.err(registrationsErr);
    }

    return Result.ok(null);
  }

  ResultErr? _validateRoot(Map<String, dynamic> json) {
    // Check required fields
    if (!json.containsKey("format")) {
      return StringError("Missing required field: format");
    }
    if (json["format"] is! String) {
      return StringError("Field 'format' must be a string");
    }
    if (json["format"] != "riff") {
      return StringError("Field 'format' must be 'riff', got '${json["format"]}'");
    }

    if (!json.containsKey("version")) {
      return StringError("Missing required field: version");
    }
    if (json["version"] is! String) {
      return StringError("Field 'version' must be a string");
    }
    var version = json["version"] as String;
    if (!version.startsWith("1.")) {
      return StringError("Unsupported version: $version (expected version starting with '1.')");
    }

    if (!json.containsKey("match")) {
      return StringError("Missing required field: match");
    }
    if (json["match"] is! Map) {
      return StringError("Field 'match' must be an object");
    }

    if (!json.containsKey("registrations")) {
      return StringError("Missing required field: registrations");
    }
    if (json["registrations"] is! List) {
      return StringError("Field 'registrations' must be an array");
    }

    return null;
  }

  ResultErr? _validateMatch(Map<String, dynamic> json) {
    // Required fields
    if (!json.containsKey("matchId")) {
      return StringError("Missing required field: matchId");
    }
    if (json["matchId"] is! String) {
      return StringError("Field 'matchId' must be a string");
    }

    // Optional fields
    if (json.containsKey("eventName") && json["eventName"] is! String) {
      return StringError("Field 'eventName' must be a string");
    }

    if (json.containsKey("date") && json["date"] is! String) {
      return StringError("Field 'date' must be a string");
    }
    if (json.containsKey("date")) {
      var dateStr = json["date"] as String;
      if (!_isValidDate(dateStr)) {
        return StringError("Field 'date' must be in ISO 8601 format (YYYY-MM-DD), got: $dateStr");
      }
    }

    if (json.containsKey("sportName") && json["sportName"] is! String) {
      return StringError("Field 'sportName' must be a string");
    }

    if (json.containsKey("sourceCode") && json["sourceCode"] is! String) {
      return StringError("Field 'sourceCode' must be a string");
    }

    if (json.containsKey("sourceIds")) {
      if (json["sourceIds"] is! List) {
        return StringError("Field 'sourceIds' must be an array");
      }
      var sourceIds = json["sourceIds"] as List;
      for (var i = 0; i < sourceIds.length; i++) {
        if (sourceIds[i] is! String) {
          return StringError("Field 'sourceIds[$i]' must be a string");
        }
      }
    }

    return null;
  }

  bool _isValidDate(String dateStr) {
    try {
      var parts = dateStr.split("-");
      if (parts.length != 3) return false;
      var year = int.parse(parts[0]);
      var month = int.parse(parts[1]);
      var day = int.parse(parts[2]);
      if (month < 1 || month > 12) return false;
      if (day < 1 || day > 31) return false;
      // Basic validation - could be more strict
      DateTime(year, month, day);
      return true;
    } catch (e) {
      return false;
    }
  }

  ResultErr? _validateRegistrations(List registrationsJson) {
    for (var i = 0; i < registrationsJson.length; i++) {
      var registration = registrationsJson[i];
      if (registration is! Map) {
        return StringError("Registrations[$i] must be an object");
      }
      var registrationMap = Map<String, dynamic>.from(registration);
      var registrationErr = _validateRegistration(registrationMap, i);
      if (registrationErr != null) {
        return StringError("Registrations[$i]: ${registrationErr.message}");
      }
    }

    return null;
  }

  ResultErr? _validateRegistration(Map<String, dynamic> json, int index) {
    // Required fields
    if (!json.containsKey("entryId")) {
      return StringError("Missing required field: entryId");
    }
    if (json["entryId"] is! String) {
      return StringError("Field 'entryId' must be a string");
    }

    // Optional fields
    if (json.containsKey("shooterName") && json["shooterName"] is! String) {
      return StringError("Field 'shooterName' must be a string");
    }

    if (json.containsKey("shooterClassificationName") && json["shooterClassificationName"] is! String) {
      return StringError("Field 'shooterClassificationName' must be a string");
    }

    if (json.containsKey("shooterDivisionName") && json["shooterDivisionName"] is! String) {
      return StringError("Field 'shooterDivisionName' must be a string");
    }

    if (json.containsKey("shooterMemberNumbers")) {
      if (json["shooterMemberNumbers"] is! List) {
        return StringError("Field 'shooterMemberNumbers' must be an array");
      }
      var shooterMemberNumbers = json["shooterMemberNumbers"] as List;
      for (var i = 0; i < shooterMemberNumbers.length; i++) {
        if (shooterMemberNumbers[i] is! String) {
          return StringError("Field 'shooterMemberNumbers[$i]' must be a string");
        }
      }
    }

    if (json.containsKey("squad") && json["squad"] is! String) {
      return StringError("Field 'squad' must be a string");
    }

    return null;
  }
}

