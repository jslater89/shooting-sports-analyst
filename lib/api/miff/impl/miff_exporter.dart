/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/util.dart";

/// Implementation of AbstractMiffExporter.
class MiffExporter implements AbstractMiffExporter {
  @override
  Result<List<int>, ResultErr> exportMatch(ShootingMatch match) {
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

  /// Converts a ShootingMatch to MIFF JSON format.
  Map<String, dynamic> toJson(ShootingMatch match) {
    var matchJson = <String, dynamic>{
      "name": match.name,
      "date": _formatDate(match.date),
      "sport": match.sport.type.name,
    };

    if (match.rawDate.isNotEmpty) {
      matchJson["rawDate"] = match.rawDate;
    }

    if (match.level != null) {
      matchJson["level"] = {
        "name": match.level!.name,
        if (match.level!.eventLevel != EventLevel.local)
          "eventLevel": match.level!.eventLevel.name,
      };
    }

    if (match.sourceCode.isNotEmpty && match.sourceIds.isNotEmpty) {
      matchJson["source"] = {
        "code": match.sourceCode,
        "ids": match.sourceIds,
      };
    }

    matchJson["stages"] = match.stages.map((stage) => _stageToJson(stage)).toList();
    matchJson["shooters"] = match.shooters.map((shooter) => _shooterToJson(shooter, match.stages)).toList();

    if (match.localBonusEvents.isNotEmpty || match.localPenaltyEvents.isNotEmpty) {
      matchJson["localEvents"] = {};
      if (match.localBonusEvents.isNotEmpty) {
        matchJson["localEvents"]["bonuses"] = match.localBonusEvents.map((e) => _scoringEventToJson(e)).toList();
      }
      if (match.localPenaltyEvents.isNotEmpty) {
        matchJson["localEvents"]["penalties"] = match.localPenaltyEvents.map((e) => _scoringEventToJson(e)).toList();
      }
    }

    return {
      "format": "miff",
      "version": "1.0",
      "match": matchJson,
    };
  }

  Map<String, dynamic> _stageToJson(MatchStage stage) {
    var stageJson = <String, dynamic>{
      "id": stage.stageId,
      "name": stage.name,
      "scoring": _scoringToJson(stage.scoring),
    };

    if (stage.minRounds > 0) {
      stageJson["minRounds"] = stage.minRounds;
    }
    if (stage.maxPoints > 0) {
      stageJson["maxPoints"] = stage.maxPoints;
    }
    if (stage.classifier) {
      stageJson["classifier"] = true;
      if (stage.classifierNumber.isNotEmpty) {
        stageJson["classifierNumber"] = stage.classifierNumber;
      }
    }
    if (stage.sourceId != null) {
      stageJson["sourceId"] = stage.sourceId;
    }

    if (stage.scoringOverrides.isNotEmpty) {
      var overrides = <String, dynamic>{};
      for (var entry in stage.scoringOverrides.entries) {
        overrides[entry.key] = {
          if (entry.value.pointChangeOverride != null) "points": entry.value.pointChangeOverride,
          if (entry.value.timeChangeOverride != null) "time": entry.value.timeChangeOverride,
        };
      }
      stageJson["overrides"] = overrides;
    }

    if (stage.variableEvents.isNotEmpty) {
      var variableEvents = <String, List<Map<String, dynamic>>>{};
      for (var entry in stage.variableEvents.entries) {
        var baseName = entry.key;
        var eventsList = entry.value;
        // Assign distinct names to variable events
        var eventsWithNames = <Map<String, dynamic>>[];
        for (var event in eventsList) {
          var distinctName = _generateVariableEventName(event, eventsList);
          var eventJson = _scoringEventToJson(event);
          eventJson["name"] = distinctName; // Override with distinct name
          eventsWithNames.add(eventJson);
        }
        variableEvents[baseName] = eventsWithNames;
      }
      stageJson["variableEvents"] = variableEvents;
    }

    return stageJson;
  }

  Map<String, dynamic> _scoringToJson(StageScoring scoring) {
    switch (scoring) {
      case HitFactorScoring():
        return {"type": "hitFactor"};
      case TimePlusScoring():
        var result = <String, dynamic>{"type": "timePlus"};
        if (scoring.rawZeroWithEventsIsNonDnf) {
          result["options"] = {"rawZeroWithEventsIsNonDnf": true};
        }
        return result;
      case PointsScoring():
        var result = <String, dynamic>{"type": "points"};
        var options = <String, dynamic>{};
        if (!scoring.highScoreBest) {
          options["highScoreBest"] = false;
        }
        if (scoring.allowDecimal) {
          options["allowDecimal"] = true;
        }
        if (options.isNotEmpty) {
          result["options"] = options;
        }
        return result;
      case IgnoredScoring():
        return {"type": "ignored"};
      case TimePlusChronoScoring():
        return {"type": "timePlusChrono"};
    }
  }

  Map<String, dynamic> _scoringEventToJson(ScoringEvent event) {
    var json = <String, dynamic>{
      "name": event.name,
      "points": event.pointChange,
      "time": event.timeChange,
    };

    if (event.shortName.isNotEmpty) {
      json["shortName"] = event.shortName;
    }
    if (event.bonus) {
      json["bonus"] = true;
      if (event.bonusLabel != "X") {
        json["bonusLabel"] = event.bonusLabel;
      }
    }

    return json;
  }

  Map<String, dynamic> _shooterToJson(MatchEntry shooter, List<MatchStage> stages) {
    var shooterJson = <String, dynamic>{
      "id": shooter.entryId,
      "firstName": shooter.firstName,
      "lastName": shooter.lastName,
      "memberNumber": shooter.memberNumber,
      "powerFactor": shooter.powerFactor.name,
    };

    if (shooter.originalMemberNumber.isNotEmpty && shooter.originalMemberNumber != shooter.memberNumber) {
      shooterJson["originalMemberNumber"] = shooter.originalMemberNumber;
    }
    if (shooter.knownMemberNumbers.isNotEmpty) {
      shooterJson["knownMemberNumbers"] = shooter.knownMemberNumbers.toList();
    }
    if (shooter.female) {
      shooterJson["female"] = true;
    }
    if (shooter.reentry) {
      shooterJson["reentry"] = true;
    }
    if (shooter.dq) {
      shooterJson["dq"] = true;
    }
    if (shooter.squad != null) {
      shooterJson["squad"] = shooter.squad;
    }
    if (shooter.division != null) {
      shooterJson["division"] = shooter.division!.name;
    }
    if (shooter.classification != null) {
      shooterJson["classification"] = shooter.classification!.name;
    }
    if (shooter.ageCategory != null) {
      shooterJson["ageCategory"] = shooter.ageCategory!.name;
    }
    if (shooter.region != null) {
      shooterJson["region"] = shooter.region;
    }
    if (shooter.regionSubdivision != null) {
      shooterJson["regionSubdivision"] = shooter.regionSubdivision;
    }
    if (shooter.rawLocation != null) {
      shooterJson["rawLocation"] = shooter.rawLocation;
    }
    if (shooter.sourceId != null) {
      shooterJson["sourceId"] = shooter.sourceId;
    }

    // Convert scores map (keyed by MatchStage) to map keyed by stage ID
    var scoresJson = <String, dynamic>{};
    for (var entry in shooter.scores.entries) {
      var stageId = entry.key.stageId.toString();
      scoresJson[stageId] = _scoreToJson(entry.value, entry.key);
    }
    shooterJson["scores"] = scoresJson;

    // TODO: Handle supersededScores when that data is available in ShootingMatch
    // For now, we don't have access to superseded scores in the match structure

    return shooterJson;
  }

  Map<String, dynamic> _scoreToJson(RawScore score, MatchStage stage) {
    var scoreJson = <String, dynamic>{
      "time": score.rawTime,
      "targetEvents": _eventCountsToJson(score.targetEvents, stage),
      "penaltyEvents": _eventCountsToJson(score.penaltyEvents, stage),
    };

    if (score.scoring.dbString != stage.scoring.dbString) {
      scoreJson["scoring"] = _scoringToJson(score.scoring);
    }
    if (score.stringTimes.isNotEmpty) {
      scoreJson["stringTimes"] = score.stringTimes;
    }
    if (score.dq) {
      scoreJson["dq"] = true;
    }
    if (score.modified != null) {
      scoreJson["modified"] = score.modified!.toIso8601String();
    }

    return scoreJson;
  }

  Map<String, int> _eventCountsToJson(Map<ScoringEvent, int> events, MatchStage stage) {
    var result = <String, int>{};

    // Build a map from (baseName, pointChange, timeChange) to distinct name for variable events
    // This allows us to match score events (which have base names) to variable events (which may have distinct names)
    var variableEventMap = <String, Map<String, String>>{}; // baseName -> (key: "$pointChange:$timeChange", value: distinctName)
    for (var entry in stage.variableEvents.entries) {
      var baseName = entry.key;
      var variableList = entry.value;
      var nameMap = <String, String>{};
      for (var event in variableList) {
        // Generate the same distinct name we used when exporting the stage definition
        var distinctName = _generateVariableEventName(event, variableList);
        // Use pointChange and timeChange as the key to match score events
        var key = "${event.pointChange}:${event.timeChange}";
        nameMap[key] = distinctName;
      }
      variableEventMap[baseName] = nameMap;
    }

    for (var entry in events.entries) {
      var event = entry.key;
      var count = entry.value;

      // Check if this event matches any variable event in the stage
      // Match by base name and values (pointChange, timeChange)
      String? distinctName;
      if (variableEventMap.containsKey(event.name)) {
        var nameMap = variableEventMap[event.name]!;
        var key = "${event.pointChange}:${event.timeChange}";
        distinctName = nameMap[key];
      }

      if (distinctName != null) {
        // This is a variable event - use the distinct name
        result[distinctName] = count;
      } else {
        // Standard event - use the event name
        result[event.name] = count;
      }
    }

    return result;
  }

  /// Generates a distinct name for a variable event.
  ///
  /// If there are multiple events with the same base name but different values,
  /// generates names like "X-0.5", "X-1.0", or "X-5--1.0" to ensure uniqueness.
  String _generateVariableEventName(ScoringEvent event, List<ScoringEvent> allEventsWithSameName) {
    if (allEventsWithSameName.length == 1) {
      // Only one event with this name, use the base name
      return event.name;
    }

    // Multiple events - need to distinguish by values
    // Check if we need to include both points and time, or just one
    var hasPointVariation = allEventsWithSameName.any((e) => e.pointChange != event.pointChange);
    var hasTimeVariation = allEventsWithSameName.any((e) => e.timeChange != event.timeChange);

    if (hasPointVariation && hasTimeVariation) {
      return "${event.name}-${event.pointChange}-${event.timeChange}";
    } else if (hasTimeVariation) {
      return "${event.name}-${event.timeChange}";
    } else if (hasPointVariation) {
      return "${event.name}-${event.pointChange}";
    } else {
      // No variation (shouldn't happen, but fallback)
      return event.name;
    }
  }

  String _formatDate(DateTime date) {
    return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}
