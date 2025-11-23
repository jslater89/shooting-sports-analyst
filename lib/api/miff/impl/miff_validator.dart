/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/util.dart";

/// Implementation of AbstractMiffValidator.
class MiffValidator implements AbstractMiffValidator {
  @override
  Result<void, ResultErr> validate(List<int> miffBytes) {
    try {
      // Decompress gzip
      var decompressed = gzip.decode(miffBytes);
      var jsonString = utf8.decode(decompressed);
      var json = jsonDecode(jsonString) as Map<String, dynamic>;

      return validateJson(json);
    } on FormatException catch (e) {
      return Result.err(StringError("Invalid JSON: $e"));
    } catch (e) {
      return Result.err(StringError("Failed to decompress or parse MIFF file: $e"));
    }
  }

  @override
  Result<void, ResultErr> validateJson(Map<String, dynamic> jsonData) {
    // Validate root object
    var rootErr = _validateRoot(jsonData);
    if (rootErr != null) {
      return Result.err(rootErr);
    }

    var matchJson = jsonData["match"] as Map<String, dynamic>;
    var matchErr = _validateMatch(matchJson);
    if (matchErr != null) {
      return Result.err(matchErr);
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
    if (json["format"] != "miff") {
      return StringError("Field 'format' must be 'miff', got '${json["format"]}'");
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

    return null;
  }

  ResultErr? _validateMatch(Map<String, dynamic> json) {
    // Required fields
    if (!json.containsKey("name")) {
      return StringError("Match missing required field: name");
    }
    if (json["name"] is! String) {
      return StringError("Match field 'name' must be a string");
    }

    if (!json.containsKey("date")) {
      return StringError("Match missing required field: date");
    }
    if (json["date"] is! String) {
      return StringError("Match field 'date' must be a string");
    }
    var dateStr = json["date"] as String;
    if (!_isValidDate(dateStr)) {
      return StringError("Match field 'date' must be in ISO 8601 format (YYYY-MM-DD), got: $dateStr");
    }

    if (!json.containsKey("sport")) {
      return StringError("Match missing required field: sport");
    }
    if (json["sport"] is! String) {
      return StringError("Match field 'sport' must be a string");
    }

    if (!json.containsKey("stages")) {
      return StringError("Match missing required field: stages");
    }
    if (json["stages"] is! List) {
      return StringError("Match field 'stages' must be an array");
    }

    if (!json.containsKey("shooters")) {
      return StringError("Match missing required field: shooters");
    }
    if (json["shooters"] is! List) {
      return StringError("Match field 'shooters' must be an array");
    }

    // Optional fields
    if (json.containsKey("rawDate") && json["rawDate"] is! String) {
      return StringError("Match field 'rawDate' must be a string");
    }

    if (json.containsKey("sportDef") && json["sportDef"] is! Map) {
      return StringError("Match field 'sportDef' must be an object");
    }

    if (json.containsKey("level")) {
      var levelErr = _validateLevel(json["level"]);
      if (levelErr != null) {
        return StringError("Match level: ${levelErr.message}");
      }
    }

    if (json.containsKey("source")) {
      var sourceErr = _validateSource(json["source"]);
      if (sourceErr != null) {
        return StringError("Match source: ${sourceErr.message}");
      }
    }

    if (json.containsKey("localEvents")) {
      var localEventsErr = _validateLocalEvents(Map<String, dynamic>.from(json["localEvents"] as Map));
      if (localEventsErr != null) {
        return StringError("Match localEvents: ${localEventsErr.message}");
      }
    }

    // Validate stages array
    var stages = json["stages"] as List;
    var stageIds = <int>{};
    for (var i = 0; i < stages.length; i++) {
      var stage = stages[i];
      if (stage is! Map) {
        return StringError("Match stages[$i] must be an object");
      }
      var stageMap = stage as Map<String, dynamic>;
      var stageErr = _validateStage(stageMap, i);
      if (stageErr != null) {
        return StringError("Match stages[$i]: ${stageErr.message}");
      }
      var stageId = stageMap["id"] as int;
      if (stageIds.contains(stageId)) {
        return StringError("Match stages[$i]: Duplicate stage ID: $stageId");
      }
      stageIds.add(stageId);
    }

    // Validate shooters array
    var shooters = json["shooters"] as List;
    var shooterIds = <int>{};
    for (var i = 0; i < shooters.length; i++) {
      var shooter = shooters[i];
      if (shooter is! Map) {
        return StringError("Match shooters[$i] must be an object");
      }
      var shooterMap = shooter as Map<String, dynamic>;
      var shooterErr = _validateShooter(shooterMap, stageIds, i);
      if (shooterErr != null) {
        return StringError("Match shooters[$i]: ${shooterErr.message}");
      }
      var shooterId = shooterMap["id"] as int;
      if (shooterIds.contains(shooterId)) {
        return StringError("Match shooters[$i]: Duplicate shooter ID: $shooterId");
      }
      shooterIds.add(shooterId);
    }

    return null;
  }

  ResultErr? _validateLevel(Map<String, dynamic> json) {
    if (!json.containsKey("name")) {
      return StringError("Missing required field: name");
    }
    if (json["name"] is! String) {
      return StringError("Field 'name' must be a string");
    }

    if (json.containsKey("eventLevel")) {
      if (json["eventLevel"] is! String) {
        return StringError("Field 'eventLevel' must be a string");
      }
      var eventLevel = json["eventLevel"] as String;
      var validLevels = ["local", "regional", "area", "national", "international", "world"];
      if (!validLevels.contains(eventLevel)) {
        return StringError("Field 'eventLevel' must be one of: ${validLevels.join(", ")}, got: $eventLevel");
      }
    }

    return null;
  }

  ResultErr? _validateSource(Map<String, dynamic> json) {
    if (!json.containsKey("code")) {
      return StringError("Missing required field: code");
    }
    if (json["code"] is! String) {
      return StringError("Field 'code' must be a string");
    }

    if (!json.containsKey("ids")) {
      return StringError("Missing required field: ids");
    }
    if (json["ids"] is! List) {
      return StringError("Field 'ids' must be an array");
    }
    var ids = json["ids"] as List;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] is! String) {
        return StringError("Field 'ids[$i]' must be a string");
      }
    }

    return null;
  }

  ResultErr? _validateStage(Map<String, dynamic> json, int index) {
    // Required fields
    if (!json.containsKey("id")) {
      return StringError("Missing required field: id");
    }
    if (json["id"] is! int) {
      return StringError("Field 'id' must be an integer");
    }

    if (!json.containsKey("name")) {
      return StringError("Missing required field: name");
    }
    if (json["name"] is! String) {
      return StringError("Field 'name' must be a string");
    }

    if (!json.containsKey("scoring")) {
      return StringError("Missing required field: scoring");
    }
    if (json["scoring"] is! Map) {
      return StringError("Field 'scoring' must be an object");
    }
    var scoringErr = _validateScoring(Map<String, dynamic>.from(json["scoring"]));
    if (scoringErr != null) {
      return StringError("Scoring: ${scoringErr.message}");
    }

    // Optional fields
    if (json.containsKey("minRounds") && json["minRounds"] is! int) {
      return StringError("Field 'minRounds' must be an integer");
    }

    if (json.containsKey("maxPoints") && json["maxPoints"] is! int) {
      return StringError("Field 'maxPoints' must be an integer");
    }

    if (json.containsKey("classifier") && json["classifier"] is! bool) {
      return StringError("Field 'classifier' must be a boolean");
    }

    if (json.containsKey("classifierNumber") && json["classifierNumber"] is! String) {
      return StringError("Field 'classifierNumber' must be a string");
    }

    if (json.containsKey("sourceId") && json["sourceId"] is! String) {
      return StringError("Field 'sourceId' must be a string");
    }

    if (json.containsKey("overrides")) {
      var overridesErr = _validateOverrides(json["overrides"]);
      if (overridesErr != null) {
        return StringError("Overrides: ${overridesErr.message}");
      }
    }

    if (json.containsKey("variableEvents")) {
      var variableEventsErr = _validateVariableEvents(json["variableEvents"]);
      if (variableEventsErr != null) {
        return StringError("VariableEvents: ${variableEventsErr.message}");
      }
    }

    return null;
  }

  ResultErr? _validateScoring(Map<String, dynamic> json) {
    if (!json.containsKey("type")) {
      return StringError("Missing required field: type");
    }
    if (json["type"] is! String) {
      return StringError("Field 'type' must be a string");
    }
    var type = json["type"] as String;
    var validTypes = ["hitFactor", "timePlus", "points", "ignored", "timePlusChrono"];
    if (!validTypes.contains(type)) {
      return StringError("Field 'type' must be one of: ${validTypes.join(", ")}, got: $type");
    }

    if (json.containsKey("options")) {
      if (json["options"] is! Map) {
        return StringError("Field 'options' must be an object");
      }
      var optionsErr = _validateScoringOptions(Map<String, dynamic>.from(json["options"]), type);
      if (optionsErr != null) {
        return StringError("Options: ${optionsErr.message}");
      }
    }

    return null;
  }

  ResultErr? _validateScoringOptions(Map<String, dynamic> json, String scoringType) {
    if (scoringType == "timePlus") {
      if (json.containsKey("rawZeroWithEventsIsNonDnf") && json["rawZeroWithEventsIsNonDnf"] is! bool) {
        return StringError("Field 'rawZeroWithEventsIsNonDnf' must be a boolean");
      }
    } else if (scoringType == "points") {
      if (json.containsKey("highScoreBest") && json["highScoreBest"] is! bool) {
        return StringError("Field 'highScoreBest' must be a boolean");
      }
      if (json.containsKey("allowDecimal") && json["allowDecimal"] is! bool) {
        return StringError("Field 'allowDecimal' must be a boolean");
      }
    }

    return null;
  }

  ResultErr? _validateOverrides(Map<String, dynamic> json) {
    for (var entry in json.entries) {
      var eventName = entry.key;
      var overrideValue = entry.value;
      if (overrideValue is! Map) {
        return StringError("Override '$eventName' must be an object");
      }
      var override = Map<String, dynamic>.from(overrideValue);
      if (override.containsKey("points") && override["points"] is! int) {
        return StringError("Override '$eventName'.points must be an integer");
      }
      if (override.containsKey("time") && override["time"] is! num) {
        return StringError("Override '$eventName'.time must be a number");
      }
    }

    return null;
  }

  ResultErr? _validateVariableEvents(Map<String, dynamic> json) {
    var variableEventNames = <String>{};
    for (var entry in json.entries) {
      var baseName = entry.key;
      var eventsList = entry.value;
      if (eventsList is! List) {
        return StringError("VariableEvents '$baseName' must be an array");
      }
      var events = eventsList;
      for (var i = 0; i < events.length; i++) {
        var event = events[i];
        if (event is! Map) {
          return StringError("VariableEvents '$baseName'[$i] must be an object");
        }
        var eventMap = event as Map<String, dynamic>;
        var eventErr = _validateScoringEvent(eventMap, true);
        if (eventErr != null) {
          return StringError("VariableEvents '$baseName'[$i]: ${eventErr.message}");
        }
        // Check for unique names within the stage
        var eventName = eventMap["name"] as String;
        if (variableEventNames.contains(eventName)) {
          return StringError("VariableEvents '$baseName'[$i]: Duplicate variable event name: $eventName");
        }
        variableEventNames.add(eventName);
      }
    }

    return null;
  }

  ResultErr? _validateLocalEvents(Map<String, dynamic> json) {
    if (json.containsKey("bonuses")) {
      if (json["bonuses"] is! List) {
        return StringError("Field 'bonuses' must be an array");
      }
      var bonuses = json["bonuses"] as List;
      for (var i = 0; i < bonuses.length; i++) {
        var bonus = bonuses[i];
        if (bonus is! Map) {
          return StringError("LocalEvents.bonuses[$i] must be an object");
        }
        var bonusErr = _validateScoringEvent(Map<String, dynamic>.from(bonus), false);
        if (bonusErr != null) {
          return StringError("LocalEvents.bonuses[$i]: ${bonusErr.message}");
        }
      }
    }

    if (json.containsKey("penalties")) {
      if (json["penalties"] is! List) {
        return StringError("Field 'penalties' must be an array");
      }
      var penalties = json["penalties"] as List;
      for (var i = 0; i < penalties.length; i++) {
        var penalty = penalties[i];
        if (penalty is! Map) {
          return StringError("LocalEvents.penalties[$i] must be an object");
        }
        var penaltyErr = _validateScoringEvent(Map<String, dynamic>.from(penalty), false);
        if (penaltyErr != null) {
          return StringError("LocalEvents.penalties[$i]: ${penaltyErr.message}");
        }
      }
    }

    return null;
  }

  ResultErr? _validateScoringEvent(Map<String, dynamic> json, bool requireName) {
    if (requireName || json.containsKey("name")) {
      if (!json.containsKey("name")) {
        return StringError("Missing required field: name");
      }
      if (json["name"] is! String) {
        return StringError("Field 'name' must be a string");
      }
    }

    if (!json.containsKey("points")) {
      return StringError("Missing required field: points");
    }
    if (json["points"] is! int) {
      return StringError("Field 'points' must be an integer");
    }

    if (!json.containsKey("time")) {
      return StringError("Missing required field: time");
    }
    if (json["time"] is! num) {
      return StringError("Field 'time' must be a number");
    }

    if (json.containsKey("shortName") && json["shortName"] is! String) {
      return StringError("Field 'shortName' must be a string");
    }

    if (json.containsKey("bonus") && json["bonus"] is! bool) {
      return StringError("Field 'bonus' must be a boolean");
    }

    if (json.containsKey("bonusLabel") && json["bonusLabel"] is! String) {
      return StringError("Field 'bonusLabel' must be a string");
    }

    return null;
  }

  ResultErr? _validateShooter(Map<String, dynamic> json, Set<int> validStageIds, int index) {
    // Required fields
    if (!json.containsKey("id")) {
      return StringError("Missing required field: id");
    }
    if (json["id"] is! int) {
      return StringError("Field 'id' must be an integer");
    }

    if (!json.containsKey("firstName")) {
      return StringError("Missing required field: firstName");
    }
    if (json["firstName"] is! String) {
      return StringError("Field 'firstName' must be a string");
    }

    if (!json.containsKey("lastName")) {
      return StringError("Missing required field: lastName");
    }
    if (json["lastName"] is! String) {
      return StringError("Field 'lastName' must be a string");
    }

    if (!json.containsKey("memberNumber")) {
      return StringError("Missing required field: memberNumber");
    }
    if (json["memberNumber"] is! String) {
      return StringError("Field 'memberNumber' must be a string");
    }

    if (!json.containsKey("powerFactor")) {
      return StringError("Missing required field: powerFactor");
    }
    if (json["powerFactor"] is! String) {
      return StringError("Field 'powerFactor' must be a string");
    }

    if (!json.containsKey("scores")) {
      return StringError("Missing required field: scores");
    }
    if (json["scores"] is! Map) {
      return StringError("Field 'scores' must be an object");
    }

    // Optional fields
    if (json.containsKey("originalMemberNumber") && json["originalMemberNumber"] is! String) {
      return StringError("Field 'originalMemberNumber' must be a string");
    }

    if (json.containsKey("knownMemberNumbers")) {
      if (json["knownMemberNumbers"] is! List) {
        return StringError("Field 'knownMemberNumbers' must be an array");
      }
      var knownNumbers = json["knownMemberNumbers"] as List;
      for (var i = 0; i < knownNumbers.length; i++) {
        if (knownNumbers[i] is! String) {
          return StringError("Field 'knownMemberNumbers[$i]' must be a string");
        }
      }
    }

    if (json.containsKey("female") && json["female"] is! bool) {
      return StringError("Field 'female' must be a boolean");
    }

    if (json.containsKey("reentry") && json["reentry"] is! bool) {
      return StringError("Field 'reentry' must be a boolean");
    }

    if (json.containsKey("dq") && json["dq"] is! bool) {
      return StringError("Field 'dq' must be a boolean");
    }

    if (json.containsKey("squad") && json["squad"] is! int) {
      return StringError("Field 'squad' must be an integer");
    }

    if (json.containsKey("division") && json["division"] is! String) {
      return StringError("Field 'division' must be a string");
    }

    if (json.containsKey("classification") && json["classification"] is! String) {
      return StringError("Field 'classification' must be a string");
    }

    if (json.containsKey("ageCategory") && json["ageCategory"] is! String) {
      return StringError("Field 'ageCategory' must be a string");
    }

    if (json.containsKey("region") && json["region"] is! String) {
      return StringError("Field 'region' must be a string");
    }

    if (json.containsKey("regionSubdivision") && json["regionSubdivision"] is! String) {
      return StringError("Field 'regionSubdivision' must be a string");
    }

    if (json.containsKey("rawLocation") && json["rawLocation"] is! String) {
      return StringError("Field 'rawLocation' must be a string");
    }

    if (json.containsKey("sourceId") && json["sourceId"] is! String) {
      return StringError("Field 'sourceId' must be a string");
    }

    // Validate scores
    var scores = json["scores"] as Map;
    for (var entry in scores.entries) {
      var stageIdStr = entry.key;
      var scoreValue = entry.value;
      int? stageId;
      try {
        stageId = int.parse(stageIdStr);
      } catch (e) {
        return StringError("Scores key '$stageIdStr' must be a valid stage ID (integer as string)");
      }
      if (!validStageIds.contains(stageId)) {
        return StringError("Scores references unknown stage ID: $stageId");
      }
      if (scoreValue is! Map) {
        return StringError("Scores['$stageIdStr'] must be an object");
      }
      var scoreErr = _validateScore(Map<String, dynamic>.from(scoreValue), stageIdStr);
      if (scoreErr != null) {
        return StringError("Scores['$stageIdStr']: ${scoreErr.message}");
      }
    }

    // Validate supersededScores if present
    if (json.containsKey("supersededScores")) {
      if (json["supersededScores"] is! Map) {
        return StringError("Field 'supersededScores' must be an object");
      }
      var supersededScores = json["supersededScores"] as Map;
      for (var entry in supersededScores.entries) {
        var stageIdStr = entry.key;
        var scoreArray = entry.value;
        int? stageId;
        try {
          stageId = int.parse(stageIdStr);
        } catch (e) {
          return StringError("SupersededScores key '$stageIdStr' must be a valid stage ID (integer as string)");
        }
        if (!validStageIds.contains(stageId)) {
          return StringError("SupersededScores references unknown stage ID: $stageId");
        }
        if (scoreArray is! List) {
          return StringError("SupersededScores['$stageIdStr'] must be an array");
        }
        var scoresList = scoreArray;
        for (var i = 0; i < scoresList.length; i++) {
          var score = scoresList[i];
          if (score is! Map) {
            return StringError("SupersededScores['$stageIdStr'][$i] must be an object");
          }
          var scoreErr = _validateScore(Map<String, dynamic>.from(score), "$stageIdStr[$i]");
          if (scoreErr != null) {
            return StringError("SupersededScores['$stageIdStr'][$i]: ${scoreErr.message}");
          }
        }
      }
    }

    return null;
  }

  ResultErr? _validateScore(Map<String, dynamic> json, String context) {
    // Required fields
    if (!json.containsKey("time")) {
      return StringError("Missing required field: time");
    }
    if (json["time"] is! num) {
      return StringError("Field 'time' must be a number");
    }

    // Validate score representation - exactly one mode must be present:
    // Mode 1: Aggregated events (targetEvents required)
    // Mode 2: Per target events (targets required)
    // Mode 3: Overrides (totalPointsOverride and/or finalTimeOverride required)
    var hasTargetEvents = json.containsKey("targetEvents");
    var hasTargets = json.containsKey("targets");
    var hasTotalPointsOverride = json.containsKey("totalPointsOverride");
    var hasFinalTimeOverride = json.containsKey("finalTimeOverride");

    var hasAggregatedEvents = hasTargetEvents;
    var hasPerTargetEvents = hasTargets;
    var hasOverrides = hasTotalPointsOverride || hasFinalTimeOverride;

    // Must have exactly one mode
    var modeCount = (hasAggregatedEvents ? 1 : 0) + (hasPerTargetEvents ? 1 : 0) + (hasOverrides ? 1 : 0);
    if (modeCount == 0) {
      return StringError("Score must have one of: targetEvents (aggregated events), targets (per target events), or totalPointsOverride/finalTimeOverride (overrides)");
    }
    if (modeCount > 1) {
      return StringError("Score cannot have multiple representation modes (targetEvents, targets, and overrides are mutually exclusive)");
    }

    // targetEvents and targets are mutually exclusive
    if (hasTargetEvents && hasTargets) {
      return StringError("Score cannot have both 'targetEvents' (aggregated events) and 'targets' (per target events)");
    }

    // Validate targetEvents - required when using aggregated events mode
    if (hasAggregatedEvents) {
      if (json["targetEvents"] is! Map) {
        return StringError("Field 'targetEvents' must be an object");
      }
      var targetEventsErr = _validateEventCounts(Map<String, dynamic>.from(json["targetEvents"]));
      if (targetEventsErr != null) {
        return StringError("TargetEvents: ${targetEventsErr.message}");
      }
    } else if (hasPerTargetEvents) {
      // When using per target events, targetEvents must not be present
      if (hasTargetEvents) {
        return StringError("Field 'targetEvents' is forbidden when using 'targets' (per target events mode)");
      }
    }

    // Validate targets if present
    if (hasTargets) {
      if (json["targets"] is! List) {
        return StringError("Field 'targets' must be an array");
      }
      var targets = json["targets"] as List;
      for (var i = 0; i < targets.length; i++) {
        var target = targets[i];
        if (target is! Map) {
          return StringError("Field 'targets[$i]' must be an object");
        }
        var targetMap = Map<String, dynamic>.from(target);
        if (!targetMap.containsKey("targetNumber")) {
          return StringError("Field 'targets[$i].targetNumber' is required");
        }
        if (targetMap["targetNumber"] is! String) {
          return StringError("Field 'targets[$i].targetNumber' must be a string");
        }
        if (!targetMap.containsKey("events")) {
          return StringError("Field 'targets[$i].events' is required");
        }
        if (targetMap["events"] is! Map) {
          return StringError("Field 'targets[$i].events' must be an object");
        }
        var eventsErr = _validateEventCounts(Map<String, dynamic>.from(targetMap["events"]));
        if (eventsErr != null) {
          return StringError("Targets[$i].events: ${eventsErr.message}");
        }
      }
    }

    // Validate totalPointsOverride and finalTimeOverride if present
    if (hasTotalPointsOverride) {
      if (json["totalPointsOverride"] is! num) {
        return StringError("Field 'totalPointsOverride' must be a number");
      }
    }
    if (hasFinalTimeOverride) {
      if (json["finalTimeOverride"] is! num) {
        return StringError("Field 'finalTimeOverride' must be a number");
      }
    }

    // penaltyEvents is optional when using targetEvents or targets (may be omitted if all entries are zero), but forbidden when using overrides
    if (!hasOverrides) {
      if (json.containsKey("penaltyEvents")) {
        if (json["penaltyEvents"] is! Map) {
          return StringError("Field 'penaltyEvents' must be an object");
        }
        var penaltyEventsErr = _validateEventCounts(Map<String, dynamic>.from(json["penaltyEvents"]));
        if (penaltyEventsErr != null) {
          return StringError("PenaltyEvents: ${penaltyEventsErr.message}");
        }
      }
      // If penaltyEvents is missing, it's treated as an empty map (all zeros) - this is valid
    } else {
      // Forbidden when using overrides
      if (json.containsKey("penaltyEvents")) {
        return StringError("Field 'penaltyEvents' is forbidden when using 'totalPointsOverride' or 'finalTimeOverride'");
      }
    }

    // Optional fields
    if (json.containsKey("scoring")) {
      if (json["scoring"] is! Map) {
        return StringError("Field 'scoring' must be an object");
      }
      var scoringErr = _validateScoring(Map<String, dynamic>.from(json["scoring"]));
      if (scoringErr != null) {
        return StringError("Scoring: ${scoringErr.message}");
      }
    }

    if (json.containsKey("stringTimes")) {
      if (json["stringTimes"] is! List) {
        return StringError("Field 'stringTimes' must be an array");
      }
      var stringTimes = json["stringTimes"] as List;
      for (var i = 0; i < stringTimes.length; i++) {
        if (stringTimes[i] is! num) {
          return StringError("Field 'stringTimes[$i]' must be a number");
        }
      }
    }

    if (json.containsKey("dq") && json["dq"] is! bool) {
      return StringError("Field 'dq' must be a boolean");
    }

    if (json.containsKey("modified")) {
      if (json["modified"] is! String) {
        return StringError("Field 'modified' must be a string");
      }
      var modifiedStr = json["modified"] as String;
      try {
        DateTime.parse(modifiedStr);
      } catch (e) {
        return StringError("Field 'modified' must be a valid ISO 8601 timestamp, got: $modifiedStr");
      }
    }

    return null;
  }

  ResultErr? _validateEventCounts(Map<String, dynamic> json) {
    for (var entry in json.entries) {
      var eventName = entry.key;
      var count = entry.value;
      if (count is! int) {
        return StringError("EventCounts['$eventName'] must be an integer");
      }
      if (count < 0) {
        return StringError("EventCounts['$eventName'] must be non-negative, got: $count");
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
}
