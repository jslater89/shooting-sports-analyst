import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/util.dart';

/// A connectivity calculator that identifies rating carriers based on
/// encounter volume, match diversity, and bridge behavior patterns.
///
/// This calculator uses aggregate statistics to efficiently track competitive
/// breadth without storing individual competitor IDs.
class RatingCarrierConnectivityCalculator implements ConnectivityCalculator {

  @override
  NewConnectivity calculateRatingConnectivity(DbShooterRating rating) {
    double connectivity = getConnectivityScore(rating.aggregateConnectivityData);
    double rawConnectivity = rating.aggregateConnectivityData.totalEncounters.toDouble();

    return NewConnectivity(
      connectivity: connectivity,
      rawConnectivity: rawConnectivity,
    );
  }

  @override
  double calculateConnectivityBaseline({
    int? matchCount,
    int? competitorCount,
    double? connectivitySum,
    List<double>? connectivityScores,
  }) {
    if (connectivityScores == null || connectivityScores.isEmpty) {
      return defaultBaselineConnectivity;
    }

    var max = connectivityScores.max;

    var nonzeroScores = connectivityScores.where((score) => score != 0);
    if(nonzeroScores.isEmpty) return max > 0 ? max * 0.5 : 0;
    return nonzeroScores.average * nonzeroScores.length / connectivityScores.length;
  }

  @override
  double calculateMatchConnectivity(List<double> connectivityScores) {
    if (connectivityScores.isEmpty) return 0;

    var max = connectivityScores.max;

    var nonzeroScores = connectivityScores.where((score) => score != 0);
    if(nonzeroScores.isEmpty) return max > 0 ? max * 0.5 : 0;
    return nonzeroScores.average * nonzeroScores.length / connectivityScores.length;
  }

  @override
  double getScaleFactor({
    required double connectivity,
    required double baseline,
    double minScale = 0.8,
    double baselineScale = 1.0,
    double maxScale = 1.2,
  }) {
    return lerpAroundCenter(
      value: connectivity,
      center: baseline,
      minOut: minScale,
      centerOut: baselineScale,
      maxOut: maxScale,
    );
  }

  @override
  bool updateCompetitorData({
    required DbShooterRating rating,
    ShootingMatch? match,
    List<MatchPointer>? matchPointers,
    Iterable<DbShooterRating>? competitors,
    int? competitorCount,
  }) {
    // Add this match to the rating carrier data
    rating.aggregateConnectivityData.addMatch(competitorCount!);

    return true; // Indicate that the data was updated
  }

  @override
  int get matchWindowCount => 5; // Keep consistent with existing system

  @override
  int get baselineMatchWindowCount => 100; // Keep consistent with existing system

  @override
  List<BaselineConnectivityRequiredData> get requiredBaselineData => [
    BaselineConnectivityRequiredData.connectivityScores,
  ];

  @override
  List<CompetitorConnectivityRequiredData> get requiredCompetitorData => [
    CompetitorConnectivityRequiredData.competitorCount,
  ];

  @override
  double get defaultBaselineConnectivity => 1.0;

  @override
  bool rollbackCompetitorData({
    required DbShooterRating rating,
    List<ShootingMatch>? matchesRemoved,
    List<MatchPointer>? matchPointers,
    Iterable<Iterable<DbShooterRating>>? competitorsRemoved,
    Iterable<int>? competitorCountsRemoved,
  }) {
    for(var count in competitorCountsRemoved!) {
      rating.aggregateConnectivityData.removeMatch(count);
    }
    return true;
  }

  // This is simple enough that we don't need to use history for rollback.
  @override
  bool get useHistoryForRollback => false;

  double getConnectivityScore(AggregateConnectivityData data) {
    if (data.matchCount == 0) return 0.0;

    // Core metric: size of recent competitive fields
    double fieldQualityScore = _calculateFieldQualityScore(data);

    // Bonus for diversity in field sizes (network bridge behavior)
    double diversityBonus = _calculateDiversityBonus(data);

    // Bonus for positive skewness (local + major pattern)
    double bridgeBonus = _calculateBridgeBonus(data);

    return fieldQualityScore * diversityBonus * bridgeBonus;
  }

double _calculateFieldQualityScore(AggregateConnectivityData data) {
  List<int> recentMatches = _getRecentMatches(data);
  if (recentMatches.isEmpty) return 0.0;

  // Weight more recent matches more heavily
  double weightedSum = 0.0;
  double totalWeight = 0.0;

  for (int i = 0; i < recentMatches.length; i++) {
    double weight = 1.0 + (i * 0.2); // Most recent gets highest weight
    weightedSum += recentMatches[i] * weight;
    totalWeight += weight;
  }

  double weightedAverage = weightedSum / totalWeight;
  return sqrt(weightedAverage) * 25;
}

  double _calculateEncounterScore(AggregateConnectivityData data) {
    List<int> recentMatches = _getRecentMatches(data);
    int recentTotalEncounters = recentMatches.sum;

    return sqrt(recentTotalEncounters) * 20; // Scale factor
  }

  double _calculateDiversityBonus(AggregateConnectivityData data) {
    List<int> recentMatches = _getRecentMatches(data);
    if (recentMatches.length <= 1) return 1.0;

    // Calculate statistics from recent matches only
    double recentTotalEncounters = recentMatches.sum.toDouble();
    double recentAverageSize = recentTotalEncounters / recentMatches.length;

    double recentSumSquared = recentMatches.map((size) => size * size).sum.toDouble();
    double recentVariance = (recentSumSquared / recentMatches.length) - (recentAverageSize * recentAverageSize);

    double recentSizeRange = (recentMatches.reduce(max) - recentMatches.reduce(min)).toDouble();

    // Apply the same logarithmic bonuses to recent data
    double varianceBonus = 1.0 + log(sqrt(recentVariance) + 1) * 0.05;
    double rangeBonus = 1.0 + log(recentSizeRange + 1) * 0.03;

    return varianceBonus * rangeBonus;
  }

  double _calculateConsistencyBonus(AggregateConnectivityData data) {
    List<int> recentMatches = _getRecentMatches(data);

    // Reward sustained competition based on recent activity
    return 1.0 + log(recentMatches.length + 1) * 0.1;
  }

  double _calculateBridgeBonus(AggregateConnectivityData data) {
    List<int> recentMatches = _getRecentMatches(data, windowSize: 12);
    if (recentMatches.length < 3) return 1.0;

    double skewness = _calculateRecentSkewness(recentMatches);

    // Same logic as before, but based on recent matches
    if (skewness > 0) {
      return 1.0 + (skewness * 0.1).clamp(0.0, 0.2);
    }
    return 1.0 + (skewness * 0.05).clamp(-0.1, 0.0);
  }

  /// Get the most recent N matches (default 5)
  List<int> _getRecentMatches(AggregateConnectivityData data, {int windowSize = 5}) {
    if (data.matchSizes.length <= windowSize) {
      return data.matchSizes; // Return all if we have fewer than window size
    }

    // Return the last N matches
    return data.matchSizes.sublist(data.matchSizes.length - windowSize);
  }

  double _calculateRecentSkewness(List<int> recentMatches) {
    if (recentMatches.length < 3) return 0.0;

    double recentTotal = recentMatches.sum.toDouble();
    double mean = recentTotal / recentMatches.length;

    double sumSquared = recentMatches.map((size) => size * size).sum.toDouble();
    double variance = (sumSquared / recentMatches.length) - (mean * mean);
    double stdDev = sqrt(variance);

    if (stdDev == 0) return 0.0;

    double sumCubed = recentMatches.map((size) => size * size * size).sum.toDouble();
    double thirdMoment = (sumCubed / recentMatches.length) -
                        (3 * mean * variance) -
                        (mean * mean * mean);

    return thirdMoment / (stdDev * stdDev * stdDev);
  }

  /// For debugging and tuning
  Map<String, dynamic> getDebugInfo(AggregateConnectivityData data) {
    List<int> recentMatches = _getRecentMatches(data);

    return {
      'totalEncounters': data.totalEncounters,
      'totalMatchCount': data.matchCount,
      'recentMatches': recentMatches,
      'recentEncounters': recentMatches.sum,
      'recentMatchCount': recentMatches.length,
      'recentAverageSize': recentMatches.isNotEmpty ? recentMatches.sum / recentMatches.length : 0,
      'allMatchSizes': data.matchSizes,
      'encounterScore': _calculateEncounterScore(data),
      'diversityBonus': _calculateDiversityBonus(data),
      'consistencyBonus': _calculateConsistencyBonus(data),
      'bridgeBonus': _calculateBridgeBonus(data),
      'recentSkewness': recentMatches.length >= 3 ? _calculateRecentSkewness(recentMatches) : 0.0,
      'finalScore': getConnectivityScore(data),
    };
  }
}
