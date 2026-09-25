/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:data/stats.dart' show WeibullDistribution;
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/cache/match/match_cache.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart' show ipscSport, ipscDivisionForUspsaDivision;
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart' show uspsaSport, uspsaA;
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("MatchHeatDatabase");

/// Per-division inputs to a match heat calculation.
///
/// [rawWeight] is this division's score-entry count divided by the match's
/// shooter count. [normalizedWeight] is that share renormalized over divisions
/// that were included (at least five rated competitors with a scaled rating).
/// Weighted contributions are [normalizedWeight] times the division metric.
///
/// Both averages walk rated competitors in finish order. The score map is
/// inserted after sorting on match total, so the first entries are the best
/// finishers.
///
/// [topTenPercentAverageRating] is the first max(3, round(10%)) of those
/// ratings. [topContenderAverageRating] uses a count that grows linearly from
/// 3 to 24 as the rated field grows from 0 to 400, then stays at 24.
class DivisionHeatContribution {
  final String divisionName;
  final String divisionShortName;
  final String? scoredDivisionName;
  final String? groupName;
  final String? groupUuid;
  final int rosterCount;
  final int scoreCount;
  final int ratedCount;
  final int unratedCount;
  final int currentRatingCount;
  final int matchRatingCount;
  final int ratedWithoutMatchEventCount;
  final double? groupMinRating;
  final double? groupMaxRating;
  final double? topTenPercentAverageRating;
  final int topTenSampleSize;
  final double? topContenderAverageRating;
  final int topContenderSampleSize;
  final double? medianRating;
  final double? classificationStrength;
  final bool classificationFixedToUspsaA;
  final double rawWeight;
  final double? normalizedWeight;
  final String? skipReason;

  bool get included => skipReason == null && normalizedWeight != null;

  const DivisionHeatContribution({
    required this.divisionName,
    required this.divisionShortName,
    required this.scoredDivisionName,
    required this.groupName,
    required this.groupUuid,
    required this.rosterCount,
    required this.scoreCount,
    required this.ratedCount,
    required this.unratedCount,
    required this.currentRatingCount,
    required this.matchRatingCount,
    required this.ratedWithoutMatchEventCount,
    required this.groupMinRating,
    required this.groupMaxRating,
    required this.topTenPercentAverageRating,
    required this.topTenSampleSize,
    required this.topContenderAverageRating,
    required this.topContenderSampleSize,
    required this.medianRating,
    required this.classificationStrength,
    required this.classificationFixedToUspsaA,
    required this.rawWeight,
    required this.normalizedWeight,
    required this.skipReason,
  });

  double? get weightedTopTenContribution =>
      _weighted(topTenPercentAverageRating);
  double? get weightedContenderContribution =>
      _weighted(topContenderAverageRating);
  double? get weightedMedianContribution => _weighted(medianRating);
  double? get weightedClassificationContribution =>
      _weighted(classificationStrength);

  double? _weighted(double? value) {
    if(value == null || normalizedWeight == null) {
      return null;
    }
    return value * normalizedWeight!;
  }
}

/// Full match-heat result plus the division rows that produced it.
class MatchHeatCalculation {
  final MatchHeat? heat;
  final String? failureReason;
  final String matchName;
  final DateTime? matchDate;
  final int rawCompetitorCount;
  final int ratedCompetitorCount;
  final int unratedCompetitorCount;
  final List<DivisionHeatContribution> divisions;

  const MatchHeatCalculation({
    required this.heat,
    required this.failureReason,
    required this.matchName,
    required this.matchDate,
    required this.rawCompetitorCount,
    required this.ratedCompetitorCount,
    required this.unratedCompetitorCount,
    required this.divisions,
  });

  factory MatchHeatCalculation.failed(String reason, {String matchName = ""}) {
    return MatchHeatCalculation(
      heat: null,
      failureReason: reason,
      matchName: matchName,
      matchDate: null,
      rawCompetitorCount: 0,
      ratedCompetitorCount: 0,
      unratedCompetitorCount: 0,
      divisions: const [],
    );
  }

  String describe() {
    final buf = StringBuffer();
    final dateLabel = matchDate == null
        ? "unknown date"
        : "${matchDate!.year.toString().padLeft(4, "0")}-${matchDate!.month.toString().padLeft(2, "0")}-${matchDate!.day.toString().padLeft(2, "0")}";
    buf.writeln("Match heat: $matchName ($dateLabel)");
    if(failureReason != null) {
      buf.writeln("  Failed: $failureReason");
    }
    buf.writeln(
      "  Shooters: $rawCompetitorCount raw, $ratedCompetitorCount rating lookups, $unratedCompetitorCount unrated",
    );
    buf.writeln(
      "  Weight: raw = division score entries / match shooters; normalized = raw / sum of included raw weights.",
    );
    buf.writeln(
      "  Both averages use finish order. Top 10% is max(3, round(10% of rated)). Contenders lerp from 3 to 24 across 0 to 400 rated competitors.",
    );
    if(heat != null) {
      buf.writeln(
        "  Unweighted avg  decile ${heat!.topTenPercentAverageRating.toStringAsFixed(4)}"
        "  contenders ${heat!.topContenderAverageRating.toStringAsFixed(4)}"
        "  median ${heat!.medianRating.toStringAsFixed(4)}"
        "  class ${heat!.classificationStrength.toStringAsFixed(4)}",
      );
      buf.writeln(
        "  Weighted avg    decile ${heat!.weightedTopTenPercentAverageRating.toStringAsFixed(4)}"
        "  contenders ${heat!.weightedTopContenderAverageRating.toStringAsFixed(4)}"
        "  median ${heat!.weightedMedianRating.toStringAsFixed(4)}"
        "  class ${heat!.weightedClassificationStrength.toStringAsFixed(4)}",
      );
    }

    final included = divisions.where((d) => d.included).toList();
    final skipped = divisions.where((d) => !d.included).toList();
    if(included.isNotEmpty) {
      buf.writeln("  Included divisions (${included.length})");
      buf.writeln(
        "  ${_pad("Div", 8)} ${_pad("Ent", 5)} ${_pad("Rated", 5)} ${_pad("RawWt", 7)} ${_pad("NormWt", 7)}"
        " ${_pad("Decile", 8)} ${_pad("Contend", 8)} ${_pad("Median", 8)} ${_pad("Class", 7)}"
        " ${_pad("WtDec", 8)} ${_pad("WtCon", 8)} ${_pad("WtMed", 8)} ${_pad("WtCls", 8)}",
      );
      for(final division in included) {
        buf.writeln(
          "  ${_pad(division.divisionShortName, 8)} ${_pad("${division.scoreCount}", 5)} ${_pad("${division.ratedCount}", 5)}"
          " ${_num(division.rawWeight, 7)} ${_num(division.normalizedWeight, 7)}"
          " ${_num(division.topTenPercentAverageRating, 8)} ${_num(division.topContenderAverageRating, 8)}"
          " ${_num(division.medianRating, 8)} ${_num(division.classificationStrength, 7)}"
          " ${_num(division.weightedTopTenContribution, 8)} ${_num(division.weightedContenderContribution, 8)} ${_num(division.weightedMedianContribution, 8)}"
          " ${_num(division.weightedClassificationContribution, 8)}",
        );
        buf.writeln(
          "    ${division.groupName ?? "no group"}"
          "  roster ${division.rosterCount}"
          "  current ${division.currentRatingCount}"
          "  match ${division.matchRatingCount}"
          "  no event ${division.ratedWithoutMatchEventCount}"
          "  unrated ${division.unratedCount}"
          "  decile n=${division.topTenSampleSize}  contender n=${division.topContenderSampleSize}"
          "${division.classificationFixedToUspsaA ? "  class fixed to USPSA A" : ""}"
          "${_rangeLabel(division)}",
        );
      }
    }
    if(skipped.isNotEmpty) {
      buf.writeln("  Skipped divisions (${skipped.length})");
      for(final division in skipped) {
        buf.writeln(
          "  ${_pad(division.divisionShortName, 8)} roster ${division.rosterCount}  scores ${division.scoreCount}  rated ${division.ratedCount}  ${division.skipReason}",
        );
      }
    }
    return buf.toString().trimRight();
  }

  static String _pad(String value, int width) {
    if(value.length >= width) {
      return value.substring(0, width);
    }
    return value.padRight(width);
  }

  static String _num(double? value, int width) {
    if(value == null) {
      return "-".padLeft(width);
    }
    return value.toStringAsFixed(3).padLeft(width);
  }

  static String _rangeLabel(DivisionHeatContribution division) {
    if(division.groupMinRating == null || division.groupMaxRating == null) {
      return "";
    }
    return "  raw scale ${division.groupMinRating!.toStringAsFixed(3)}..${division.groupMaxRating!.toStringAsFixed(3)}";
  }
}

class _DivisionHeatDraft {
  _DivisionHeatDraft(this.divisionName, this.divisionShortName);

  final String divisionName;
  final String divisionShortName;
  String? scoredDivisionName;
  String? groupName;
  String? groupUuid;
  int rosterCount = 0;
  int scoreCount = 0;
  int ratedCount = 0;
  int unratedCount = 0;
  int currentRatingCount = 0;
  int matchRatingCount = 0;
  int ratedWithoutMatchEventCount = 0;
  double? groupMinRating;
  double? groupMaxRating;
  double? topTenPercentAverageRating;
  int topTenSampleSize = 0;
  double? topContenderAverageRating;
  int topContenderSampleSize = 0;
  double? medianRating;
  double? classificationStrength;
  bool classificationFixedToUspsaA = false;
  double rawWeight = 0;
  double? normalizedWeight;
  String? skipReason;
}

/// TODO: RatingDataSource interface to this
extension MatchHeatDatabase on AnalystDatabase {
  /// Get a match heat record for a specific match.
  Future<MatchHeat?> getMatchHeatForMatch(int projectId, String matchSourceId) async {
    return await isar.matchHeats.where().projectIdMatchSourceIdEqualTo(projectId, matchSourceId).findFirst();
  }

  /// Get a match heat record for a specific match.
  MatchHeat? getMatchHeatForMatchSync(int projectId, String matchSourceId) {
    return isar.matchHeats.where().projectIdMatchSourceIdEqualTo(projectId, matchSourceId).findFirstSync();
  }

  /// Save a match heat record.
  Future<void> saveMatchHeat(MatchHeat matchHeat) async {
    await isar.writeTxn(() async {
      await isar.matchHeats.put(matchHeat);
    });
  }

  /// Get all match heat records for a project.
  Future<List<MatchHeat>> getMatchHeatForProject(int projectId) async {
    return await isar.matchHeats.where().projectIdEqualToAnyMatchSourceId(projectId).findAll();
  }

  /// Get all match heat records for a project.
  List<MatchHeat> getMatchHeatForProjectSync(int projectId) {
    return isar.matchHeats.where().projectIdEqualToAnyMatchSourceId(projectId).findAllSync();
  }

  /// Delete all match heat records for a project.
  Future<void> deleteMatchHeatForProject(int projectId) async {
    await isar.writeTxn(() async {
      await isar.matchHeats.where().projectIdEqualToAnyMatchSourceId(projectId).deleteAll();
    });
  }

  Future<MatchHeat?> calculateHeatForMatch(int ratingProjectId, MatchPointer ptr) async {
    final calculation = await calculateHeatCalculation(ratingProjectId, ptr);
    return calculation.heat;
  }

  /// Same calculation as [calculateHeatForMatch], plus per-division weights.
  ///
  /// Set [logBreakdown] to write [MatchHeatCalculation.describe] to the log.
  Future<MatchHeatCalculation> calculateHeatCalculation(int ratingProjectId, MatchPointer ptr, {bool logBreakdown = false}) async {
    var project = await getRatingProjectById(ratingProjectId);
    if(project == null) {
      _log.w("Rating project not found: $ratingProjectId");
      return MatchHeatCalculation.failed("Rating project not found: $ratingProjectId", matchName: ptr.name);
    }
    var sport = project.sport;

    Map<String, RatingScaler> scalers = {};
    final useCurrentRating = false;

    var dbMatch = await getMatchByAnySourceId(ptr.sourceIds);
    if(dbMatch == null) {
      _log.w("Match not found: ${ptr.name}");
      return MatchHeatCalculation.failed("Match not found: ${ptr.name}", matchName: ptr.name);
    }
    var matchRes = await MatchCache.instance.get(dbMatch);
    if(matchRes.isErr()) {
      _log.w("Error hydrating match: ${matchRes.unwrapErr()}");
      return MatchHeatCalculation.failed("Error hydrating match: ${matchRes.unwrapErr()}", matchName: ptr.name);
    }
    var match = matchRes.unwrap();
    Map<MatchEntry, double> shooterRatings = {};
    int rawCompetitorCount = match.shooters.length;
    int ratedCompetitorCount = 0;
    int unratedCompetitorCount = 0;
    List<double> topTenPercentAverageRatings = [];
    List<(double, double)> weightedTopTenPercentAverageRatings = [];
    List<double> topContenderAverageRatings = [];
    List<(double, double)> weightedTopContenderAverageRatings = [];
    List<double> medianRatings = [];
    List<(double, double)> weightedMedianRatings = [];
    List<double> classificationStrengths = [];
    List<(double, double)> weightedClassificationStrengths = [];
    final drafts = <_DivisionHeatDraft>[];
    final draftByName = <String, _DivisionHeatDraft>{};

    // For each division, find ratings for all rated competitors, ignoring divisions with fewer than 5 competitors.
    for(var division in sport.divisions.values) {
      final draft = _DivisionHeatDraft(division.name, division.shortDisplayName);
      drafts.add(draft);
      draftByName[division.name] = draft;

      DataSourceResult<RatingGroup?> groupRes;
      Division finalDivision = division;
      if(sport == uspsaSport && match.sport == ipscSport) {
        var ipscDivision = ipscDivisionForUspsaDivision(division);
        if(ipscDivision == null) {
          _log.w("No IPSC division found for USPSA division: ${division.name}");
          draft.skipReason = "No IPSC division for this USPSA division";
          continue;
        }
        groupRes = await project.groupForDivision(division);
        finalDivision = ipscDivision;
      }
      else {
        groupRes = await project.groupForDivision(division);
      }
      draft.scoredDivisionName = finalDivision.name;

      if(groupRes.isErr()) {
        _log.w("Error getting group for division ${division.name}: ${groupRes.unwrapErr()}");
        draft.skipReason = "Group lookup failed: ${groupRes.unwrapErr()}";
        continue;
      }
      var group = groupRes.unwrap();
      if(group == null) {
        _log.w("No group found for division: ${division.name}");
        draft.skipReason = "No rating group";
        continue;
      }
      draft.groupName = group.name;
      draft.groupUuid = group.uuid;

      var scaler = scalers[group.uuid];
      if(scaler == null) {
        var groupInfo = await _calculateGroupInfo(this, project, group);
        scaler = project.settings.algorithm.standardScaler;
        scaler.info = groupInfo;
        scalers[group.uuid] = scaler;
      }
      draft.groupMinRating = scaler.info.minRating;
      draft.groupMaxRating = scaler.info.maxRating;

      final int shortCompetitorHistory;
      if(project.settings.byStage) {
        shortCompetitorHistory = 50;
      }
      else {
        shortCompetitorHistory = 5;
      }

      var divisionEntries = match.filterShooters(divisions: [finalDivision]);
      draft.rosterCount = divisionEntries.length;
      if(divisionEntries.length < 5) {
        draft.skipReason = "Fewer than 5 roster entries (${divisionEntries.length})";
        continue;
      }
      for(var entry in divisionEntries) {
        var rating = this.maybeKnownShooterSync(
          project: project,
          group: group,
          memberNumber: entry.memberNumber,
          useCache: true,
          usePossibleMemberNumbers: true,
        );
        if(rating != null) {
          ratedCompetitorCount++;
          draft.ratedCount++;
          // Use current rating for short-time competitors
          // ignore: dead_code
          if(useCurrentRating || rating.length < shortCompetitorHistory) {
            shooterRatings[entry] = scaler.scaleRating(rating.rating);
            draft.currentRatingCount++;
          }
          // ignore: dead_code
          else {
            var matchRatings = await rating.matchEvents(match);
            if(matchRatings.isNotEmpty) {
              shooterRatings[entry] = scaler.scaleRating(matchRatings.last.newRating);
              draft.matchRatingCount++;
            }
            else {
              draft.ratedWithoutMatchEventCount++;
            }
          }
        }
        else {
          unratedCompetitorCount++;
          draft.unratedCount++;
        }
      }
    }

    final includedDrafts = <_DivisionHeatDraft>[];

    // For each division, calculate divisional heat.
    for(var division in sport.divisions.values) {
      final draft = draftByName[division.name];
      Division finalDivision = division;
      if(sport == uspsaSport && match.sport == ipscSport) {
        var ipscDivision = ipscDivisionForUspsaDivision(division);
        if(ipscDivision == null) {
          _log.w("No IPSC division found for USPSA division: ${division.name}");
          continue;
        }
        finalDivision = ipscDivision;
      }
      var scores = match.getScoresFromFilters(FilterSet(match.sport, divisions: [finalDivision]));

      var competitors = scores.keys.where((e) => e.division == finalDivision).toList();
      var ratedCompetitors = competitors.where((e) => shooterRatings.containsKey(e));
      if(draft != null) {
        draft.scoreCount = competitors.length;
        draft.rawWeight = rawCompetitorCount == 0 ? 0 : competitors.length.toDouble() / rawCompetitorCount.toDouble();
      }

      if(ratedCompetitors.length < 5) {
        // _log.d("Not enough rated competitors for division ${division.name}${finalDivision == division ? "" : " ($finalDivision)"}: ${ratedCompetitors.length}");
        // _log.v("Division: $division Final division: $finalDivision");
        // _log.v("Competitors found: ${scores.length}/${competitors.length}/${ratedCompetitors.length}");
        draft?.skipReason ??= "Fewer than 5 rated competitors with a scaled rating (${ratedCompetitors.length})";
        continue;
      }

      // Finish order: the score map is inserted from best match total to worst.
      final finishRatings = ratedCompetitors.map((e) => shooterRatings[e]!).toList();
      final decileCount = min(finishRatings.length, max(3, (finishRatings.length * 0.1).round()));
      var topTenPercentAverageRating = finishRatings.take(decileCount).average;
      final contenderCount = _topContenderCount(finishRatings.length);
      var topContenderAverageRating = finishRatings.take(contenderCount).average;

      // Get the median rating of rated competitors.
      var medianRating = ratedCompetitors
        .map((e) => shooterRatings[e]!)
        .sorted((a, b) => a.compareTo(b))
        .toList()[ratedCompetitors.length ~/ 2];

      // Get the average classification strength of all competitors.
      var classifications = competitors
        .map((e) => sport.ratingStrengthProvider?.strengthForClass(e.classification))
        .nonNulls;

      var classificationStrength;
      if(classifications.isNotEmpty) {
        classificationStrength = classifications.average;
      }
      else {
        classificationStrength = 1.0;
      }

      double weight = competitors.length.toDouble() / rawCompetitorCount.toDouble();

      if(sport == uspsaSport && match.sport == ipscSport) {
        classificationStrength = uspsaSport.ratingStrengthProvider!.strengthForClass(uspsaA);
      }

      topTenPercentAverageRatings.add(topTenPercentAverageRating);
      weightedTopTenPercentAverageRatings.add((topTenPercentAverageRating, weight));
      topContenderAverageRatings.add(topContenderAverageRating);
      weightedTopContenderAverageRatings.add((topContenderAverageRating, weight));
      medianRatings.add(medianRating);
      weightedMedianRatings.add((medianRating, weight));
      classificationStrengths.add(classificationStrength);
      weightedClassificationStrengths.add((classificationStrength, weight));

      if(draft != null) {
        draft.skipReason = null;
        draft.topTenPercentAverageRating = topTenPercentAverageRating;
        draft.topTenSampleSize = decileCount;
        draft.topContenderAverageRating = topContenderAverageRating;
        draft.topContenderSampleSize = contenderCount;
        draft.medianRating = medianRating;
        draft.classificationStrength = classificationStrength;
        draft.classificationFixedToUspsaA = sport == uspsaSport && match.sport == ipscSport;
        draft.rawWeight = weight;
        includedDrafts.add(draft);
      }
    }

    final normalizedWeights = topTenPercentAverageRatings.isEmpty
        ? const <(double, double)>[]
        : _normalizeWeights(weightedTopTenPercentAverageRatings);
    for(var i = 0; i < includedDrafts.length && i < normalizedWeights.length; i++) {
      includedDrafts[i].normalizedWeight = normalizedWeights[i].$2;
    }

    final divisions = drafts.map(_contributionFromDraft).toList();
    if(topTenPercentAverageRatings.isEmpty) {
      _log.w("No top ten percent average ratings for match: ${ptr.name}");
      final failed = MatchHeatCalculation(
        heat: null,
        failureReason: "No division had 5 or more rated competitors",
        matchName: match.name,
        matchDate: match.date,
        rawCompetitorCount: rawCompetitorCount,
        ratedCompetitorCount: ratedCompetitorCount,
        unratedCompetitorCount: unratedCompetitorCount,
        divisions: divisions,
      );
      if(logBreakdown) {
        _log.i(failed.describe());
      }
      return failed;
    }

    // The match heat is (for now) the average of divisional heats.
    final heat = MatchHeat(
      projectId: project.id,
      matchPointer: ptr,
      topTenPercentAverageRating: topTenPercentAverageRatings.average,
      weightedTopTenPercentAverageRating: _calculateWeightedAverage(weightedTopTenPercentAverageRatings),
      topContenderAverageRating: topContenderAverageRatings.average,
      weightedTopContenderAverageRating: _calculateWeightedAverage(weightedTopContenderAverageRatings),
      medianRating: medianRatings.average,
      weightedMedianRating: _calculateWeightedAverage(weightedMedianRatings),
      classificationStrength: classificationStrengths.average,
      weightedClassificationStrength: _calculateWeightedAverage(weightedClassificationStrengths),
      rawCompetitorCount: rawCompetitorCount,
      ratedCompetitorCount: ratedCompetitorCount,
      unratedCompetitorCount: unratedCompetitorCount,
    );
    final calculation = MatchHeatCalculation(
      heat: heat,
      failureReason: null,
      matchName: match.name,
      matchDate: match.date,
      rawCompetitorCount: rawCompetitorCount,
      ratedCompetitorCount: ratedCompetitorCount,
      unratedCompetitorCount: unratedCompetitorCount,
      divisions: divisions,
    );
    if(logBreakdown) {
      _log.i(calculation.describe());
    }
    return calculation;
  }

  DivisionHeatContribution _contributionFromDraft(_DivisionHeatDraft draft) {
    return DivisionHeatContribution(
      divisionName: draft.divisionName,
      divisionShortName: draft.divisionShortName,
      scoredDivisionName: draft.scoredDivisionName,
      groupName: draft.groupName,
      groupUuid: draft.groupUuid,
      rosterCount: draft.rosterCount,
      scoreCount: draft.scoreCount,
      ratedCount: draft.ratedCount,
      unratedCount: draft.unratedCount,
      currentRatingCount: draft.currentRatingCount,
      matchRatingCount: draft.matchRatingCount,
      ratedWithoutMatchEventCount: draft.ratedWithoutMatchEventCount,
      groupMinRating: draft.groupMinRating,
      groupMaxRating: draft.groupMaxRating,
      topTenPercentAverageRating: draft.topTenPercentAverageRating,
      topTenSampleSize: draft.topTenSampleSize,
      topContenderAverageRating: draft.topContenderAverageRating,
      topContenderSampleSize: draft.topContenderSampleSize,
      medianRating: draft.medianRating,
      classificationStrength: draft.classificationStrength,
      classificationFixedToUspsaA: draft.classificationFixedToUspsaA,
      rawWeight: draft.rawWeight,
      normalizedWeight: draft.normalizedWeight,
      skipReason: draft.skipReason,
    );
  }


  /// How many highest-rated competitors to average for the top-end heat.
  ///
  /// Linear from 3 to 24 as [ratedCount] goes from 0 to 400, then 24.
  /// Twenty-four is about two super squads, the realistic contending group
  /// including long shots. The result is also capped at [ratedCount].
  int _topContenderCount(int ratedCount) {
    if(ratedCount <= 0) {
      return 0;
    }
    final lerped = (3 + ratedCount * (24 - 3) / 400.0).round();
    return min(ratedCount, lerped.clamp(3, 24));
  }

  /// Calculate a weighted average of a list of tuples, where the first element is the value
  /// and the second element is the weight.
  double _calculateWeightedAverage(List<(double, double)> weightedValues) {
    var normalizedWeights = _normalizeWeights(weightedValues);
    return normalizedWeights.map((e) => e.$1 * e.$2).sum;
  }

  /// Normalize the weights of a list of tuples, where the first element is the value
  /// and the second element is the weight, so that the weights sum to 1.
  List<(double, double)> _normalizeWeights(List<(double, double)> weightedValues) {
    var sum = weightedValues.map((e) => e.$2).sum;
    return weightedValues.map((e) => (e.$1, e.$2 / sum)).toList();
  }

  Future<RatingScalerInfo> _calculateGroupInfo(AnalystDatabase db, DbRatingProject project, RatingGroup group) async {
    var ratingsRes = await project.getRatings(group);
    if(ratingsRes.isErr()) {
      _log.w("Error getting ratings for group ${group.name}: ${ratingsRes.unwrapErr()}");
      return RatingScalerInfo.empty();
    }
    var ratings = ratingsRes.unwrap();

    // We're using a StandardizedMaximumScaler, so we can skip everything except the min and max ratings.
    var sortedRatings = ratings.map((e) => e.rating).sorted((a, b) => b.compareTo(a));
    return RatingScalerInfo(
      minRating: sortedRatings.last,
      maxRating: sortedRatings.first,
      ratingDistribution: WeibullDistribution(1, 1),
      top2PercentAverage: 0,
      ratingMean: 0,
      ratingStdDev: 1,
    );
  }
}
