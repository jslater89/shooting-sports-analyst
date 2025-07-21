import 'dart:math';

import 'package:collection/collection.dart';
import 'package:data/stats.dart' show WeibullDistribution;
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';

final _log = SSALogger("MatchHeatDatabase");

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
    var project = await getRatingProjectById(ratingProjectId);
    if(project == null) {
      _log.w("Rating project not found: $ratingProjectId");
      return null;
    }
    var sport = project.sport;

    Map<String, RatingScaler> scalers = {};
    final useCurrentRating = false;

    var dbMatch = await getMatchByAnySourceId(ptr.sourceIds);
    if(dbMatch == null) {
      _log.w("Match not found: ${ptr.name}");
      return null;
    }
    var matchRes = await HydratedMatchCache().get(dbMatch);
    if(matchRes.isErr()) {
      _log.w("Error hydrating match: ${matchRes.unwrapErr()}");
      return null;
    }
    var match = matchRes.unwrap();
    Map<MatchEntry, double> shooterRatings = {};
    int rawCompetitorCount = match.shooters.length;
    int ratedCompetitorCount = 0;
    int unratedCompetitorCount = 0;
    List<double> topTenPercentAverageRatings = [];
    List<(double, double)> weightedTopTenPercentAverageRatings = [];
    List<double> medianRatings = [];
    List<(double, double)> weightedMedianRatings = [];
    List<double> classificationStrengths = [];
    List<(double, double)> weightedClassificationStrengths = [];

    // For each division, find ratings for all rated competitors, ignoring divisions with fewer than 5 competitors.
    for(var division in sport.divisions.values) {
      var groupRes = await project.groupForDivision(division);

      if(groupRes.isErr()) {
        _log.w("Error getting group for division ${division.name}: ${groupRes.unwrapErr()}");
        continue;
      }
      var group = groupRes.unwrap();
      if(group == null) {
        _log.w("No group found for division: ${division.name}");
        continue;
      }

      var scaler = scalers[group.uuid];
      if(scaler == null) {
        var groupInfo = await _calculateGroupInfo(this, project, group);
        scaler = StandardizedMaximumScaler(info: groupInfo, scaleMax: 2000, scaleMin: 0);
        scalers[group.uuid] = scaler;
      }

      var divisionEntries = match.filterShooters(divisions: [division]);
      if(divisionEntries.length < 5) {
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
          // Use current rating for short-time competitors
          // ignore: dead_code
          if(useCurrentRating || rating.length < 50) {
            shooterRatings[entry] = scaler.scaleRating(rating.rating);
          }
          // ignore: dead_code
          else {
            var matchRatings = await rating.matchEvents(match);
            if(matchRatings.isNotEmpty) {
              shooterRatings[entry] = scaler.scaleRating(matchRatings.last.newRating);
            }
          }
        }
        else {
          unratedCompetitorCount++;
        }
      }
    }

    // For each division, calculate divisional heat.
    for(var division in sport.divisions.values) {
      var scores = match.getScoresFromFilters(FilterSet(sport, divisions: [division]));

      var competitors = scores.keys.where((e) => e.division == division).toList();
      var ratedCompetitors = competitors.where((e) => shooterRatings.containsKey(e));

      if(ratedCompetitors.length < 5) {
        continue;
      }

      // Get the average rating of the top 10%, minimum 3, of rated competitors.
      var topTenPercentAverageRating = ratedCompetitors
        .map((e) => shooterRatings[e]!)
        .take(max(3, (ratedCompetitors.length * 0.1).round()))
        .average;

      // Get the median rating of rated competitors.
      var medianRating = ratedCompetitors
        .map((e) => shooterRatings[e]!)
        .sorted((a, b) => a.compareTo(b))
        .toList()[ratedCompetitors.length ~/ 2];

      // Get the average classification strength of all competitors.
      var classificationStrength = competitors
        .map((e) => sport.ratingStrengthProvider?.strengthForClass(e.classification))
        .whereNotNull()
        .average;

      double weight = competitors.length.toDouble() / rawCompetitorCount.toDouble();

      topTenPercentAverageRatings.add(topTenPercentAverageRating);
      weightedTopTenPercentAverageRatings.add((topTenPercentAverageRating, weight));
      medianRatings.add(medianRating);
      weightedMedianRatings.add((medianRating, weight));
      classificationStrengths.add(classificationStrength);
      weightedClassificationStrengths.add((classificationStrength, weight));
    }

    if(topTenPercentAverageRatings.isEmpty) {
      _log.w("No top ten percent average ratings for match: ${ptr.name}");
      return null;
    }

    // The match heat is (for now) the average of divisional heats.
    return MatchHeat(
      projectId: project.id,
      matchPointer: ptr,
      topTenPercentAverageRating: topTenPercentAverageRatings.average,
      weightedTopTenPercentAverageRating: _calculateWeightedAverage(weightedTopTenPercentAverageRatings),
      medianRating: medianRatings.average,
      weightedMedianRating: _calculateWeightedAverage(weightedMedianRatings),
      classificationStrength: classificationStrengths.average,
      weightedClassificationStrength: _calculateWeightedAverage(weightedClassificationStrengths),
      rawCompetitorCount: rawCompetitorCount,
      ratedCompetitorCount: ratedCompetitorCount,
      unratedCompetitorCount: unratedCompetitorCount,
    );
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
