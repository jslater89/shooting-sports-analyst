
import 'dart:convert';

import 'package:shooting_sports_analyst/data/location_normalizer.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/bare_match_def.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/icore/icore_matchdef.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/icore/icore_scorelogs.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/icore/icore_scores.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';
import 'package:shooting_sports_analyst/data/source/psc/psc_options.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("IcoreConverter");
final _verboseParse = FlutterOrNative.debugModeProvider.kDebugMode;

class IcoreConverter {
  static (IcoreMatchDef, IcoreScores) matchInfoFromBareMatchDef(BareMatchDef matchDef) {
    if(matchDef.matchDefJson.isEmpty || matchDef.scoresJson.isEmpty) {
      throw ArgumentError("matchDefJson and scoresJson must be non-empty");
    }

    return (
      IcoreMatchDef.fromJson(matchDef.matchDefJson),
      IcoreScores.fromJson(matchDef.scoresJson),
    );
  }

  static Result<ShootingMatch, MatchSourceError> matchFromBareMatchDef(BareMatchDef bareMatchDef, {PscMatchFetchOptions? options}) {
    final (matchDef, scores) = IcoreConverter.matchInfoFromBareMatchDef(bareMatchDef);

    if(matchesSport(icoreSport, divisions: matchDef.divisions) || (options?.ignoreUnknownDivisions ?? false)) {
      _log.w("Advancing with best effort: ICORE division match failed for ${bareMatchDef.name}: ${matchDef.divisions}");
    }
    var match = IcoreConverter.toMatch(icoreSport, matchDef, scores, sourceIds: [bareMatchDef.id]);
    return Result.ok(match);
  }

  static ShootingMatch toMatch(
    Sport sport,
    IcoreMatchDef matchDef,
    IcoreScores scores,
    {
      List<String> sourceIds = const [],
      IcoreScoreLogs? scoreLogs,
    }
  ) {
    DateTime lastUpdated = practicalShootingZeroDate;
    // We need these as maps of int to ScoringEvent here, because we're going to look them
    // up by index in the bonus/penalty arrays on each PS score. We discard the int keys
    // when we add them to the match object, because we look everything up by name in
    // Analyst proper.
    Map<int, ScoringEvent> matchBonuses = {};
    Map<int, ScoringEvent> localBonuses = {};
    Map<int, ScoringEvent> matchPenalties = {};
    Map<int, ScoringEvent> localPenalties = {};
    int sortOrderStart = sport.defaultPowerFactor.allEvents.length + 1;

    for(var (i, b) in matchDef.bonuses.indexed) {
      if(sport.defaultPowerFactor.allEvents.lookupByName(b.name) == null) {
        var event = b.toScoringEvent(sortOrderStart);
        _log.i("Creating bonus ${b.name} (${event.shortName}) worth ${b.value} for ${matchDef.name}");
        matchBonuses[i] = event;
        localBonuses[i] = event;
        sortOrderStart++;
      }
      else {
        matchBonuses[i] = sport.defaultPowerFactor.allEvents.lookupByName(b.name)!;
      }
    }

    for(var (i, p) in matchDef.penalties.indexed) {
      if(sport.defaultPowerFactor.allEvents.lookupByName(p.name) == null) {
        var event = p.toScoringEvent(sortOrderStart);
        _log.i("Creating penalty ${p.name} (${event.shortName}) worth ${p.value} for ${matchDef.name}");
        matchPenalties[i] = event;
        localPenalties[i] = event;
        sortOrderStart++;
      }
      else {
        matchPenalties[i] = sport.defaultPowerFactor.allEvents.lookupByName(p.name)!;
      }
    }

    Map<String, MatchStage> stages = {};
    for(var s in matchDef.stages) {
      if(s.deleted) {
        _log.v("Stage ${s.stageNumber} ${s.name} was deleted");
        continue;
      }

      var minRounds = s.minRounds;

      var xEvent = icoreX;
      double? nonstandardXMult;
      bool hasSingleNonstandardXMult = true;
      Map<int, ScoringEvent> nonstandardXMults = {};
      for(var (i, t) in s.targets.indexed) {
        if(t.xMult != 1) {
          if(nonstandardXMult == null) {
            nonstandardXMult = t.xMult;
          }
          else if(nonstandardXMult != t.xMult) {
            hasSingleNonstandardXMult = false;
          }
          nonstandardXMults[i] = xEvent.copyWith(timeChange: -1 * t.xMult);
        }
      }

      Map<String, ScoringEventOverride> scoringOverrides = {};
      Map<String, List<ScoringEvent>> variableEvents = {};
      // If all targets have an X-ring bonus of 1
      if(hasSingleNonstandardXMult && nonstandardXMult != null) {
        _log.v("Stage ${s.stageNumber} has a single nonstandard X mult: $nonstandardXMult");
        scoringOverrides[icoreX.name] = ScoringEventOverride(
          name: icoreX.name,
          timeChangeOverride: -1 * nonstandardXMult,
        );
      }
      else if(nonstandardXMults.isNotEmpty) {
        _log.v("Stage ${s.stageNumber} has nonstandard X mults: ${nonstandardXMults.values.map((e) => e.timeChange).toList()}");
        s.nonstandardX = nonstandardXMults;
        variableEvents[icoreX.name] = nonstandardXMults.values.toSet().toList(); // remove duplicates
      }

      var isChrono = s.scoreType == icoreChronoScoringName;
      if(!isChrono) {
        // TODO: I'd love to inspect scores to see if they're chrono-like {0.01, 360.01} or {0.00, 360.00}
        var processedName = s.name.toLowerCase().replaceAll(RegExp(r"[^a-z]+"), "").replaceAll("stage", "").trim();
        if(processedName == "chrono" || (processedName.split(" ").length == 1 && processedName.startsWith("chrono"))) {
          _log.v("Fallback chrono detection for ${matchDef.name} stage ${s.stageNumber}");
          isChrono = true;
        }
      }

      var ms = MatchStage(
        stageId: s.stageNumber,
        name: s.name,
        scoring: isChrono ? const TimePlusChronoScoring() : sport.defaultStageScoring,
        classifier: s.classifier,
        classifierNumber: s.classifierCode,
        minRounds: minRounds,
        maxPoints: 0, // irrelevant
        sourceId: s.uuid,
        scoringOverrides: scoringOverrides,
        variableEvents: variableEvents,
      );
      stages[s.uuid] = ms;

      if(_verboseParse) {
        _log.v("Stage ${ms.stageId} ${ms.name}: ${s.minRounds} rounds");
      }
    }

    Map<String, bool> deletedShooters = {};
    Map<String, MatchEntry> shooters = {};
    int i = 1;
    for(var s in matchDef.shooters) {
      if(s.deleted) {
        _log.d("Shooter ${s.firstName} ${s.lastName} ${s.memberNumber} was deleted");
        deletedShooters[s.uuid] = true;
        continue;
      }

      Division? division;
      if(sport.hasDivisions) {
        division = sport.divisions.lookupByName(s.divisionName);
      }
      PowerFactor? powerFactor;
      if(division?.powerFactorOverride != null) {
        powerFactor = division!.powerFactorOverride!;
      }
      else {
        powerFactor = sport.defaultPowerFactor;
      }

      if(division?.fallback ?? false) {
        var noFallback = sport.divisions.lookupByName(s.divisionName, fallback: false);
        if(noFallback == null) {
          if(_verboseParse) _log.d("No fallback division for original division ${s.divisionName}");
        }
      }

      AgeCategory? ageCategory;
      bool female = false;

      List<dynamic> parsedCategories = jsonDecode(s.rawCategories);

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
        }
      }

      if(sport.hasDivisions && division == null) {
        // In ICORE, we can't trust fallback because some ICORE matches will allow non-revolvers
        _log.i("Skipping ${s.firstName} ${s.lastName} ${s.memberNumber} with no division");
        continue;
      }

      String? region;
      String? regionSubdivision;
      if(s.state != null) {
        var usState = normalizeUSState(s.state);
        if(usState != null) {
          region = "USA";
          regionSubdivision = usState;
        }
      }
      shooters[s.uuid] = MatchEntry(
        entryId: i,
        firstName: s.firstName,
        lastName: s.lastName,
        email: s.email,
        powerFactor: powerFactor,
        memberNumber: s.memberNumber,
        division: division,
        classification: sport.hasClassifications ? sport.classifications.lookupByName(s.className) : null,
        scores: {},
        squad: s.squad,
        ageCategory: ageCategory,
        female: female,
        sourceId: s.uuid,
        dq: s.disqualified,
        region: region,
        regionSubdivision: regionSubdivision,
      );
      i++;
    }

    for(var stageScoreHolder in scores.stageScores) {
      var stage = stages[stageScoreHolder.stageId];
      var stageDef = matchDef.stages.firstWhere((s) => s.stageNumber == stageScoreHolder.stageNumber);

      if(stage == null) {
        _log.w("Stage ${stageScoreHolder.stageId} does not exist!");
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
          targetEvents = IcoreScore.flattenTargetScores(scoreDef.decodeTargetHits(shooter.powerFactor, stageDef.nonstandardX));
          targetEvents.incrementBy(shooter.powerFactor.targetEvents.lookupByName("A")!, scoreDef.steelHits);
          targetEvents.incrementBy(shooter.powerFactor.targetEvents.lookupByName("M")!, scoreDef.steelMisses);

          for(int i = 0; i < scoreDef.penalties.length; i++) {
            var penCount = scoreDef.penalties[i];
            if(penCount > 0) {
              if(matchPenalties.containsKey(i)) {
                var penalty = matchPenalties[i]!;
                penaltyEvents.incrementBy(penalty, penCount);
              }
              else {
                _log.w("Penalty $i is out of bounds (${matchPenalties.keys.toList()} known)!");
              }
            }
          }

          for(int i = 0; i < scoreDef.bonuses.length; i++) {
            var bonCount = scoreDef.bonuses[i];
            if(bonCount > 0) {
              if(matchBonuses.containsKey(i)) {
                var bonus = matchBonuses[i]!;
                targetEvents.incrementBy(bonus, bonCount);
              }
              else {
                _log.w("Bonus $i is out of bounds (${matchBonuses.keys.toList()} known)!");
              }
            }
          }
        }

        var score = RawScore(
          scoring: stage.scoring,
          targetEvents: targetEvents,
          penaltyEvents: penaltyEvents,
          rawTime: scoreDef.totalTime,
          stringTimes: []..addAll(scoreDef.stringTimes),
          modified: scoreDef.modified,
          dq: scoreDef.dqReasons.isNotEmpty,
          scoringOverrides: {...stage.scoringOverrides},
        );
        if(score.modified != null && score.modified!.isAfter(lastUpdated)) {
          lastUpdated = score.modified!;
        }
        shooter.scores[stage] = score;
      }
    }

    // TODO: score logs

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
      localBonusEvents: localBonuses.values.toList(),
      localPenaltyEvents: localPenalties.values.toList(),
    );
  }
}
