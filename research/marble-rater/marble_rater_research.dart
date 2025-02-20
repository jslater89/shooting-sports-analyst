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
  final competitors = generateCompetitors(200, startingId: 0);

  for(int i = 0; i < 4; i++) {
    int matchSize = rng.nextInt(75) + 125;
    var matchCompetitors = competitors.sample(matchSize);
    var match = Match(matchCompetitors, model: PowerLawModel(power: 1));
    match.calculateResults();
    match.distributeMarbles();

    // var newCompetitors = generateCompetitors(4, startingId: currentId);
    // competitors.addAll(newCompetitors);
    // currentId += 4;
  }

  competitors.sort((a, b) => b.marbles.compareTo(a.marbles));

  var scoring = InversePlaceScoring();
  for(var competitor in competitors) {
    if(competitor.outcomes.isEmpty) {
      continue;
    }
    scoring.calculatePoints(competitor.outcomes);
    var bestScores = scoring.getBestScores(competitor.outcomes, 3).map((e) => e.ratingScore);
    competitor.score = bestScores.sum;
  }

  var competitorsByScore = competitors.sorted((a, b) => b.score.compareTo(a.score));
  var competitorsByOrdinalMu = competitors.sorted((a, b) => (b.ordinalMu).compareTo(a.ordinalMu));

  // Draw distribution
  const int bucketSize = 20; // marbles per bucket
  const int maxBuckets = 40; // maximum number of buckets to show
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

  // Print top 5 competitors in three columns with details
  print("\nTop Competitors By Category:");
  print("Rank  By Marbles                             By Score                               By Mu");
  print("─" * 116);  // 100-char wide dividing line
  
  for (int i = 0; i < 5; i++) {
    final byMarbles = competitors[i];
    final byScore = competitorsByScore[i];
    final byMu = competitorsByOrdinalMu[i];
    
    // First line: IDs and values
    print(
      "${i+1}.    "
      "ID ${byMarbles.id.toString().padRight(4)} "
      "Ma:${byMarbles.marbles.toString().padRight(4)} "
      "S:${byMarbles.score.toStringAsFixed(1).padRight(4)} "
      "Mu:${byMarbles.mu.toStringAsFixed(2)}        "
      
      "ID ${byScore.id.toString().padRight(4)} "
      "Ma:${byScore.marbles.toString().padRight(4)} "
      "S:${byScore.score.toStringAsFixed(1).padRight(4)} "
      "Mu:${byScore.mu.toStringAsFixed(2)}        "
      
      "ID ${byMu.id.toString().padRight(4)} "
      "Ma:${byMu.marbles.toString().padRight(4)} "
      "S:${byMu.score.toStringAsFixed(1).padRight(4)} "
      "Mu:${byMu.mu.toStringAsFixed(2)}"
    );
    
    // Second line: rankings
    // Second line: rankings and sigma
    print(
      "       "
      "MuR:${(competitorsByOrdinalMu.indexOf(byMarbles) + 1).toString().padLeft(2)}, "
      "SR:${(competitorsByScore.indexOf(byMarbles) + 1).toString().padLeft(2)}, "
      "oMu:${byMarbles.ordinalMu.toStringAsFixed(2)}, "
      "σ:${byMarbles.sigma.toStringAsFixed(2)}        "
      
      "MuR:${(competitorsByOrdinalMu.indexOf(byScore) + 1).toString().padLeft(2)}, "
      "MaR:${(competitors.indexOf(byScore) + 1).toString().padLeft(2)}, "
      "oMu:${byScore.ordinalMu.toStringAsFixed(2)}, "
      "σ:${byScore.sigma.toStringAsFixed(2)}       "
      
      "MaR:${(competitors.indexOf(byMu) + 1).toString().padLeft(2)}, "
      "SR:${(competitorsByScore.indexOf(byMu) + 1).toString().padLeft(2)}, "
      "oMu:${byMu.ordinalMu.toStringAsFixed(2)}, "
      "σ:${byMu.sigma.toStringAsFixed(2)}"
    );
  }
  
  print("\nCorrelation between mu and marbles: ${calculateMarblesCorrelation(competitors).toStringAsFixed(3)}");
  
  // printMagnitudeComparison(competitors);

  print("\nCorrelation between mu and score: ${calculateScoreCorrelation(competitors).toStringAsFixed(3)}");
}


// Calculate magnitude ratios
void printMagnitudeComparison(List<Competitor> competitors) {
  // Sort by mu and marbles
  var byMu = List.of(competitors)..sort((a, b) => b.mu.compareTo(a.mu));
  var byMarbles = List.of(competitors)..sort((a, b) => b.marbles.compareTo(a.marbles));
  
  // Get top and bottom (excluding zero marbles for fairness)
  var topMu = byMu.first.mu;
  var bottomMu = byMu.last.mu;
  var topMarbles = byMarbles.first.marbles;
  var bottomMarbles = byMarbles.reversed.firstWhere((c) => c.marbles > 0).marbles;
  
  print("\nMagnitude Comparisons:");
  print("Mu ratio (top/bottom): ${(topMu/bottomMu).toStringAsFixed(3)}");
  print("Marbles ratio (top/bottom): ${(topMarbles/bottomMarbles).toStringAsFixed(3)}");
  
  // Also show absolute values
  print("\nTop mu: ${topMu.toStringAsFixed(3)}, Bottom mu: ${bottomMu.toStringAsFixed(3)}");
  print("Top marbles: $topMarbles, Bottom marbles: $bottomMarbles");
}

double calculateMarblesCorrelation(List<Competitor> competitors, {double sigmaOffset = 0.0}) {
  var n = competitors.length;
  
  // Get means
  double muMean = competitors.map((c) => c.mu - sigmaOffset * c.sigma).average;
  double marblesMean = competitors.map((c) => c.marbles).average;
  
  // Calculate covariance and standard deviations
  double covariance = 0;
  double muVariance = 0;
  double marblesVariance = 0;
  
  for (final competitor in competitors) {
    double muDiff = competitor.mu - muMean;
    double marblesDiff = competitor.marbles - marblesMean;
    
    covariance += muDiff * marblesDiff;
    muVariance += muDiff * muDiff;
    marblesVariance += marblesDiff * marblesDiff;
  }
  
  covariance /= n;
  double muStdDev = sqrt(muVariance / n);
  double marblesStdDev = sqrt(marblesVariance / n);
  
  return covariance / (muStdDev * marblesStdDev);
}

double calculateScoreCorrelation(List<Competitor> competitors, {double sigmaOffset = 0.0}) {
  var n = competitors.length;
  
  // Get means
  double muMean = competitors.map((c) => c.mu - sigmaOffset * c.sigma).average;
  double scoreMean = competitors.map((c) => c.score).average;
  
  // Calculate covariance and standard deviations
  double covariance = 0;
  double muVariance = 0;
  double scoreVariance = 0;
  
  for (final competitor in competitors) {
    double muDiff = competitor.mu - muMean;
    double scoreDiff = competitor.score - scoreMean;
    
    covariance += muDiff * scoreDiff;
    muVariance += muDiff * muDiff;
    scoreVariance += scoreDiff * scoreDiff;
  }
  
  covariance /= n;
  double muStdDev = sqrt(muVariance / n);
  double scoreStdDev = sqrt(scoreVariance / n);
  
  return covariance / (muStdDev * scoreStdDev);
}

List<Competitor> generateCompetitors(int count, {int startingId = 0}) {
  // Weibull distribution with shape parameter k ≈ 3.5-4.0 tends to model skill well
  // It gives us the right-tailed distribution we observe in real competition
  return List.generate(count, (index) {
    // Generate Weibull random number using inverse transform sampling
    final u = rng.nextDouble();
    final shape = 3.75;  // k parameter (shape)
    final scale = 1; // λ parameter (scale)
    
    // Weibull inverse CDF: λ * (-ln(1-u))^(1/k)
    final mu = scale * pow(-log(1 - u), 1/shape);
    final sigma = rng.nextDouble() * 0.15 + 0.05; // Keep same sigma distribution
    
    return Competitor(id: startingId + index, mu: mu.toDouble(), sigma: sigma.toDouble());
  });
}

class Competitor {
  final int id;
  final double mu;    // Mean performance level (percentage)
  final double sigma; // Standard deviation of performance
  int marbles;        // Current marble count
  double score;       // Current score

  double get ordinalMu => mu - sigma;
  List<CompetitorOutcome> outcomes = [];
  Competitor({
    required this.id,
    required this.mu,
    required this.sigma,
    this.marbles = 200, // Starting with standard marble count
    this.score = 0,
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
      "ordinalMu: ${ordinalMu.toStringAsFixed(2)}, "
      "marbles: $marbles, "
      "score: ${score.toStringAsFixed(2)})";
}

class CompetitorOutcome {
  int place;
  int totalCompetitors;
  double matchScore;
  double ratingScore;
  int marblesStaked;
  int marblesWon;
  int matchStake;

  CompetitorOutcome({
    required this.place,
    required this.matchScore,
    required this.marblesStaked,
    required this.matchStake,
    required this.totalCompetitors,
    required this.marblesWon,
    required this.ratingScore,
  });

  @override
  String toString() {
    return "place: $place/$totalCompetitors, score: ${matchScore.toStringAsFixed(2)}, "
    "marbles won/staked/available: $marblesWon/$marblesStaked/$matchStake, "
    "rating score: ${ratingScore.toStringAsFixed(2)}";
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
        matchScore: 0,  // Will be set in calculateResults
        marblesStaked: stake,
        matchStake: 0, // Will be set in calculateResults
        totalCompetitors: competitors.length,
        marblesWon: 0,  // Will be set in distributeMarbles
        ratingScore: 0, // Will be set in a cumulative scorer
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
      outcomes[competitor]!.matchScore = results[competitor]!;
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
      outcomes[competitor]!.marblesStaked = stakes[competitor]!;
      outcomes[competitor]!.matchStake = totalStake;
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

/// Interface for cumulative scoring systems
abstract class CumulativeScoring {
  /// Calculate points for a list of match outcomes, updating them in place.
  void calculatePoints(List<CompetitorOutcome> outcomes);
  
  /// Get best N of M matches
  List<CompetitorOutcome> getBestScores(List<CompetitorOutcome> outcomes, int n) {
    outcomes.sort((a, b) => b.ratingScore.compareTo(a.ratingScore));
    return outcomes.take(n).toList();
  }
}

/// Points based on percentage finish (100% for 1st, down to 0%)
class PercentFinishScoring extends CumulativeScoring {
  @override
  void calculatePoints(List<CompetitorOutcome> outcomes) {
    for(var outcome in outcomes) {
      outcome.ratingScore = outcome.matchScore * 100.0;
    }
  }
}

/// Points based on number of competitors beaten
class InversePlaceScoring extends CumulativeScoring {
  @override
  void calculatePoints(List<CompetitorOutcome> outcomes) {
    for(var outcome in outcomes) {
      outcome.ratingScore = (outcome.totalCompetitors - outcome.place + 1).toDouble();
    }
  }
}

/// F1-style points system (25, 18, 15, 12, 10, 8, 6, 4, 2, 1)
class F1Scoring extends CumulativeScoring {
  static const points = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1];
  
  @override
  void calculatePoints(List<CompetitorOutcome> outcomes) {
    for(var outcome in outcomes) {
      outcome.ratingScore = points[outcome.place - 1].toDouble();
    }
  }
}
