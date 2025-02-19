/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';

final rng = Random();

void main() {
  int currentId = 1000;
  final competitors = generateCompetitors(1000, startingId: 0);

  for(int i = 0; i < 250; i++) {
    int matchSize = rng.nextInt(125) + 25;
    var matchCompetitors = competitors.sample(matchSize);
    var match = Match(matchCompetitors, model: OrdinalPowerModel(power: 2));
    match.calculateResults();
    match.distributeMarbles();

    var newCompetitors = generateCompetitors(4, startingId: currentId);
    competitors.addAll(newCompetitors);
    currentId += 4;
  }

  competitors.sort((a, b) => b.marbles.compareTo(a.marbles));

  // Draw distribution
  const int bucketSize = 50; // marbles per bucket
  const int maxBuckets = 20; // maximum number of buckets to show
  Map<int, int> distribution = {};
  
  // Count competitors in each bucket
  for (var competitor in competitors) {
    int bucket = (competitor.marbles / bucketSize).floor() * bucketSize;
    distribution[bucket] = (distribution[bucket] ?? 0) + 1;
  }
  
  // Find the bucket with most competitors for scaling
  int maxCount = distribution.values.max;
  
  // Print distribution
  print("\nMarble Distribution (each █ = ${(maxCount / 40).ceil()} competitors):");
  print("Marbles | Count");
  print("-" * 50);
  
  var sortedBuckets = distribution.keys.toList()..sort();
  for (var bucket in sortedBuckets.take(maxBuckets)) {
    int count = distribution[bucket]!;
    int bars = (count * 40 / maxCount).round();
    print("${bucket.toString().padLeft(7)} | ${"█" * bars} ($count)");
  }

  // Print the full history for the top 5 competitors
  for(int i = 0; i < 5; i++) {
    print("${i+1}-th competitor: ${competitors[i]}");
    print(competitors[i].outcomes.join("\n"));
    print("\n\n");
  }

  // Print the full history for a competitor in the middle of the pack
  print("Middle competitor: ${competitors[competitors.length ~/ 2]}");
  print(competitors[competitors.length ~/ 2].outcomes.join("\n"));
  print("\n\n");

  // Print the full history for the worst competitor who still has marbles
  print("Worst competitor: ${competitors.reversed.firstWhere((c) => c.marbles > 0)}");
  print(competitors.reversed.firstWhere((c) => c.marbles > 0).outcomes.join("\n"));
}


List<Competitor> generateCompetitors(int count, {int startingId = 0}) {
  // Competitor mu is normally distributed with mu=0.75, sigma=0.15.
  // Competitor sigma is uniformly distributed between 0.05 and 0.20.
  return List.generate(count, (index) {
    final mu = randomNormalDistribution(0.75, 0.15);
    final sigma = rng.nextDouble() * 0.15 + 0.05;
    return Competitor(id: startingId + index, mu: mu, sigma: sigma);
  });
}

class Competitor {
  final int id;
  final double mu;    // Mean performance level (percentage)
  final double sigma; // Standard deviation of performance
  int marbles;        // Current marble count
  List<CompetitorOutcome> outcomes = [];
  Competitor({
    required this.id,
    required this.mu,
    required this.sigma,
    this.marbles = 150, // Starting with standard marble count
  });

  /// Simulate a match performance using a normal distribution
  double simulatePerformance() {
    return randomNormalDistribution(mu, sigma);
  }

  /// Calculate marble stake for a match
  int calculateStake() {
    if(marbles <= 5) {
      return 0;
    }
    return (marbles * 0.20).round(); // 20% stake, rounded to nearest integer
  }

  int takeStake() {
    final stake = calculateStake();
    marbles -= stake;
    return stake;
  }

  @override
  String toString() => 
      "Competitor(id: $id, mu: ${mu.toStringAsFixed(2)}, "
      "sigma: ${sigma.toStringAsFixed(2)}, "
      "marbles: $marbles)";
}

class CompetitorOutcome {
  int place;
  int totalCompetitors;
  double score;
  int marblesStaked;
  int marblesWon;
  int matchStake;

  CompetitorOutcome({
    required this.place,
    required this.score,
    required this.marblesStaked,
    required this.matchStake,
    required this.totalCompetitors,
    required this.marblesWon
  });

  @override
  String toString() {
    return "place: $place/$totalCompetitors, score: ${score.toStringAsFixed(2)}, "
    "marbles won/staked/available: $marblesWon/$marblesStaked/$matchStake";
  }
}

/// Generate a random number normally distributed according to mu and sigma
/// using the Box-Muller transform.
double randomNormalDistribution(double mu, double sigma) {
  double u1 = rng.nextDouble();
  double u2 = rng.nextDouble();
  double z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  return mu + z * sigma;
}

class Match {
  final List<Competitor> competitors;
  final MarbleModel model;
  late final int totalStake;
  
  Map<Competitor, double> results = {};
  Map<Competitor, CompetitorOutcome> outcomes = {};

  Match(this.competitors, {this.model = const PowerLawModel()}) {
    var stakes = <int>[];
    int innerStake = 0;
    
    for (final competitor in competitors) {
      final stake = competitor.takeStake();
      stakes.add(stake);
      innerStake += stake;
      
      outcomes[competitor] = CompetitorOutcome(
        place: 0,  // Will be set in calculateResults
        score: 0,  // Will be set in calculateResults
        marblesStaked: stake,
        matchStake: 0, // Will be set in calculateResults
        totalCompetitors: competitors.length,
        marblesWon: 0  // Will be set in distributeMarbles
      );
    }

    totalStake = innerStake;
  }

  /// Calculate the results of the match, storing a simulated performance
  /// in [results], and then sorting [competitors] by performance.
  void calculateResults() {
    Map<Competitor, double> intermediateResults = Map.fromEntries(competitors.map((c) => MapEntry(c, c.simulatePerformance())));

    // Normalize to between 0 and 1, since we may have 'percentages' > 1.0 or < 0.0.
    var bestResult = intermediateResults.values.max;
    var worstResult = intermediateResults.values.min;
    for(var result in intermediateResults.entries) {
      results[result.key] = (result.value - worstResult) / (bestResult - worstResult);
    }

    competitors.sort((a, b) => results[b]!.compareTo(results[a]!));

    // Update outcomes with places and scores
    for (int i = 0; i < competitors.length; i++) {
      final competitor = competitors[i];
      outcomes[competitor]!.place = i + 1;
      outcomes[competitor]!.score = results[competitor]!;
    }
  }

  /// Distribute the total stake according to the performance of each competitor.
  void distributeMarbles() {
    final stakes = Map.fromEntries(
      outcomes.entries.map((e) => MapEntry(e.key, e.value.marblesStaked))
    );
    
    final distribution = model.distributeMarbles(
      results: results,
      stakes: stakes,
      totalStake: totalStake,
    );
    
    // Update competitors and outcomes
    for (final entry in distribution.entries) {
      final competitor = entry.key;
      final marbles = entry.value;
      competitor.marbles += marbles;
      outcomes[competitor]!.marblesWon = marbles;
      competitor.outcomes.add(outcomes[competitor]!);
    }
  }
}

/// Interface for different marble distribution models
abstract class MarbleModel {
  /// Calculate marble distribution based on performance
  /// 
  /// [results] maps competitors to their normalized performance (0.0-1.0)
  /// [stakes] maps competitors to their staked marble count
  /// Returns a map of competitors to their marble winnings
  Map<Competitor, int> distributeMarbles({
    required Map<Competitor, double> results,
    required Map<Competitor, int> stakes,
    required int totalStake,
  });
}

/// Power law distribution model where share = performance^power
class PowerLawModel implements MarbleModel {
  final double power;
  
  const PowerLawModel({this.power = 2.5});

  @override
  Map<Competitor, int> distributeMarbles({
    required Map<Competitor, double> results,
    required Map<Competitor, int> stakes,
    required int totalStake,
  }) {
    final maxPerformance = results.values.max;
    
    // Calculate shares using power law
    double sumShares = 0;
    final shares = <Competitor, double>{};
    
    for (final entry in results.entries) {
      final competitor = entry.key;
      final relativeScore = entry.value / maxPerformance;
      final share = pow(relativeScore, power).toDouble();
      shares[competitor] = share;
      sumShares += share;
    }
    
    // Distribute marbles proportionally
    return Map.fromEntries(
      shares.entries.map((entry) => MapEntry(
        entry.key,
        (totalStake * entry.value / sumShares).round()
      ))
    );
  }
}

/// Sigmoid distribution model where share = 1/(1 + e^(-steepness * (x - midpoint)))
class SigmoidModel implements MarbleModel {
  final double steepness;
  final double midpoint;
  
  const SigmoidModel({
    this.steepness = 6.0,  // Controls how sharp the S-curve is
    this.midpoint = 0.75,    // Point of inflection (0.0-1.0)
  });

  @override
  Map<Competitor, int> distributeMarbles({
    required Map<Competitor, double> results,
    required Map<Competitor, int> stakes,
    required int totalStake,
  }) {
    final maxPerformance = results.values.max;
    
    // Calculate shares using sigmoid function
    double sumShares = 0;
    final shares = <Competitor, double>{};
    
    for (final entry in results.entries) {
      final competitor = entry.key;
      final relativeScore = entry.value / maxPerformance;
      // Sigmoid function: 1/(1 + e^(-steepness * (x - midpoint)))
      final share = 1.0 / (1.0 + exp(-steepness * (relativeScore - midpoint)));
      shares[competitor] = share;
      sumShares += share;
    }
    
    // Distribute marbles proportionally
    return Map.fromEntries(
      shares.entries.map((entry) => MapEntry(
        entry.key,
        (totalStake * entry.value / sumShares).round()
      ))
    );
  }
}

/// Distribution model based on ordinal finish position rather than score
class OrdinalPowerModel implements MarbleModel {
  final double power;  // Controls how steeply rewards drop off by place
  
  const OrdinalPowerModel({this.power = 2});

  @override
  Map<Competitor, int> distributeMarbles({
    required Map<Competitor, double> results,
    required Map<Competitor, int> stakes,
    required int totalStake,
  }) {
    // Sort competitors by performance
    var sortedCompetitors = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Calculate shares based on place
    double sumShares = 0;
    final shares = <Competitor, double>{};
    
    for (int i = 0; i < sortedCompetitors.length; i++) {
      final competitor = sortedCompetitors[i].key;
      // Convert place to a 0-1 scale where 1st = 1.0, last = 0.0
      final relativePlace = (sortedCompetitors.length - i) / sortedCompetitors.length;
      final share = pow(relativePlace, power).toDouble();
      shares[competitor] = share;
      sumShares += share;
    }
    
    // Distribute marbles proportionally
    return Map.fromEntries(
      shares.entries.map((entry) => MapEntry(
        entry.key,
        (totalStake * entry.value / sumShares).round()
      ))
    );
  }
}


