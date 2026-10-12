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

/// Implementation of AbstractRiffExporter.
class RiffExporter implements AbstractRiffExporter {
  static const String mimeType = "application/x-riff";
  static const String compressedMimeType = "application/x-riff+gzip";
  /// Current RIFF format version written by this exporter.
  static const String formatVersion = "1.1";

  @override
  Result<List<int>, ResultErr> exportMatch(FutureMatch match) {
    try {
      var json = toJson(match);
      var jsonString = jsonEncode(json);
      var jsonBytes = utf8.encode(jsonString);
      var compressed = gzip.encode(jsonBytes);
      return Result.ok(compressed);
    } catch (e) {
      return Result.err(StringError("Failed to export match: $e"));
    }
  }

  /// Converts a FutureMatch object to RIFF JSON format.
  Map<String, dynamic> toJson(FutureMatch match) {
    // Build match object
    var matchJson = <String, dynamic>{
      "matchId": match.matchId,
    };

    if (match.eventName.isNotEmpty) {
      matchJson["eventName"] = match.eventName;
    }
    if (match.date != practicalShootingZeroDate) {
      matchJson["date"] = programmerYmdFormat.format(match.date);
    }
    if (match.endDate != null) {
      matchJson["endDate"] = match.endDate!.toIso8601String();
    }
    if (match.sportName.isNotEmpty) {
      matchJson["sportName"] = match.sportName;
    }
    if (match.sourceCode != null && match.sourceCode!.isNotEmpty) {
      matchJson["sourceCode"] = match.sourceCode;
    }
    if (match.sourceIds != null && match.sourceIds!.isNotEmpty) {
      matchJson["sourceIds"] = match.sourceIds;
    }
    if (match.address1 != null && match.address1!.isNotEmpty) {
      matchJson["address1"] = match.address1;
    }
    if (match.address2 != null && match.address2!.isNotEmpty) {
      matchJson["address2"] = match.address2;
    }
    if (match.city != null && match.city!.isNotEmpty) {
      matchJson["city"] = match.city;
    }
    if (match.state != null && match.state!.isNotEmpty) {
      matchJson["state"] = match.state;
    }
    if (match.zip != null && match.zip!.isNotEmpty) {
      matchJson["zip"] = match.zip;
    }
    if (match.latitude != null) {
      matchJson["latitude"] = match.latitude;
    }
    if (match.longitude != null) {
      matchJson["longitude"] = match.longitude;
    }
    if (match.levelName != null && match.levelName!.isNotEmpty) {
      matchJson["levelName"] = match.levelName;
    }
    if (match.timezone != null && match.timezone!.isNotEmpty) {
      matchJson["timezone"] = match.timezone;
    }
    if (match.slug != null && match.slug!.isNotEmpty) {
      matchJson["slug"] = match.slug;
    }
    if (match.registrationOpenDate != null) {
      matchJson["registrationOpenDate"] = match.registrationOpenDate!.toIso8601String();
    }
    if (match.registrationCloseDate != null) {
      matchJson["registrationCloseDate"] = match.registrationCloseDate!.toIso8601String();
    }
    if (match.registrationStatus != null && match.registrationStatus!.isNotEmpty) {
      matchJson["registrationStatus"] = match.registrationStatus;
    }

    // Get registrations from the match
    var registrations = match.registrations.toList();

    return {
      "format": "riff",
      "version": formatVersion,
      "match": matchJson,
      "registrations": registrations.map((registration) => _registrationToJson(registration)).toList(),
    };
  }

  Map<String, dynamic> _registrationToJson(MatchRegistration registration) {
    var json = <String, dynamic>{
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
    if (registration.shooterMemberNumbers.isNotEmpty) {
      json["shooterMemberNumbers"] = registration.shooterMemberNumbers;
    }
    if (registration.squad != null) {
      json["squad"] = registration.squad;
    }

    return json;
  }
}

