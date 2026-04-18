/*
 * Copyright Jay Slater 2024.
 * All rights reserved.
 */

import 'dart:convert';

import 'package:shooting_sports_analyst/data/location_normalizer.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/bare_match_def.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/hitfactor/hitfactor_matchdef.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/hitfactor/hitfactor_scorelogs.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/hitfactor/hitfactor_scores.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';
import 'package:shooting_sports_analyst/data/source/psc/psc_options.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/pcsl.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("HitFactorConverter");

class HitFactorConverter {
  static (HitFactorMatchDef, HitFactorScores) matchInfoFromBareMatchDef(BareMatchDef matchDef) {
    if(matchDef.matchDefJson.isEmpty || matchDef.scoresJson.isEmpty) {
      throw ArgumentError("matchDefJson and scoresJson must be non-empty");
    }

    return (
      HitFactorMatchDef.fromJson(matchDef.matchDefJson),
      HitFactorScores.fromJson(matchDef.scoresJson),
    );
  }

  static Result<ShootingMatch, MatchSourceError> matchFromBareMatchDef(BareMatchDef bareMatchDef, {PscMatchFetchOptions? options}) {
    final (matchDef, scores) = HitFactorConverter.matchInfoFromBareMatchDef(bareMatchDef);

    final orderedSports = hitFactorSubtypeSportOrder(bareMatchDef.name, bareMatchDef.matchSubtype);
    Sport? sport;
    if(options?.parseAsSport != null) {
      sport = options!.parseAsSport;
    }
    else {
      sport = firstMatchingSport(orderedSports, divisions: matchDef.divisions, fuzzyMatching: options?.fuzzyHitFactorDivisionMatching ?? false);
    }

    if(sport == null) {
      _log.w("Unable to process match: ${bareMatchDef.name} without a sport");
      return Result.err(FormatError(StringError("No sport found for match: ${bareMatchDef.name}")));
    }

    return Result.ok(HitFactorConverter.toMatch(sport, matchDef, scores, sourceIds: [bareMatchDef.id], ignoreUnknownDivisions: options?.ignoreUnknownDivisions ?? false));
  }

  static ShootingMatch toMatch(
    Sport sport,
    HitFactorMatchDef matchDef,
    HitFactorScores scores,
    {
      List<String> sourceIds = const [],
      HitFactorScoreLogs? scoreLogs,
      bool ignoreUnknownDivisions = false,
    }
  ) {
    DateTime lastUpdated = practicalShootingZeroDate;
    Map<String, MatchStage> stages = {};
    for(var s in matchDef.stages) {
      if(s.deleted) {
        _log.v("Stage ${s.stageNumber} ${s.name} was deleted");
        continue;
      }

      var scoring = HitFactorConverter._matchScoring(s.scoreType);
      if(s.minRounds == 0 && s.maxPoints == 0 && scoring is! IgnoredScoring) {
        _log.w("Stage ${s.name} has no rounds or points but is not IgnoredScoring");
        scoring = IgnoredScoring();
      }
      var minRounds = s.minRounds;

      var ms = MatchStage(
        stageId: s.stageNumber,
        name: s.name,
        scoring: scoring,
        classifier: s.classifier,
        classifierNumber: s.classifierCode,
        minRounds: minRounds,
        maxPoints: minRounds * 5, // TODO: allow nonstandard values
        sourceId: s.uuid,
      );
      stages[s.uuid] = ms;

      //_log.v("Stage ${ms.stageId} ${ms.name}: ${s.minRounds} rounds");
    }

    Map<int, List<MatchStage>> stageIdToStages = {};
    int nextUnusedStageId = 0;
    for(var s in stages.values) {
      stageIdToStages.addToList(s.stageId, s);
      if(s.stageId >= nextUnusedStageId) {
        nextUnusedStageId = s.stageId + 1;
      }
    }

    for(var s in stageIdToStages.entries) {
      var id = s.key;
      var stages = s.value;
      if(stages.length > 1) {
        _log.i("Stage ID $id has multiple stages: ${stages.map((s) => s.name).join(", ")}");
        for(int i = 1; i < stages.length; i++) {
          var stage = stages[i];
          stage.stageId = nextUnusedStageId;
          nextUnusedStageId++;
          _log.d("Stage ${stage.name} now has ID ${stage.stageId}");
        }
      }
    }

    Map<String, bool> deletedShooters = {};
    Map<String, MatchEntry> shooters = {};
    int i = 1;
    int hasEmail = 0;
    for(var s in matchDef.shooters) {
      if(s.deleted) {
        _log.d("Shooter ${s.firstName} ${s.lastName} ${s.memberNumber} was deleted");
        deletedShooters[s.uuid] = true;
        continue;
      }

      PowerFactor? powerFactor;
      if(sport.hasPowerFactors) {
        powerFactor = sport.powerFactors.lookupByName(s.powerFactorName);
      }
      else {
        powerFactor = sport.defaultPowerFactor;
      }

      List<dynamic> parsedCategories = [];
      if(s.rawCategories.isNotEmpty) {
        try {
          parsedCategories = jsonDecode(s.rawCategories);
        } catch(e, st) {
          _log.e("error parsing categories for ${s.uuid}", error: e, stackTrace: st);
        }
      }

      AgeCategory? ageCategory;
      List<CompetitorCategory> categories = [];
      bool female = false;

      for(var cat in parsedCategories) {
        if(cat is String) {
          var ac = sport.ageCategories.lookupByName(cat);
          if(ac != null && ageCategory == null) {
            ageCategory = ac;
          }

          var lc = cat.toLowerCase();
          if(lc == "lady" || lc == "female") {
            female = true;
          }

          var cc = sport.categories.lookupByName(cat);
          if(cc != null) {
            categories.add(cc);
          }
        }
      }

      if(powerFactor != null) {
        var division = sport.hasDivisions ? sport.divisions.lookupByName(s.divisionName) : null;
        bool wasFallback = false;
        if(division != null && division.fallback) {
          var noFallback = sport.divisions.lookupByName(s.divisionName, fallback: false);
          if(noFallback == null) {
            wasFallback = true;
            _log.vv("Unknown division ${s.divisionName}");
          }
        }
        if(wasFallback && ignoreUnknownDivisions) {
          _log.v("Ignoring unknown division ${s.divisionName} for ${s.uuid}");
          continue;
        }

        String? region;
        String? subdivision;
        String? rawLocation;
        var usState = normalizeUSState(s.shooterState);
        if(usState != null) {
          region = "USA";
          subdivision = usState;
        }
        else if(s.shooterState != null && s.shooterState!.isNotEmpty) {
          _log.i("Unknown state ${s.shooterState} for ${s.uuid}");
          rawLocation = s.shooterState;
        }
        if(s.email != null && s.email!.isNotEmpty) {
          hasEmail++;
        }
        shooters[s.uuid] = MatchEntry(
          entryId: i,
          firstName: s.firstName,
          lastName: s.lastName,
          email: s.email,
          powerFactor: powerFactor,
          memberNumber: s.memberNumber,
          division: sport.hasDivisions ? sport.divisions.lookupByName(s.divisionName) : null,
          classification: sport.hasClassifications ? sport.classifications.lookupByName(s.className) : null,
          scores: {},
          squad: s.squad,
          ageCategory: ageCategory,
          categories: categories,
          female: female,
          sourceId: s.uuid,
          dq: s.disqualified,
          region: region,
          regionSubdivision: subdivision,
          rawLocation: rawLocation,
        );
      }
      else {
        _log.w("Shooter ${s.uuid} has missing power factor ${s.powerFactorName}!");
      }
      i++;
    }

    _log.i("Found $hasEmail email addresses");

    // Make sure we don't apply score logs to stage scores that are marked in the main scores as DNFs,
    // since the score logs will probably include steel hits on those.
    // This is a map of {stage ID: {shooter ID: dnf/not dnf}}
    Map<String, Map<String, bool>> stageShooterDnfs = {};

    for(var stageScoreHolder in scores.stageScores) {
      var stage = stages[stageScoreHolder.stageId];
      if(stage == null) {
        _log.e("Stage ${stageScoreHolder.stageId} does not exist!");
        continue;
      }

      for(var scoreDef in stageScoreHolder.scores) {
        var shooter = shooters[scoreDef.shooterId];
        if(deletedShooters.containsKey(scoreDef.shooterId)) {
          continue;
        }
        else if(shooter == null) {
          _log.w("Shooter ${scoreDef.shooterId} does not exist!");
          continue;
        }

        Map<ScoringEvent, int> targetEvents = {};
        Map<ScoringEvent, int> penaltyEvents = {};

        if(!scoreDef.stageDnf) {
          targetEvents = HitFactorScore.flattenTargetScores(scoreDef.decodeTargetHits(shooter.powerFactor));
          targetEvents.incrementBy(shooter.powerFactor.targetEvents.lookupByName("A")!, scoreDef.steelHits);
          targetEvents.incrementBy(shooter.powerFactor.targetEvents.lookupByName("M")!, scoreDef.steelMisses);
          targetEvents.incrementBy(shooter.powerFactor.targetEvents.lookupByName("NS")!, scoreDef.steelNoShoots);

          penaltyEvents[shooter.powerFactor.penaltyEvents.lookupByName("Procedural")!] = scoreDef.procedurals;
          penaltyEvents[shooter.powerFactor.penaltyEvents.lookupByName("Overtime Shot")!] = scoreDef.overtimeShots;
        }
        else {
          stageShooterDnfs[stageScoreHolder.stageId] ??= {};
          stageShooterDnfs[stageScoreHolder.stageId]![scoreDef.shooterId] = true;
        }

        var score = RawScore(
          scoring: stage.scoring,
          targetEvents: targetEvents,
          penaltyEvents: penaltyEvents,
          rawTime: scoreDef.totalTime,
          stringTimes: []..addAll(scoreDef.stringTimes),
          modified: scoreDef.modified,
          dq: scoreDef.dqReasons.isNotEmpty,
        );
        if(score.modified != null && score.modified!.isAfter(lastUpdated)) {
          lastUpdated = score.modified!;
        }
        shooter.scores[stage] = score;
      }
    }

    if(scoreLogs != null) {
      _log.i("Processing ${scoreLogs.logs.length} score logs");
      int applied = 0;
      for(var log in scoreLogs.logs) {
        var stage = stages[log.stageUuid];
        if(stage == null) {
          _log.w("Stage ${log.stageUuid} in score log ${log.logUuid} does not exist!");
          continue;
        }

        if(stage.scoring is IgnoredScoring) {
          continue;
        }

        if(!log.isValid && (!log.isValidPointsOnly && stage.scoring is! PointsScoring)) {
          _log.v("Score log ${log.logUuid} for shooter ${log.shooterId} is incomplete");
          _log.vv("${log.originalLog?['score']}");
          if(log.originalLog?['score'] == null) {
            _log.vv("${log.originalLog}");
          }
          continue;
        }

        var shooter = shooters[log.shooterUniqueId];
        if(shooter == null) {
          _log.w("Shooter ${log.shooterUniqueId} in score log ${log.logUuid} does not exist!");
          continue;
        }

        var stageScore = shooter.scores[stage];
        if(stageScore != null && !stageScore.dnf) {
         //  _log.vv("Shooter ${shooter.name} already has a score for stage ${stage.name}");
          continue;
        }

        // If we have an affirmative DNF from the main scores, don't apply the score log.
        if(stageShooterDnfs.containsKey(log.stageUuid) && stageShooterDnfs[log.stageUuid]![log.shooterUniqueId] == true) {
          // _log.vv("Shooter ${shooter.name} has an affirmative DNF on stage ${stage.stageId} ${stage.name} from the main scores, skipping score log ${log.logUuid}");
          continue;
        }

        Map<ScoringEvent, int> targetEvents = {};
        Map<ScoringEvent, int> penaltyEvents = {};

        var powerFactor = shooter.powerFactor;
        for(var e in log.eventNamesToCounts.entries) {
          var eventName = e.key;
          var count = e.value;

          var maybeTarget = powerFactor.targetEvents.lookupByName(eventName);
          var maybePenalty = powerFactor.penaltyEvents.lookupByName(eventName);
          if(maybeTarget != null) {
            targetEvents.incrementBy(maybeTarget, count);
          }
          else if(maybePenalty != null) {
            penaltyEvents.incrementBy(maybePenalty, count);
          }
          else {
            _log.w("Unknown event $eventName");
          }
        }
        var time = 0.0;
        if(stage.scoring is! PointsScoring) {
          time = log.time;
        }
        var stringTimes = [0.0];
        if(stage.scoring is! PointsScoring) {
          stringTimes = log.stringTimes;
        }
        var score = RawScore(
          scoring: stage.scoring,
          rawTime: time,
          targetEvents: targetEvents,
          penaltyEvents: penaltyEvents,
          stringTimes: stringTimes,
          modified: log.modified,
        );
        if(log.modified.isAfter(lastUpdated)) {
          lastUpdated = log.modified;
        }
        shooter.scores[stage] = score;
        applied++;
      }
      _log.i("Applied $applied score logs of ${scoreLogs.logs.length}");
    }

    var level = sport.eventLevels.lookupByName(matchDef.levelName);

    if(lastUpdated == practicalShootingZeroDate) {
      // If we have no score time information, use the current date (the date of retrieval/parsing)
      // as the match date.
      _log.i("No score time information for match ${matchDef.name}, using current date as match date");
      lastUpdated = DateTime.now();
    }

    return ShootingMatch(
      sport: sport,
      name: matchDef.name,
      rawDate: matchDef.rawDate,
      date: programmerYmdFormat.parse(matchDef.rawDate),
      sourceLastUpdated: lastUpdated,
      shooters: []..addAll(shooters.values),
      stages: []..addAll(stages.values),
      sourceIds: []..addAll(sourceIds),
      level: level,
    );
  }

  static StageScoring _matchScoring(String stageScoring) {
    return switch(stageScoring) {
      comstockScoring || virginiaScoring => HitFactorScoring(),
      fixedTimeScoring => PointsScoring(),
      String() => IgnoredScoring(),
    };
  }
}

List<Sport> hitFactorSubtypeSportOrder(String matchName, String subtype) {
  if(matchName.toLowerCase().contains("pcsl")) {
    return [pcslSport, uspsaSport, ipscSport];
  }

  return switch(subtype.toLowerCase()) {
    "ipsc" => [ipscSport, uspsaSport, pcslSport],
    "pcsl" => [pcslSport, uspsaSport, ipscSport],
    String() => [uspsaSport, ipscSport, pcslSport],
  };
}
