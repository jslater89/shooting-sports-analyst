import 'dart:math';
import 'package:collection/collection.dart';

void main() {
  print("Generating entities...");
  // Testing some ideas about connectivity in a DB-friendly way.
  var (competitors, matches) = generateEntities();
  
  // Calculate connectivity scores over time
  var connectivityTracker = ConnectivityTracker();
  
  print("Processing matches...");
  // Process matches in chronological order
  int i = 0;
  List<Match> matchWindow = [];
  int matchWindowSize = 100;
  for (var match in matches.values.sorted((a, b) => a.start.compareTo(b.start))) {
    var matchCompetitors = Map.fromEntries(competitors.entries.where((e) => match.competitorIds.contains(e.key)));
    connectivityTracker.processMatch(match, matchWindow, matchCompetitors, competitors);
    i++;

    // Maintain a window of the last 30 matches
    while(matchWindow.length >= matchWindowSize) {
      matchWindow.removeAt(0);
    }
    matchWindow.add(match);
    if(i % 25 == 0) {
      print("Processed $i matches");
    }
  }

  print("Analyzing results...");
  // Analyze results
  analyzeConnectivity(connectivityTracker, competitors, matches);
}

const int highActivityCount = 2500;

(Map<int, Competitor> competitors, Map<int, Match> matches) generateEntities() {
  var random = Random();
  Map<int, Competitor> lowActivityCompetitors = {};
  Map<int, Competitor> highActivityCompetitors = {};
  Map<int, Match> matches = {};

  int initialLowActivityCount = 2500;

  double lowActivityCompetitorRetirementBaseRate = 0.20;
  double lowActivityCompetitorRetirementVariance = 0.05;

  double lowActivityCompetitorGrowthBaseRate = 0.24;
  double lowActivityCompetitorGrowthVariance = 0.03;
  
  // Fixed pool of high-activity competitors
  for(int i = 0; i < highActivityCount; i++) {
    highActivityCompetitors[i] = Competitor(i);
  }
  
  // Initial smaller pool of low-activity competitors
  int nextCompetitorId = highActivityCount;
  for(int i = nextCompetitorId; i < nextCompetitorId + initialLowActivityCount; i++) {
    lowActivityCompetitors[i] = Competitor(i);
  }
  nextCompetitorId += initialLowActivityCount;
  
  print("Generated ${highActivityCompetitors.length} high activity competitors");
  print("Generated ${lowActivityCompetitors.length} initial low activity competitors");

  int totalSize = 0;
  DateTime start = DateTime(2018, 1, 1);
  int currentYear = 2018;
  int minimumLowActivityId = highActivityCount;  // Initial minimum ID for selection
  
  int annualNewCompetitorCount = 0;
  int annualRetirementCount = 0;
  int newCompetitorsPerMatch = 0;
  for(int i = 0; i < 520; i++) {
    matches[i] = Match(i, start);

    var activeIds = lowActivityCompetitors.keys
      .where((id) => id >= minimumLowActivityId)
      .toList();
    
    // Year boundary check
    if (start.year > currentYear) {
      // Retire some existing low-activity competitors, and create new ones.
      annualRetirementCount = (activeIds.length * (random.nextDouble() * lowActivityCompetitorRetirementVariance + lowActivityCompetitorRetirementBaseRate)).round();
      annualNewCompetitorCount = (activeIds.length * (random.nextDouble() * lowActivityCompetitorGrowthVariance + lowActivityCompetitorGrowthBaseRate)).round();
      print("Year ${start.year}: Retiring $annualRetirementCount competitors, adding $annualNewCompetitorCount new competitors over the year");
      currentYear = start.year;
    }

    minimumLowActivityId = activeIds[(annualRetirementCount / 52).round()];  // Move up the minimum ID
    
    // Log-normal distribution for match size
    var mu = log(150);
    var sigma = 0.5;
    var u1 = random.nextDouble();
    var u2 = random.nextDouble();
    var z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
    var size = exp(mu + sigma * z).round().clamp(50, 500);
    totalSize += size;

    // High activity competitors (30-50% of match)
    var highActivitySize = 0.3 + 0.2 * random.nextDouble();
    var lowActivitySize = 1 - highActivitySize;
    var lowActivityCount = (size * lowActivitySize).round();
    
    // Add new competitors from the new pool
    var newCompetitorCount = (annualNewCompetitorCount / 52).round();
    for(int j = 0; j < newCompetitorCount; j++) {
      lowActivityCompetitors[nextCompetitorId] = Competitor(nextCompetitorId);
      nextCompetitorId++;
    }
    // print("Match $i: Added $newCompetitorCount new competitors");
    
    // Select competitors for this match
    var activeLowActivityCompetitors = lowActivityCompetitors.entries
        .where((e) => e.key >= minimumLowActivityId)
        .map((e) => e.value);

    var highActivitySample = highActivityCompetitors.values.sample((size * highActivitySize).round(), random);
    var lowActivitySampleSize = lowActivityCount - newCompetitorCount;
    List<Competitor> lowActivitySample = [];
    if(lowActivitySampleSize > 0) {
      lowActivitySample = activeLowActivityCompetitors.sample(lowActivitySampleSize, random);
    }
        
    var c = highActivitySample
      ..addAll(lowActivitySample)
      ..addAll(lowActivityCompetitors.values
          .where((c) => c.shooterId >= nextCompetitorId - newCompetitorCount));  // Add all new competitors
    
    for(var competitor in c) {
      competitor.matchIds.add(i);
      matches[i]!.competitorIds.add(competitor.shooterId);
    }
    
    start = start.add(Duration(days: 7));
  }

  var competitors = {...lowActivityCompetitors, ...highActivityCompetitors};
  print("\nFinal Statistics:");
  print("Total matches: ${matches.length}");
  print("Total competitors ever: ${competitors.length}");
  print("Active low-activity competitors: ${lowActivityCompetitors.keys.where((id) => id >= minimumLowActivityId).length}");
  print("Total entries: $totalSize");

  return (competitors, matches);
}

class MatchWindow {
  final int matchId;
  final DateTime date;
  final Set<int> uniqueOpponents;
  final int totalOpponents;

  MatchWindow({
    required this.matchId,
    required this.date,
    required this.uniqueOpponents,
    required this.totalOpponents,
  });
}

class Competitor {
  Competitor(this.shooterId);

  final int shooterId;
  final List<int> matchIds = [];
  static const int windowSize = 5;  // Keep last 5 matches
  static const double lowConnectivityLinkWeight = 0.5;
  static const double lowConnectivityLinkScore = 0;
  static const double mediumConnectivityLinkWeight = 1.0;
  static const double mediumConnectivityLinkScore = 40;
  static const double highConnectivityLinkWeight = 2.0;
  static const double highConnectivityLinkScore = 100;
  
  // Store windows in chronological order
  List<MatchWindow> get windows => allWindows.getTailWindow(windowSize);
  List<MatchWindow> allWindows = [];
  double connectivityScore = 0.0;
  double rawConnectivityScore = 0.0;

  void addMatch(int matchId, DateTime date, Iterable<int> opponents) {
    // Create new window for this match
    var newOpponents = opponents.where((id) => id != shooterId && windows.map((w) => w.uniqueOpponents).none((o) => o.contains(id))).toSet();
    var window = MatchWindow(
      matchId: matchId,
      date: date,
      uniqueOpponents: newOpponents,
      totalOpponents: opponents.length - 1, // exclude self
    );
    
    // Add window; size is now managed through the windows getter.
    allWindows.add(window);
  }

  // Calculated properties
  int get matchCount => windows.length;
  Set<int> get uniqueOpponents => windows
    .expand((w) => w.uniqueOpponents)
    .toSet();
  int get uniqueOpponentCount => uniqueOpponents.length;
  double uniqueOpponentsScore(Map<int, Competitor> allCompetitors) {
    double score = 0;
    for(var connectionId in uniqueOpponents) {
      var connectionConnectivity = allCompetitors[connectionId]!.connectivityScore;
      if(connectionConnectivity < mediumConnectivityLinkScore) {
        // lerp from lowConnectivityLinkWeight to mediumConnectivityLinkWeight based on
        // lowConnectivityLinkScore to mediumConnectivityLinkScore
        var lerp = (connectionConnectivity - lowConnectivityLinkScore) / (mediumConnectivityLinkScore - lowConnectivityLinkScore);
        var linkWeight = lerp * (mediumConnectivityLinkWeight - lowConnectivityLinkWeight) + lowConnectivityLinkWeight;
        score += linkWeight;
      }
      else if(connectionConnectivity > mediumConnectivityLinkScore) {
        // lerp from mediumConnectivityLinkWeight to highConnectivityLinkWeight based on
        // mediumConnectivityLinkScore to highConnectivityLinkScore
        var lerp = (connectionConnectivity - mediumConnectivityLinkScore) / (highConnectivityLinkScore - mediumConnectivityLinkScore);
        var linkWeight = lerp * (highConnectivityLinkWeight - mediumConnectivityLinkWeight) + mediumConnectivityLinkWeight;
        score += linkWeight;
      }
      else {
        score += mediumConnectivityLinkWeight;
      }
    }
    return score;
  }
  int get totalOpponentCount => windows
    .map((w) => w.totalOpponents)
    .sum;
  double get averageMatchSize => 
    windows.isEmpty ? 0 : totalOpponentCount / matchCount;
}


class Match {
  Match(this.matchId, this.start);

  final int matchId;
  final DateTime start;

  double averageConnectivityScore = 0;
  double medianConnectivityScore = 0;
  double competitorGlobalAverageConnectivityScore = 0;
  double competitorGlobalMedianConnectivityScore = 0;
  double matchGlobalAverageConnectivityScore = 0;
  double matchGlobalMedianConnectivityScore = 0;

  List<int> competitorIds = [];
}

class ConnectivityTracker {
  void processMatch(Match match, List<Match> matchWindow, Map<int, Competitor> matchCompetitors, Map<int, Competitor> allCompetitors) {
    var shooters = match.competitorIds;
    
    // Update each competitor's windows
    for (var shooterId in shooters) {
      matchCompetitors[shooterId]!.addMatch(
        match.matchId,
        match.start,
        shooters,
      );
    }

    match.averageConnectivityScore = matchCompetitors.values.map((c) => c.connectivityScore).average;
    match.medianConnectivityScore = (matchCompetitors.values.map((c) => c.connectivityScore).toList()..sort()).elementAt(matchCompetitors.values.length ~/ 2);

    List<double> scores = [];
    double maxRawConnectivity = 0.0;
    for(var competitor in allCompetitors.values) {
      if(competitor.windows.isNotEmpty && competitor.windows.last.date.isAfter(match.start.subtract(Duration(days: 730)))) {
        scores.add(competitor.connectivityScore);
        if(competitor.rawConnectivityScore > maxRawConnectivity) {
          maxRawConnectivity = competitor.rawConnectivityScore;
        }
      }
    }

    match.competitorGlobalAverageConnectivityScore = scores.average;
    match.competitorGlobalMedianConnectivityScore = (scores..sort()).elementAt(scores.length ~/ 2);

    var matchWindowAverages = matchWindow.map((m) => m.averageConnectivityScore).toList();
    var matchWindowMedians = matchWindow.map((m) => m.medianConnectivityScore).toList();
    // default to 1 instead of 0 for 'identity' instead of 'crash'
    match.matchGlobalAverageConnectivityScore = matchWindow.isNotEmpty ? matchWindowAverages.average : 1;
    match.matchGlobalMedianConnectivityScore = matchWindow.isNotEmpty ? (matchWindowMedians..sort()).elementAt(matchWindowMedians.length ~/ 2) : 1;

    // Recalculate scores for all participants
    _updateScores(matchCompetitors.values.where((c) => c.matchCount > 0), allCompetitors, maxRawConnectivity);
  }
  
  void _updateScores(Iterable<Competitor> activeCompetitors, Map<int, Competitor> allCompetitors, double maxExistingConnectivity) {
    if (activeCompetitors.isEmpty) return;
    
    double maxScore = maxExistingConnectivity;
    // Calculate raw scores using the (unique * total) / (unique + total) formula
    for (var competitor in activeCompetitors) {
      var uniqueScore = competitor.uniqueOpponentsScore(allCompetitors);
      var totalScore = competitor.totalOpponentCount;
      
      if (uniqueScore == 0 || totalScore == 0) {
        competitor.rawConnectivityScore = 0.0;
        competitor.connectivityScore = 0.0;
        continue;
      }

      competitor.rawConnectivityScore = (uniqueScore * totalScore) / (uniqueScore + totalScore);
      if(competitor.rawConnectivityScore > maxScore) {
        maxScore = competitor.rawConnectivityScore;
      }

      competitor.connectivityScore = sqrt(competitor.rawConnectivityScore + 1) * 24.5;
    }
    
    // if (maxScore > 0) {
    //   for (var competitor in activeCompetitors) {
    //     competitor.connectivityScore = (competitor.rawConnectivityScore / maxScore) * 100;
    //   }
    // }
  }
  
  // Helper method for analysis
  List<Competitor> getTopCompetitors(Map<int, Competitor> competitors, int count) {
    return competitors.values
      .where((c) => c.matchCount > 0)
      .sorted((a, b) => b.connectivityScore.compareTo(a.connectivityScore))
      .take(count)
      .toList();
  }
}

class Connection {
  final int opponentId;
  DateTime lastSeen;
  int matchCount;
  
  Connection({
    required this.opponentId,
    required this.lastSeen,
    required this.matchCount,
  });
}

void analyzeConnectivity(
  ConnectivityTracker tracker,
  Map<int, Competitor> competitors,
  Map<int, Match> matches,
) {
  var activeCompetitors = competitors.values
    .where((c) => c.matchCount > 0)
    .sorted((a, b) => b.connectivityScore.compareTo(a.connectivityScore))
    .toList();
    
  var allScores = activeCompetitors.map((c) => c.connectivityScore).toList();
  var allRawScores = activeCompetitors.map((c) => c.rawConnectivityScore).toList();

  // Match Size Distribution Analysis
  // print("\nMatch Size Distribution:");
  // var matchSizes = matches.values
  //   .map((m) => m.competitorIds.length.toDouble())
  //   .toList();
  
  // print("Mean Size: ${matchSizes.average.toStringAsFixed(1)}");
  // print("Median Size: ${_calculateMedian(matchSizes).toStringAsFixed(1)}");
  // print("Std Dev: ${_calculateStdDev(matchSizes).toStringAsFixed(1)}");
  
  // var sizeQuartiles = _calculateQuartiles(matchSizes);
  // print("\nMatch Size Quartiles:");
  // print("Q1 (25th): ${sizeQuartiles.q1.toStringAsFixed(1)}");
  // print("Q2 (50th): ${sizeQuartiles.q2.toStringAsFixed(1)}");
  // print("Q3 (75th): ${sizeQuartiles.q3.toStringAsFixed(1)}");
  // print("IQR: ${(sizeQuartiles.q3 - sizeQuartiles.q1).toStringAsFixed(1)}");
  
  // print("\nMatch Size Percentiles:");
  // print("10th: ${_calculatePercentile(matchSizes, 0.1).toStringAsFixed(1)}");
  // print("90th: ${_calculatePercentile(matchSizes, 0.9).toStringAsFixed(1)}");
  // print("95th: ${_calculatePercentile(matchSizes, 0.95).toStringAsFixed(1)}");
  // print("99th: ${_calculatePercentile(matchSizes, 0.99).toStringAsFixed(1)}");
  
  // print("\nMatch Size Range:");
  // print("Smallest: ${matchSizes.min.toStringAsFixed(1)}");
  // print("Largest: ${matchSizes.max.toStringAsFixed(1)}");
  
  // print("\nMatch Size Distribution:");
  // print(_createHistogram(matchSizes, buckets: 20, width: 60));

  // print("\nDetailed Analysis of Outliers:");
  // print("\nTop 5 Most Connected:");
  // for (var competitor in activeCompetitors.take(5)) {
  //   _printCompetitorDetail(competitor, matches);
  // }
  
  // print("\nBottom 5 Connected (excluding inactive):");
  // for (var competitor in activeCompetitors.reversed.take(5)) {
  //   _printCompetitorDetail(competitor, matches);
  // }
  
  // Basic statistics
  print("\nConnectivity Analysis:");
  print("Active Competitors: ${activeCompetitors.length}");
  print("\nScore Distribution:");
  print("Mean: ${allScores.average.toStringAsFixed(1)}");
  print("Median: ${_calculateMedian(allScores).toStringAsFixed(1)}");
  print("Std Dev: ${_calculateStdDev(allScores).toStringAsFixed(1)}");

  print("\nRaw Score Distribution:");
  print("Mean: ${allRawScores.average.toStringAsFixed(1)}");
  print("Median: ${_calculateMedian(allRawScores).toStringAsFixed(1)}");
  print("Std Dev: ${_calculateStdDev(allRawScores).toStringAsFixed(1)}");
  
  // Quartiles and IQR
  var quartiles = _calculateQuartiles(allScores);
  print("\nQuartiles:");
  print("Q1 (25th): ${quartiles.q1.toStringAsFixed(1)}");
  print("Q2 (50th): ${quartiles.q2.toStringAsFixed(1)}");
  print("Q3 (75th): ${quartiles.q3.toStringAsFixed(1)}");
  print("IQR: ${(quartiles.q3 - quartiles.q1).toStringAsFixed(1)}");
  
  // Percentiles
  print("\nPercentiles:");
  print("10th: ${_calculatePercentile(allScores, 0.1).toStringAsFixed(1)}");
  print("90th: ${_calculatePercentile(allScores, 0.9).toStringAsFixed(1)}");
  print("95th: ${_calculatePercentile(allScores, 0.95).toStringAsFixed(1)}");
  print("99th: ${_calculatePercentile(allScores, 0.99).toStringAsFixed(1)}");
  
  // Range
  print("\nRange:");
  print("Min: ${allScores.min.toStringAsFixed(1)}");
  print("Max: ${allScores.max.toStringAsFixed(1)}");
  print("Range: ${(allScores.max - allScores.min).toStringAsFixed(1)}");
  
  // Histogram
  print("\nConnectivity Score Distribution:");
  print(_createHistogram(allScores, buckets: 20, width: 60));

  print("\nCompetitor Activity Distribution (matches per competitor):");
  print(_createHistogram(
    competitors.values.map((c) => c.matchIds.length.toDouble()).toList(),
    buckets: 20,
    width: 60
  ));

  print("\nMatch vs Global Connectivity Analysis:");
  var matchDiffs = matches.values.map((m) => {
    "avgConnectivity": m.averageConnectivityScore,
    "medianConnectivity": m.medianConnectivityScore,
    "avgDiff": m.averageConnectivityScore - m.competitorGlobalAverageConnectivityScore,
    "medianDiff": m.medianConnectivityScore - m.competitorGlobalMedianConnectivityScore,
    "avgDiffMatch": m.averageConnectivityScore - m.matchGlobalAverageConnectivityScore,
    "medianDiffMatch": m.medianConnectivityScore - m.matchGlobalMedianConnectivityScore,
    "date": m.start,
    "size": m.competitorIds.length,
  }).toList();


  print("\nMatch Average Connectivity Distribution:");
  print(_createHistogram(
    matchDiffs.map((d) => d["avgConnectivity"] as double).toList(),
    buckets: 20,
    width: 60,
    entityName: "matches"
  ));

  print("\nMatch Median Connectivity Distribution:");
  print(_createHistogram(
    matchDiffs.map((d) => d["medianConnectivity"] as double).toList(),
    buckets: 20,
    width: 60,
    entityName: "matches"
  ));
  
  print("\nConnectivity Differences (Match - CompetitorGlobal):");
  print("Average Difference: ${matchDiffs.map((d) => d["avgDiff"]).cast<double>().average.toStringAsFixed(1)}");
  print("Median Difference: ${matchDiffs.map((d) => d["medianDiff"]).cast<double>().average.toStringAsFixed(1)}");
  
  var avgDiffs = matchDiffs.map((d) => d["avgDiff"] as double).toList();
  var medianDiffs = matchDiffs.map((d) => d["medianDiff"] as double).toList();
  
  print("\nAverage Difference Distribution:");
  print("Std Dev: ${_calculateStdDev(avgDiffs).toStringAsFixed(1)}");
  var diffQuartiles = _calculateQuartiles(avgDiffs);
  print("Q1: ${diffQuartiles.q1.toStringAsFixed(1)}");
  print("Q3: ${diffQuartiles.q3.toStringAsFixed(1)}");
  
  print("\nMatch Average Connectivity Score Distribution:");
  print(_createHistogram(avgDiffs, buckets: 40, width: 60, entityName: "matches"));

  print("\nMedian Difference Distribution:");
  print("Std Dev: ${_calculateStdDev(medianDiffs).toStringAsFixed(1)}");
  var medianQuartiles = _calculateQuartiles(medianDiffs);
  print("Q1: ${medianQuartiles.q1.toStringAsFixed(1)}");
  print("Q3: ${medianQuartiles.q3.toStringAsFixed(1)}");

  print("\nMatch Median Connectivity Score Distribution:");
  print(_createHistogram(medianDiffs, buckets: 40, width: 60, entityName: "matches"));
  
  // Correlation with match size
  var correlation = _calculateCorrelation(
    matchDiffs.map((d) => d["size"] as int).toList(),
    avgDiffs
  );
  print("\nCorrelation with Match Size: ");
  print("    Averages: ${correlation.toStringAsFixed(3)}");
  print("    Medians: ${_calculateCorrelation(
    matchDiffs.map((d) => d["size"] as int).toList(),
    medianDiffs
  ).toStringAsFixed(3)}");

  print("\nConnectivity Differences (Match vs MatchGlobal):");

  print("\nMatchGlobal Median Connectivity Score Distribution:");
  print(_createHistogram(
    matchDiffs.map((d) => d["medianDiffMatch"] as double).toList(),
    buckets: 20,
    width: 60,
    entityName: "matches"
  ));
  print("Median Difference: ${matchDiffs.map((d) => d["medianDiffMatch"]).cast<double>().average.toStringAsFixed(1)}");
  print("Median Difference Std Dev: ${_calculateStdDev(matchDiffs.map((d) => d["medianDiffMatch"] as double).toList()).toStringAsFixed(1)}");

  print("\nMatchGlobal Average Connectivity Score Distribution:");
  print(_createHistogram(
    matchDiffs.sublist(200).map((d) => d["avgDiffMatch"] as double).toList(),
    buckets: 20,
    width: 60,
    entityName: "matches"
  ));
  print("Average Difference: ${matchDiffs.sublist(200).map((d) => d["avgDiffMatch"]).cast<double>().average.toStringAsFixed(1)}");
  print("Average Difference Std Dev: ${_calculateStdDev(matchDiffs.sublist(200).map((d) => d["avgDiffMatch"] as double).toList()).toStringAsFixed(1)}");

  print("\nConnectivity Difference Time Series:");
  var matchCompetitorGlobalMedians = matches.values.map((m) => m.medianConnectivityScore).toList();
  var matchCompetitorGlobalAverages = matches.values.map((m) => m.averageConnectivityScore).toList();
  var matchMatchGlobalAverages = matches.values.map((m) => m.matchGlobalAverageConnectivityScore).toList();
  var matchMatchGlobalMedians = matches.values.map((m) => m.matchGlobalMedianConnectivityScore).toList();
  
  var medianMean = matchCompetitorGlobalMedians.average;
  var medianStdDev = _calculateStdDev(matchCompetitorGlobalMedians);
  var avgMean = matchCompetitorGlobalAverages.average;
  var avgStdDev = _calculateStdDev(matchCompetitorGlobalAverages);

  var matchAvgMean = matchMatchGlobalAverages.average;
  var matchAvgStdDev = _calculateStdDev(matchMatchGlobalAverages);
  var sortedMatches = matches.values
    .sorted((a, b) => a.start.compareTo(b.start))
    .toList();

  // Group by month for readability
  var monthlyDiffs = <DateTime, List<Map<String, dynamic>>>{};
  for (var match in sortedMatches) {
    var monthKey = DateTime(match.start.year, match.start.month);
    List<double> globalAveragesToDate = [];
    List<double> matchAveragesToDate = [];
    for(var match in sortedMatches.where((value) => value.start.isBefore(match.start))) {
      globalAveragesToDate.add(match.competitorGlobalAverageConnectivityScore);
      matchAveragesToDate.add(match.matchGlobalAverageConnectivityScore);
    }
    var avgToDate = globalAveragesToDate.isNotEmpty ? globalAveragesToDate.average : avgMean;
    var stdDevToDate = avgStdDev;
    var matchAvgToDate = matchAveragesToDate.isNotEmpty ? matchAveragesToDate.average : matchAvgMean;
    var matchStdDevToDate = matchAvgStdDev;

    if(stdDevToDate == 0.0) {
      stdDevToDate = avgStdDev;
      avgToDate = avgMean;
    }
    if(matchStdDevToDate == 0.0) {
      matchStdDevToDate = matchAvgStdDev;
      matchAvgToDate = matchAvgMean;
    }
    monthlyDiffs.putIfAbsent(monthKey, () => []).add({
      "avgDiff": match.averageConnectivityScore - match.competitorGlobalAverageConnectivityScore,
      "medianDiff": match.medianConnectivityScore - match.competitorGlobalMedianConnectivityScore,
      "avgDiffMatch": match.averageConnectivityScore - match.matchGlobalAverageConnectivityScore,
      "medianDiffMatch": match.medianConnectivityScore - match.matchGlobalMedianConnectivityScore,
      "matchAvgZScore": (match.averageConnectivityScore - matchAvgToDate) / matchStdDevToDate,
      "avgZScore": (match.averageConnectivityScore - avgToDate) / stdDevToDate,
      "refAvg": avgToDate,
      "refStdDev": stdDevToDate,
      "size": match.competitorIds.length,
    });
  }
  
  // Print monthly averages with simple ASCII chart
  print("\nMonthly Trends (■ = z-score):");
  var maxZ = monthlyDiffs.values
    .expand((m) => [m.map((d) => d["avgZScore"] as double).average])
    .map((d) => d.abs())
    .max;
  var scale = 30 / maxZ;  // Scale to fit in 60 chars (-30 to +30)
  
  for (var entry in monthlyDiffs.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    var month = entry.key;
    var diffs = entry.value;
    var avgZ = diffs.map((d) => d["avgZScore"] as double).average;
    var avgSize = diffs.map((d) => d["size"] as int).average;
    var refAvg = diffs.map((d) => d["refAvg"] as double).average;
    var refStdDev = diffs.map((d) => d["refStdDev"] as double).average;
    var matchAvgZScore = diffs.map((d) => d["matchAvgZScore"] as double).average;
    var centerPos = 30;
    var rawZPos = centerPos + (avgZ * scale).round();
    var zPos = rawZPos.clamp(0, 59);
    var matchZPos = (centerPos + (matchAvgZScore * scale).round()).clamp(0, 59);

    
    var line = List.filled(60, ' ');
    line[centerPos] = '|';
    line[zPos] = '■';
    line[matchZPos] = '□';

    
    // Add indicators for clamped values
    var clampIndicator = '';
    if (rawZPos != zPos) {
      clampIndicator = ' [!]';
    }
    
    print("${month.toString().substring(0, 7)}: "
          "${line.join('')}$clampIndicator "
          "z_cmp: ${avgZ.toStringAsFixed(2).padLeft(5)}, "
          "z_mch: ${matchAvgZScore.toStringAsFixed(2).padLeft(5)}, "
          "matches: ${diffs.length}, "
          "avg size: ${avgSize.toStringAsFixed(0).padLeft(3)}");
  }
  
  // Add legend
  print("\nScale: Each position = ${(1/scale).toStringAsFixed(1)} points");
  print("Center line = 0 difference");
  print("■ = z-score");
  print("[!] = values exceeded chart bounds");

  print("\nRaw Connectivity Z-Score Analysis:");
  
  print("Match Medians:");
  print("  Mean: ${medianMean.toStringAsFixed(1)}");
  print("  Std Dev: ${medianStdDev.toStringAsFixed(1)}");
  
  print("\nMatch Averages:");
  print("  Mean: ${avgMean.toStringAsFixed(1)}");
  print("  Std Dev: ${avgStdDev.toStringAsFixed(1)}");
  
  print("\nMedian Z-Score Distribution:");
  print(_createHistogram(
    matchCompetitorGlobalMedians.map((m) => (m - medianMean) / medianStdDev).toList(),
    buckets: 20,
    width: 60,
    valueMapper: (z) => medianMean + (z * medianStdDev),
    entityName: "matches"
  ));
  
  print("\nAverage Z-Score Distribution:");
  print(_createHistogram(
    matchCompetitorGlobalAverages.map((m) => (m - avgMean) / avgStdDev).toList(),
    buckets: 20,
    width: 60,
    valueMapper: (z) => avgMean + (z * avgStdDev),
    entityName: "matches"
  ));

  print("\nMatchGlobal Average Z-Score Distribution:");
  print(_createHistogram(
    matchMatchGlobalAverages.map((m) => (m - matchAvgMean) / matchAvgStdDev).toList(),
    buckets: 40,
    width: 60,
    valueMapper: (z) => matchAvgMean + (z * matchAvgStdDev),
    entityName: "matches"
  ));

  var avgSizeCorrelation = _calculateCorrelation(
    matches.values.map((m) => m.competitorIds.length.toDouble()).toList(),
    matches.values.map((m) => (m.averageConnectivityScore - avgMean) / avgStdDev).toList()
  );
  
  var medianSizeCorrelation = _calculateCorrelation(
    matches.values.map((m) => m.competitorIds.length.toDouble()).toList(),
    matches.values.map((m) => (m.medianConnectivityScore - medianMean) / medianStdDev).toList()
  );
  
  print("\nCorrelation with Match Size:");
  print("  Average Z-Score: ${avgSizeCorrelation.toStringAsFixed(3)}");
  print("  Median Z-Score: ${medianSizeCorrelation.toStringAsFixed(3)}");

  var matchesByZScore = matches.values.map((m) => (
    match: m,
    zScore: (m.averageConnectivityScore - avgMean) / avgStdDev
  )).toList()
    ..sort((a, b) => a.zScore.compareTo(b.zScore));
  
  // Analyze matches in different z-score ranges
  var ranges = [
    (-double.infinity, -1.0),
    (-1.0, 0.0),
    (0.0, 1.0),
    (1.0, double.infinity)
  ];
  
  for (var (min, max) in ranges) {
    var rangeMatches = matchesByZScore
      .where((m) => m.zScore >= min && m.zScore < max)
      .map((m) => m.match)
      .toList();
      
    print("\nMatches with ${min.isFinite ? min.toStringAsFixed(1) : '-∞'} ≤ z < ${max.isFinite ? max.toStringAsFixed(1) : '∞'} (${rangeMatches.length} matches):");
    print("  Average size: ${rangeMatches.map((m) => m.competitorIds.length).average.toStringAsFixed(1)}");
    // Add more characteristics here
  }

  // After z-score calculations...
  var matchAnalysis = matches.values.map((m) {
    var highActivity = m.competitorIds.where((id) => id < 3000).length;
    var total = m.competitorIds.length;
    var highProportion = highActivity / total;
    
    return {
      "match": m,
      "zScore": (m.averageConnectivityScore - avgMean) / avgStdDev,
      "highProportion": highProportion,
      "highCount": highActivity,
      "totalSize": total,
    };
  }).toList();
  
  // Group into ranges for analysis
  var proportionRanges = [
    (0.0, 0.2),
    (0.2, 0.3),
    (0.3, 0.4),
    (0.4, 0.5),
    (0.5, 0.6),
    (0.6, 1.0)
  ];
  
  for (var (min, max) in proportionRanges) {
    var rangeMatches = matchAnalysis
        .where((m) => (m["highProportion"] as double) >= min && (m["highProportion"] as double) < max)
        .toList();
        
    if (rangeMatches.isEmpty) continue;
    
    var avgZ = rangeMatches.map((m) => m["zScore"] as double).average;
    var matchCount = rangeMatches.length;
    
    print("\nMatches with ${(min * 100).toStringAsFixed(0)}%-${(max * 100).toStringAsFixed(0)}% high activity:");
    print("  Count: $matchCount matches");
    print("  Average z-score: ${avgZ.toStringAsFixed(2)}");
    print("  Average size: ${rangeMatches.map((m) => m["totalSize"] as int).average.toStringAsFixed(1)}");
  }

  // After match analysis...
  print("\nHigh Activity Proportion vs Z-Score Distribution:");
  
  // Create buckets of 5% width
  var buckets = List.generate(20, (i) => i * 0.05);
  var bucketData = <double, List<Map<String, dynamic>>>{};
  
  for (var bucket in buckets) {
    bucketData[bucket] = matchAnalysis
        .where((m) => 
            (m["highProportion"] as double) >= bucket && 
            (m["highProportion"] as double) < bucket + 0.05)
        .toList();
  }
  
  var centerPos = 30;
  // Print distribution with z-scores
  for (var bucket in buckets) {
    var matches = bucketData[bucket]!;
    if (matches.isEmpty) continue;
    
    var avgZ = matches.map((m) => m["zScore"] as double).average;
    var avgSize = matches.map((m) => m["totalSize"] as int).average;
    var proportion = (bucket * 100).toStringAsFixed(0).padLeft(2);
    
    var zPos = (centerPos + (avgZ * 10).round()).clamp(0, 59);
    var line = List.filled(60, ' ');
    line[centerPos] = '|';
    line[zPos] = '■';
    
    // Add indicators for clamped values
    var clampIndicator = '';
    if (zPos == 0 || zPos == 59) {
      clampIndicator = ' [!]';
    }
    
    print("${proportion}%-${(bucket * 100 + 5).toStringAsFixed(0)}%: "
          "${line.join('')}$clampIndicator "
          "z=${avgZ.toStringAsFixed(2).padLeft(5)} "
          "n=${matches.length.toString().padLeft(3)} "
          "size=${avgSize.toStringAsFixed(1).padLeft(5)}");
  }

    // Add scale markers
  var scaleValues = List.generate(13, (i) => -3.0 + (i * 0.5));
  var scalePositions = scaleValues.map((z) => (centerPos + (z * 10).round()).clamp(0, 60));
  var scaleLine = List.filled(61, ' ');
  for(int i = 0; i < 61; i++) {
    if(scalePositions.contains(i)) {
      scaleLine[i] = '|';
    }
  }
  print(  "         ${scaleLine.join('')}");
  print("Z-Score: ${scaleValues.map((z) => z.toStringAsFixed(1).padLeft(4)).join(' ')}");
  
  print("\nScale: Each position = 0.1 standard deviations");
  print("Center line = z-score of 0");
  print("■ = z-score");
  print("[!] = values exceeded chart bounds");

  // After existing z-score visualization and scale...

  print("\nDetailed Connectivity Analysis by High Activity Proportion:");
  for (var bucket in buckets) {
    var matches = bucketData[bucket]!;
    if (matches.isEmpty) continue;
    
    var matchStats = matches.map((m) {
      var match = m["match"] as Match;
      var matchCompetitors = match.competitorIds.map((id) => competitors[id]!);
      
      // Calculate connectivity scores as of this match
      var competitorStats = matchCompetitors.map((c) {
        var matchWindows = c.allWindows
            .where((w) => w.matchId < match.matchId)
            .toList()
            .getTailWindow(Competitor.windowSize);  // Only use last 5 matches before this one
            
        if (matchWindows.isEmpty) return {
          "unique": 0,
          "total": 0,
          "rawScore": 0.0,
          "windowSize": 0,
        };
        
        var unique = matchWindows
            .expand((w) => w.uniqueOpponents)
            .toSet()
            .length;
        var total = matchWindows
            .map((w) => w.totalOpponents)
            .sum;
            
        return {
          "unique": unique,
          "total": total,
          "rawScore": unique * total / (unique + total),
          "windowSize": matchWindows.length,
        };
      }).toList();
      
      var avgUnique = competitorStats.map((s) => s["unique"] as int).average;
      var avgTotal = competitorStats.map((s) => s["total"] as int).average;
      var avgRawScore = competitorStats.map((s) => s["rawScore"] as double).average;
      var avgWindowSize = competitorStats.map((s) => s["windowSize"] as int).average;
      
      return {
        "unique": avgUnique,
        "total": avgTotal,
        "rawScore": avgRawScore,
        "size": match.competitorIds.length,
        "windowSize": avgWindowSize,
      };
    }).toList();
    
    var avgZ = matches.map((m) => m["zScore"] as double).average;
    var avgSize = matchStats.map((s) => s["size"] as int).average;
    var avgUnique = matchStats.map((s) => s["unique"] as double).average;
    var avgTotal = matchStats.map((s) => s["total"] as double).average;
    var avgRawScore = matchStats.map((s) => s["rawScore"] as double).average;
    var avgWindowSize = matchStats.map((s) => s["windowSize"] as double).average;
    
    var proportion = (bucket * 100).toStringAsFixed(0).padLeft(2);
    
    print("${proportion}%-${(bucket * 100 + 5).toStringAsFixed(0)}%: "
          "z=${avgZ.toStringAsFixed(2).padLeft(6)} "
          "size=${avgSize.toStringAsFixed(1).padLeft(5)} "
          "unique=${avgUnique.toStringAsFixed(1).padLeft(5)} "
          "total=${avgTotal.toStringAsFixed(1).padLeft(5)} "
          "raw=${avgRawScore.toStringAsFixed(1).padLeft(5)} "
          "window=${avgWindowSize.toStringAsFixed(1).padLeft(4)}");
  }

  print("\nConnectivity Distribution by Competitor Type:");
  
  var lowActivityScores = competitors.values
      .where((c) => c.shooterId >= highActivityCount)  // ID >= 2500 means low activity
      .where((c) => c.windows.isNotEmpty &&c.windows.last.date.isAfter(matches.values.last.start.subtract(Duration(days: 730))))
      .map((c) => c.connectivityScore)
      .toList();
      
  var highActivityScores = competitors.values
      .where((c) => c.shooterId < highActivityCount)   // ID < 2500 means high activity
      .where((c) => c.windows.isNotEmpty&& c.windows.last.date.isAfter(matches.values.last.start.subtract(Duration(days: 730))))
      .map((c) => c.connectivityScore)
      .toList();
  
  print("\nLow Activity Competitor Connectivity Distribution:");
  print(_createHistogram(lowActivityScores, buckets: 20, width: 60, entityName: "low-activity"));
  
  print("\nHigh Activity Competitor Connectivity Distribution:");
  print(_createHistogram(highActivityScores, buckets: 20, width: 60, entityName: "high-activity"));

  print("\nLow Activity Competitor Match Count Distribution:");
  print(_createHistogram(
    competitors.values
      .where((c) => c.shooterId >= highActivityCount)
      .map((c) => c.matchIds.length.toDouble())
      .toList(),
    buckets: 20,
    width: 60,
    integral: true,
    entityName: "low-activity"
  ));
  
  print("\nHigh Activity Competitor Match Count Distribution:");
  print(_createHistogram(
    competitors.values
      .where((c) => c.shooterId < highActivityCount)
      .map((c) => c.matchIds.length.toDouble())
      .toList(),
    buckets: 20,
    width: 60,
    integral: true,
    entityName: "high-activity"
  ));
}

void _printCompetitorDetail(Competitor competitor, Map<int, Match> matches) {
  print("\nCompetitor ${competitor.shooterId}:");
  print("Connectivity Score: ${competitor.connectivityScore.toStringAsFixed(1)}");
  print("Total Unique Opponents: ${competitor.uniqueOpponentCount}");
  print("Total Opponents: ${competitor.totalOpponentCount}");
  print("Average Match Size: ${competitor.averageMatchSize.toStringAsFixed(1)}");
  print("\nMatch Windows:");
  
  for (var window in competitor.windows) {
    var match = matches[window.matchId]!;
    print("  Match ${window.matchId} (${window.date.toString().substring(0, 10)}):");
    print("    Unique Opponents: ${window.uniqueOpponents.length}");
    print("    Total Opponents: ${window.totalOpponents}");
    print("    Match Size: ${match.competitorIds.length}");
  }
  print("----------------------------------------");
}

double _calculateMedian(List<double> values) {
  var sorted = List<double>.from(values)..sort();
  var middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _calculateStdDev(List<double> values) {
  var mean = values.average;
  var squaredDiffs = values.map((v) => pow(v - mean, 2));
  return sqrt(squaredDiffs.average);
}

({double q1, double q2, double q3}) _calculateQuartiles(List<double> values) {
  var sorted = List<double>.from(values)..sort();
  var q2 = _calculateMedian(sorted);
  
  var lowerHalf = sorted.sublist(0, sorted.length ~/ 2);
  var upperHalf = sorted.sublist((sorted.length + 1) ~/ 2);
  
  return (
    q1: _calculateMedian(lowerHalf),
    q2: q2,
    q3: _calculateMedian(upperHalf)
  );
}

double _calculatePercentile(List<double> values, double percentile) {
  assert(percentile >= 0 && percentile <= 1);
  var sorted = List<double>.from(values)..sort();
  var index = (sorted.length - 1) * percentile;
  var lower = sorted[index.floor()];
  var upper = sorted[index.ceil()];
  return lower + (upper - lower) * (index - index.floor());
}

String _createHistogram(List<double> values, {
  int buckets = 20,
  int width = 60,
  double Function(double)? valueMapper,
  String entityName = "competitors",
  bool integral = false,
}) {
  if (values.isEmpty) return "No data";
  
  // Create buckets
  var min = values.min;
  var max = values.max;
  var range = max - min;
  var bucketSize = range / buckets;
  if(integral) {
    bucketSize = bucketSize.roundToDouble();
    buckets = (range / bucketSize).round();
  }
  
  // Count values in each bucket
  var counts = List.filled(buckets, 0);
  for (var value in values) {
    var bucketIndex = ((value - min) / bucketSize).floor();
    // Handle edge case for maximum value
    if (bucketIndex == buckets) bucketIndex--;
    counts[bucketIndex]++;
  }
  
  // Find maximum count for scaling
  var maxCount = counts.max;
  var scale = width / maxCount;
  
  // Build histogram
  var buffer = StringBuffer();
  for (var i = 0; i < buckets; i++) {
    var bucketMin = min + (i * bucketSize);
    var barLength = (counts[i] * scale).round();
    buffer.writeln(
      "${bucketMin.toStringAsFixed(1).padLeft(6)}: "
      "${"█" * barLength}${counts[i].toString().padLeft(4)} "
      "(${(counts[i] / values.length * 100).toStringAsFixed(1)}%)"
      "${valueMapper != null ? " [${valueMapper(bucketMin).toStringAsFixed(1)}]" : ""}"
    );
  }
  
  // Add legend
  buffer.writeln("\nTotal: ${values.length} $entityName");
  buffer.writeln("Bucket size: ${bucketSize.toStringAsFixed(1)} points");
  
  return buffer.toString();
}

double _calculateCorrelation(List<num> x, List<num> y) {
  assert(x.length == y.length);
  var n = x.length;
  var xMean = x.average;
  var yMean = y.average;
  
  var numerator = 0.0;
  var xDenom = 0.0;
  var yDenom = 0.0;
  
  for (var i = 0; i < n; i++) {
    var xDiff = x[i] - xMean;
    var yDiff = y[i] - yMean;
    numerator += xDiff * yDiff;
    xDenom += xDiff * xDiff;
    yDenom += yDiff * yDiff;
  }
  
  return numerator / sqrt(xDenom * yDenom);
}

extension ListOverlap<T> on Iterable<T> {
  Iterable<T> intersection(Iterable<T> other) {
    return this.where((e) => other.contains(e));
  }

  bool intersects(Iterable<T> other) {
    return this.any((e) => other.contains(e));
  }

  bool containsAll(Iterable<T> other) {
    return other.every((e) => this.contains(e));
  }
}

extension WindowedList<T> on List<T> {
    /// Get a windowed view into the list, starting at the tail of the list,
  /// optionally offset by [offset].
  List<T> getTailWindow(int window, {int offset = 0}) {
    if(offset + window > length) return this;
    return sublist(length - window - offset, length - offset);
  }
}