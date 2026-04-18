

import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/bare_match_def.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/idpa/idpa_matchdef.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/idpa/idpa_scorelogs.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/idpa/idpa_scores.dart';
import 'package:shooting_sports_analyst/data/source/psc/parse_utils.dart';
import 'package:shooting_sports_analyst/data/source/psc/psc_options.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("IDPAConverter");

class IdpaConverter {
  static (IdpaLikeMatchDef, IdpaLikeScores) matchInfoFromBareMatchDef(BareMatchDef matchDef) {
    if(matchDef.matchDefJson.isEmpty || matchDef.scoresJson.isEmpty) {
      throw ArgumentError("matchDefJson and scoresJson must be non-empty");
    }

    return (
      IdpaLikeMatchDef.fromJson(matchDef.matchDefJson),
      IdpaLikeScores.fromJson(matchDef.scoresJson),
    );
  }

  static Result<ShootingMatch, MatchSourceError> matchFromBareMatchDef(BareMatchDef bareMatchDef, {PscMatchFetchOptions? options}) {
    final (matchDef, scores) = IdpaConverter.matchInfoFromBareMatchDef(bareMatchDef);

    if(matchesSport(idpaSport, divisions: matchDef.divisions) || (options?.ignoreUnknownDivisions ?? false)) {
      return Result.ok(IdpaConverter.toMatch(idpaSport, matchDef, scores, sourceIds: [bareMatchDef.id], ignoreUnknownDivisions: options?.ignoreUnknownDivisions ?? false));
    }
    else {
      _log.w("Unable to process match: ${bareMatchDef.name} without a sport");
      return Result.err(FormatError(StringError("No sport found for match: ${bareMatchDef.name}")));
    }
  }

  static ShootingMatch toMatch(
    Sport sport,
    IdpaLikeMatchDef matchDef,
    IdpaLikeScores scores,
    {
      List<String> sourceIds = const [],
      IdpaScoreLogs? scoreLogs,
      bool ignoreUnknownDivisions = false,
    }
  ) {
    DateTime lastUpdated = practicalShootingZeroDate;
    Map<String, MatchStage> stages = {};
    for(var s in matchDef.stages) {
      if(s.deleted) {
        _log.d("Stage ${s.stageNumber} ${s.name} was deleted");
        continue;
      }

      var scoring = s.scoreType == IdpaStageScoreType ? sport.defaultStageScoring : IgnoredScoring();

      stages[s.uuid] = MatchStage(
        stageId: s.stageNumber,
        name: s.name,
        scoring: scoring,
        sourceId: s.uuid,
      );
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

    var pf = sport.defaultPowerFactor;

    Map<String, MatchEntry> shooters = {};
    Map<String, bool> deletedShooters = {};
    int i = 1;
    for(var s in matchDef.shooters) {
      if(s.deleted) {
        _log.d("Shooter ${s.firstName} ${s.lastName} ${s.memberNumber} was deleted");
        deletedShooters[s.uuid] = true;
        continue;
      }

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

      shooters[s.uuid] = MatchEntry(
        entryId: i,
        firstName: s.firstName,
        lastName: s.lastName,
        email: s.email,
        powerFactor: pf,
        memberNumber: s.memberNumber,
        division: sport.hasDivisions ? sport.divisions.lookupByName(s.divisionName) : null,
        classification: sport.hasClassifications ? sport.classifications.lookupByName(s.className) : null,
        scores: {},
        squad: s.squad,
        sourceId: s.uuid,
        dq: s.disqualified,
      );
      i++;
    }

    for(var stageScoreHolder in scores.stageScores) {
      var stage = stages[stageScoreHolder.stageId];
      if(stage == null) {
        _log.w("Stage ${stageScoreHolder.stageId} does not exist!");
        continue;
      }

      for(var scoreDef in stageScoreHolder.scores) {
        var shooter = shooters[scoreDef.shooterId];
        if(deletedShooters.containsKey(scoreDef.shooterId)) {
          continue;
        }
        if(shooter == null) {
          _log.w("Shooter ${scoreDef.shooterId} does not exist!");
          continue;
        }

        Map<ScoringEvent, int> penalties = {};
        for(int i = 0; i < scoreDef.penalties.length; i++) {
          int count = scoreDef.penalties[i];
          if(count > 0) {
            var penaltyDef = matchDef.penalties[i];
            var penalty = pf.penaltyEvents.lookupByName(penaltyDef.name);

            // It might be a miss, which is scored on target in SSA IDPA.
            var targetEvent = pf.targetEvents.lookupByName(penaltyDef.name);
            if(penalty != null) {
              penalties[penalty] = count;
            }
            else if(targetEvent != null && !targetEvent.isPositive(sport)) {
              // Since we're looking at penalties, we should ignore any events that are
              // good for the competitor here.
              penalties[targetEvent] = count;
            }
            else {
              _log.w("Unknown penalty ${penaltyDef.name}!");
            }
          }
        }

        var score = RawScore(
          scoring: sport.defaultStageScoring,
          targetEvents: {
            pf.targetEvents.lookupByName("-1")!: scoreDef.totalPointsDown,
          },
          penaltyEvents: penalties,
          rawTime: scoreDef.totalTime,
          stringTimes: []..addAll(scoreDef.stringTimes),
          modified: scoreDef.modified,
        );

        shooter.scores[stage] = score;
        if(score.modified != null && score.modified!.isAfter(lastUpdated)) {
          lastUpdated = score.modified!;
        }
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

        if(!log.isValid) {
          _log.v("Score log ${log.logUuid} for shooter ${log.shooterId} is incomplete");
          continue;
        }

        var shooter = shooters[log.shooterUniqueId];
        if(shooter == null) {
          _log.w("Shooter ${log.shooterUniqueId} in score log ${log.logUuid} does not exist!");
          continue;
        }

        var stageScore = shooter.scores[stage];
        if(stageScore != null && !stageScore.dnf) {
          _log.d("Shooter already has a score for stage ${stage.name}");
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

        var score = RawScore(
          scoring: stage.scoring,
          targetEvents: targetEvents,
          penaltyEvents: penaltyEvents,
          rawTime: log.rawTime,
          stringTimes: [log.rawTime],
          modified: log.modified,
        );

        if(log.modified.isAfter(lastUpdated)) {
          lastUpdated = log.modified;
        }

        if(score.finalTime != log.finalTime) {
          _log.w("Final time mismatch for ${shooter.memberNumber} on ${stage.name}: $score.finalTime != $log.finalTime");
        }

        shooter.scores[stage] = score;
        applied++;
      }

      _log.i("Applied $applied score logs");
    }

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
    );
  }
}
