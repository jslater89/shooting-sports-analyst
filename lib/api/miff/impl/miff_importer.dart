/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";
import "dart:io";

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/data/sport/builtins/registry.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/util.dart";

class _ImportState {
  Sport? preexistingSport;
  Map<int, MatchStage> stages = {};
  Map<int, Map<String, ScoringEvent>> stageVariableEventMap = {};

  void addStage(int stageId, MatchStage stage) {
    stages[stageId] = stage;
  }

  MatchStage? getStage(int stageId) {
    return stages[stageId];
  }

  void addVariableEvent(int stageId, String nameInFile, ScoringEvent event) {
    stageVariableEventMap[stageId] ??= {};
    stageVariableEventMap[stageId]![nameInFile] = event;
  }

  ScoringEvent? getVariableEvent(int stageId, String nameInFile) {
    return stageVariableEventMap[stageId]?[nameInFile];
  }

  Map<String, ScoringEvent> getVariableEventMap(int stageId) {
    return stageVariableEventMap[stageId] ?? {};
  }

  List<ScoringEvent> localBonusEvents = [];
  List<ScoringEvent> localPenaltyEvents = [];

  void addLocalBonusEvent(ScoringEvent event) {
    localBonusEvents.add(event);
  }

  void addLocalPenaltyEvent(ScoringEvent event) {
    localPenaltyEvents.add(event);
  }

  List<ScoringEvent> getLocalEvents() {
    return [...localBonusEvents, ...localPenaltyEvents];
  }

  ScoringEvent? lookupPreexistingEvent(String name, String powerFactorName) {
    if(preexistingSport == null) {
      return null;
    }
    var powerFactor = preexistingSport!.powerFactors.lookupByName(powerFactorName);
    if(powerFactor == null) {
      return null;
    }
    return powerFactor.allEvents.lookupByName(name);
  }
}

/// Implementation of AbstractMiffImporter.
class MiffImporter implements AbstractMiffImporter {
  @override
  Result<ShootingMatch, ResultErr> importMatch(List<int> miffBytes) {
    try {
      var importState = _ImportState();
      // Decompress gzip
      var decompressed = gzip.decode(miffBytes);
      var jsonString = utf8.decode(decompressed);
      var json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate format
      if (json["format"] != "miff") {
        return Result.err(StringError("Invalid format: expected 'miff', got '${json["format"]}'"));
      }

      // Validate version
      var version = json["version"] as String?;
      if (version == null || !version.startsWith("1.")) {
        return Result.err(StringError("Unsupported version: $version"));
      }

      // Parse match
      var matchJson = json["match"] as Map<String, dynamic>;
      var match = parseMatch(matchJson, importState);
      if (match.isErr()) {
        return Result.err(match.unwrapErr());
      }

      return Result.ok(match.unwrap());
    } catch (e) {
      return Result.err(StringError("Failed to import match: $e"));
    }
  }

  Result<ShootingMatch, ResultErr> parseMatch(Map<String, dynamic> json, _ImportState importState) {
    try {
      // Parse sport
      var sportName = json["sport"] as String;
      var sport = _lookupSport(sportName);
      if (sport == null) {
        return Result.err(StringError("Unknown sport: $sportName"));
      }

      // Parse date
      var dateStr = json["date"] as String;
      var date = _parseDate(dateStr);
      if (date == null) {
        return Result.err(StringError("Invalid date format: $dateStr"));
      }

      var rawDate = json["rawDate"] as String? ?? "";

      // Parse level
      MatchLevel? level;
      if (json.containsKey("level")) {
        var levelJson = json["level"] as Map<String, dynamic>;
        var levelName = levelJson["name"] as String;
        var eventLevelStr = levelJson["eventLevel"] as String?;
        EventLevel? eventLevel;
        if (eventLevelStr != null) {
          try {
            eventLevel = EventLevel.values.firstWhere((e) => e.name == eventLevelStr);
          } catch (e) {
            return Result.err(StringError("Invalid event level: $eventLevelStr"));
          }
        }
        level = sport.eventLevels.lookupByName(levelName) ??
                (eventLevel != null ? MatchLevel(name: levelName, shortName: levelName, eventLevel: eventLevel) : null);
      }

      // Parse source
      String sourceCode = "";
      List<String> sourceIds = [];
      if (json.containsKey("source")) {
        var sourceJson = json["source"] as Map<String, dynamic>;
        sourceCode = sourceJson["code"] as String;
        sourceIds = (sourceJson["ids"] as List).map((e) => e.toString()).toList();
      }

      // Parse stages
      var stagesJson = json["stages"] as List;
      var stages = <MatchStage>[];
      for (var stageJson in stagesJson) {
        var stage = _parseStage(stageJson as Map<String, dynamic>, sport, importState);
        if (stage.isErr()) {
          return Result.err(stage.unwrapErr());
        }
        stages.add(stage.unwrap());
      }

      // Parse local events
      var localBonusEvents = <ScoringEvent>[];
      var localPenaltyEvents = <ScoringEvent>[];
      if (json.containsKey("localEvents")) {
        var localEventsJson = json["localEvents"] as Map<String, dynamic>;
        if (localEventsJson.containsKey("bonuses")) {
          var bonusesJson = localEventsJson["bonuses"] as List;
          for (var eventJson in bonusesJson) {
            var event = _parseScoringEvent(eventJson as Map<String, dynamic>, importState);
            localBonusEvents.add(event);
          }
        }
        if (localEventsJson.containsKey("penalties")) {
          var penaltiesJson = localEventsJson["penalties"] as List;
          for (var eventJson in penaltiesJson) {
            var event = _parseScoringEvent(eventJson as Map<String, dynamic>, importState);
            localPenaltyEvents.add(event);
          }
        }
      }

      // Parse shooters (after local events so we can use them in score parsing)
      var shootersJson = json["shooters"] as List;
      var shooters = <MatchEntry>[];
      for (var shooterJson in shootersJson) {
        var shooter = _parseShooter(shooterJson as Map<String, dynamic>, sport, stages, importState);
        if (shooter.isErr()) {
          return Result.err(shooter.unwrapErr());
        }
        shooters.add(shooter.unwrap());
      }

      var match = ShootingMatch(
        name: json["name"] as String,
        rawDate: rawDate,
        date: date,
        level: level,
        sport: sport,
        stages: stages,
        shooters: shooters,
        sourceCode: sourceCode,
        sourceIds: sourceIds,
        localBonusEvents: localBonusEvents,
        localPenaltyEvents: localPenaltyEvents,
      );

      return Result.ok(match);
    } catch (e) {
      return Result.err(StringError("Failed to parse match: $e"));
    }
  }

  Sport? _lookupSport(String sportName) {
    // Try to find sport by type name
    try {
      var sportType = SportType.values.firstWhere((t) => t.name == sportName);
      var registry = SportRegistry();
      return registry.availableSports.firstWhereOrNull((s) => s.type == sportType);
    } catch (e) {
      return null;
    }
  }

  DateTime? _parseDate(String dateStr) {
    try {
      // Parse YYYY-MM-DD format
      var parts = dateStr.split("-");
      if (parts.length != 3) return null;
      var year = int.parse(parts[0]);
      var month = int.parse(parts[1]);
      var day = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  Result<MatchStage, ResultErr> _parseStage(Map<String, dynamic> json, Sport sport, _ImportState importState) {
    try {
      var stageId = json["id"] as int;
      var name = json["name"] as String;
      var scoringJson = json["scoring"] as Map<String, dynamic>;
      var scoring = _parseScoring(scoringJson);
      if (scoring == null) {
        return Result.err(StringError("Invalid scoring type: ${scoringJson["type"]}"));
      }

      var stage = MatchStage(
        stageId: stageId,
        name: name,
        scoring: scoring,
        minRounds: json["minRounds"] as int? ?? 0,
        maxPoints: json["maxPoints"] as int? ?? 0,
        classifier: json["classifier"] as bool? ?? false,
        classifierNumber: json["classifierNumber"] as String? ?? "",
        sourceId: json["sourceId"] as String?,
      );

      // Parse overrides
      if (json.containsKey("overrides")) {
        var overridesJson = json["overrides"] as Map<String, dynamic>;
        var overrides = <String, ScoringEventOverride>{};
        for (var entry in overridesJson.entries) {
          var overrideJson = entry.value as Map<String, dynamic>;
          overrides[entry.key] = ScoringEventOverride(
            name: entry.key,
            pointChangeOverride: overrideJson["points"] as int?,
            timeChangeOverride: (overrideJson["time"] as num?)?.toDouble(),
          );
        }
        stage.scoringOverrides = overrides;
      }

      // Parse variable events
      if (json.containsKey("variableEvents")) {
        var variableEventsJson = json["variableEvents"] as Map<String, dynamic>;
        var variableEvents = <String, List<ScoringEvent>>{};
        for (var entry in variableEventsJson.entries) {
          var baseName = entry.key;
          var eventsJson = entry.value as List;
          var events = <ScoringEvent>[];
          for (var eventJson in eventsJson) {
            var nameInFile = eventJson["name"] as String;
            var event = _parseScoringEvent(eventJson as Map<String, dynamic>, importState, baseName: baseName);
            importState.addVariableEvent(stageId, nameInFile, event);
            events.add(event);
          }
          variableEvents[entry.key] = events;
        }
        stage.variableEvents = variableEvents;
      }

      return Result.ok(stage);
    } catch (e) {
      return Result.err(StringError("Failed to parse stage: $e"));
    }
  }

  StageScoring? _parseScoring(Map<String, dynamic> json) {
    var type = json["type"] as String;
    var options = json["options"] as Map<String, dynamic>?;

    switch (type) {
      case "hitFactor":
        return const HitFactorScoring();
      case "timePlus":
        var rawZeroWithEventsIsNonDnf = options?["rawZeroWithEventsIsNonDnf"] as bool? ?? false;
        return TimePlusScoring(rawZeroWithEventsIsNonDnf: rawZeroWithEventsIsNonDnf);
      case "points":
        var highScoreBest = options?["highScoreBest"] as bool? ?? true;
        var allowDecimal = options?["allowDecimal"] as bool? ?? false;
        return PointsScoring(highScoreBest: highScoreBest, allowDecimal: allowDecimal);
      case "ignored":
        return const IgnoredScoring();
      case "timePlusChrono":
        return const TimePlusChronoScoring();
      default:
        return null;
    }
  }

  ScoringEvent _parseScoringEvent(Map<String, dynamic> json, _ImportState importState, {String? baseName}) {
    return ScoringEvent(
      baseName ?? json["name"] as String,
      shortName: json["shortName"] as String? ?? "",
      pointChange: json["points"] as int,
      timeChange: (json["time"] as num).toDouble(),
      bonus: json["bonus"] as bool? ?? false,
      bonusLabel: json["bonusLabel"] as String? ?? "X",
    );
  }

  Result<MatchEntry, ResultErr> _parseShooter(
    Map<String, dynamic> json,
    Sport sport,
    List<MatchStage> stages,
    _ImportState importState,
  ) {
    try {
      var entryId = json["id"] as int;
      var firstName = json["firstName"] as String;
      var lastName = json["lastName"] as String;
      var memberNumber = json["memberNumber"] as String;
      var powerFactorName = json["powerFactor"] as String;
      var powerFactor = sport.powerFactors.lookupByName(powerFactorName);
      if (powerFactor == null) {
        return Result.err(StringError("Unknown power factor: $powerFactorName"));
      }

      var shooter = MatchEntry(
        entryId: entryId,
        firstName: firstName,
        lastName: lastName,
        memberNumber: memberNumber,
        powerFactor: powerFactor,
        division: sport.hasDivisions ? sport.divisions.lookupByName(json["division"] as String?) : null,
        classification: sport.hasClassifications ? sport.classifications.lookupByName(json["classification"] as String?) : null,
        ageCategory: sport.ageCategories.lookupByName(json["ageCategory"] as String?),
        female: json["female"] as bool? ?? false,
        reentry: json["reentry"] as bool? ?? false,
        dq: json["dq"] as bool? ?? false,
        squad: json["squad"] as int?,
        region: json["region"] as String?,
        regionSubdivision: json["regionSubdivision"] as String?,
        rawLocation: json["rawLocation"] as String?,
        sourceId: json["sourceId"] as String?,
        scores: {},
      );

      if (json.containsKey("originalMemberNumber")) {
        shooter.originalMemberNumber = json["originalMemberNumber"] as String;
      }
      if (json.containsKey("knownMemberNumbers")) {
        shooter.knownMemberNumbers = (json["knownMemberNumbers"] as List).map((e) => e.toString()).toSet();
      }

      // Parse scores
      var scoresJson = json["scores"] as Map<String, dynamic>;
      var stageMap = {for (var s in stages) s.stageId: s};

      for (var entry in scoresJson.entries) {
        var stageId = int.parse(entry.key);
        var stage = stageMap[stageId];
        if (stage == null) {
          return Result.err(StringError("Unknown stage ID: $stageId"));
        }

        var scoreJson = entry.value as Map<String, dynamic>;
        var score = _parseScore(scoreJson, stage, sport, powerFactor, importState);
        if (score.isErr()) {
          return Result.err(score.unwrapErr());
        }

        shooter.scores[stage] = score.unwrap();
      }

      // TODO: Parse supersededScores when that data structure is available

      return Result.ok(shooter);
    } catch (e) {
      return Result.err(StringError("Failed to parse shooter: $e"));
    }
  }

  Result<RawScore, ResultErr> _parseScore(
    Map<String, dynamic> json,
    MatchStage stage,
    Sport sport,
    PowerFactor powerFactor,
    _ImportState importState,
  ) {
    try {
      var time = (json["time"] as num).toDouble();
      var scoring = stage.scoring;
      if (json.containsKey("scoring")) {
        var scoringJson = json["scoring"] as Map<String, dynamic>;
        var parsedScoring = _parseScoring(scoringJson);
        if (parsedScoring == null) {
          return Result.err(StringError("Invalid scoring type in score"));
        }
        scoring = parsedScoring;
      }

      // Parse target events
      var targetEventsJson = json["targetEvents"] as Map<String, dynamic>;
      var targetEvents = _parseEventCounts(targetEventsJson, stage, powerFactor, importState, true);

      // Parse penalty events
      var penaltyEventsJson = json["penaltyEvents"] as Map<String, dynamic>;
      var penaltyEvents = _parseEventCounts(penaltyEventsJson, stage, powerFactor, importState, false);

      var score = RawScore(
        scoring: scoring,
        rawTime: time,
        targetEvents: targetEvents,
        penaltyEvents: penaltyEvents,
        stringTimes: (json["stringTimes"] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
        dq: json["dq"] as bool? ?? false,
        modified: json["modified"] != null ? DateTime.parse(json["modified"] as String) : null,
      );

      return Result.ok(score);
    } catch (e) {
      return Result.err(StringError("Failed to parse score: $e"));
    }
  }

  Map<ScoringEvent, int> _parseEventCounts(
    Map<String, dynamic> json,
    MatchStage stage,
    PowerFactor powerFactor,
    _ImportState importState,
    bool isTarget,
  ) {
    var result = <ScoringEvent, int>{};

    var variableEventMap = importState.getVariableEventMap(stage.stageId);

    // Build lookup map for local events
    var localEventMap = <String, ScoringEvent>{};
    for (var event in importState.getLocalEvents()) {
      localEventMap[event.name] = event;
    }

    for (var entry in json.entries) {
      var eventName = entry.key;
      var count = entry.value as int;

      ScoringEvent? event;

      // First check variable events
      if (variableEventMap.containsKey(eventName)) {
        event = variableEventMap[eventName];
      } else if (localEventMap.containsKey(eventName)) {
        // Check match-local events
        event = localEventMap[eventName];
      } else {
        // Check standard sport events
        if (isTarget) {
          event = powerFactor.targetEvents.lookupByName(eventName);
        } else {
          event = powerFactor.penaltyEvents.lookupByName(eventName);
        }
      }

      if (event != null) {
        result[event] = count;
      }
    }

    return result;
  }
}
