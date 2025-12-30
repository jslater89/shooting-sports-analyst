import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:data/stats.dart' show StudentDistribution;
import 'package:normal/normal.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class LadyRatingAnalysisCommand extends DbOneoffCommand {
  LadyRatingAnalysisCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "LRA";
  @override
  final String title = "Lady Rating Analysis";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var output = StringBuffer();

    var project1 = await db.getRatingProjectByName("L2s Main");
    var project2 = await db.getRatingProjectByName("L2s Main Glicko");

    if(project1 == null) {
      output.writeln("L2s Main project not found");
      console.print(output.toString());
      return;
    }

    if(project2 == null) {
      output.writeln("L2s Main Glicko project not found");
      console.print(output.toString());
      return;
    }

    List<_ShooterData> allData = [];

    List<String> targetGroupNames = [
      "PCC",
      "OPEN",
      "CARRY OPTICS",
      "LIMITED OPTICS",
      "PRODUCTION",
      "LIMITED",
      "SINGLE STACK",
      "REVOLVER",
    ];

    // Process L2s Main
    output.writeln("\n=== Processing L2s Main ===");
    for(var group in project1.dbGroups) {
      if(!targetGroupNames.contains(group.name.toUpperCase())) {
        continue;
      }

      output.writeln("Processing group: ${group.name}");
      var ratings = await project1.getRatings(group);
      if(ratings.isErr()) {
        output.writeln("Error getting ratings for group ${group.name}: ${ratings.unwrapErr()}");
        continue;
      }

      var ratingsList = ratings.unwrap();
      for(var rating in ratingsList) {
        var data = await _extractShooterData(rating, project1, "L2s Main", group.name);
        if(data != null) {
          allData.add(data);
        }
      }
    }

    // Process L2s Main Glicko
    output.writeln("\n=== Processing L2s Main Glicko ===");
    for(var group in project2.dbGroups) {
      if(!targetGroupNames.contains(group.name.toUpperCase())) {
        continue;
      }

      output.writeln("Processing group: ${group.name}");
      var ratings = await project2.getRatings(group);
      if(ratings.isErr()) {
        output.writeln("Error getting ratings for group ${group.name}: ${ratings.unwrapErr()}");
        continue;
      }

      var ratingsList = ratings.unwrap();
      for(var rating in ratingsList) {
        var data = await _extractShooterData(rating, project2, "L2s Main Glicko", group.name);
        if(data != null) {
          allData.add(data);
        }
      }
    }

    // Export CSV
    _exportCsv(allData, output);

    // Analyze by project and group
    Map<String, List<_ShooterData>> byProjectGroup = {};
    for(var data in allData) {
      var key = "${data.projectName}|${data.groupName}";
      byProjectGroup.putIfAbsent(key, () => []).add(data);
    }

    for(var entry in byProjectGroup.entries) {
      var parts = entry.key.split("|");
      var projectName = parts[0];
      var groupName = parts[1];
      var data = entry.value;

      output.writeln("\n\n=== Analysis: $projectName - $groupName ===");
      _analyzeData(data, output);
    }

    // Top-line summaries by project
    output.writeln("\n\n=== Top-Line Summary: L2s Main ===");
    var l2sMainData = allData.where((d) => d.projectName == "L2s Main").toList();
    _printTopLineSummary(l2sMainData, output);

    output.writeln("\n\n=== Top-Line Summary: L2s Main Glicko ===");
    var l2sMainGlickoData = allData.where((d) => d.projectName == "L2s Main Glicko").toList();
    _printTopLineSummary(l2sMainGlickoData, output);

    // Print to console and save to file
    var outputText = output.toString();
    console.print(outputText);

    var file = File("/tmp/lady_rating_analysis_output.txt");
    file.writeAsStringSync(outputText);
    console.print("\n\nOutput also saved to ${file.path}");
  }

  Future<_ShooterData?> _extractShooterData(DbShooterRating rating, DbRatingProject project, String projectName, String groupName) async {
    // Load events if not loaded
    if(!rating.events.isLoaded) {
      await rating.events.load();
    }

    // Skip if no events
    if(rating.events.isEmpty) {
      return null;
    }

    // Get distinct match IDs and stage count
    Set<String> matchIds = {};
    int stageCount = 0;

    // For Glicko2, use lengthInStages from wrapped rating and capture RD
    double? rd;
    bool isGlicko2 = projectName.contains("Glicko");
    if(isGlicko2) {
      var wrappedRating = project.wrapDbRatingSync(rating);
      if(wrappedRating is Glicko2Rating) {
        stageCount = wrappedRating.lengthInStages;
        rd = wrappedRating.committedRD; // Use committed RD in display units
      }
      else {
        // Fallback to counting events if wrapping fails
        stageCount = rating.events.length;
      }
    }
    else {
      // For non-Glicko2, count events for stages
      stageCount = rating.events.length;
    }

    // Count distinct matches (same for both algorithms)
    for(var event in rating.events) {
      matchIds.add(event.matchId);
    }

    return _ShooterData(
      projectName: projectName,
      groupName: groupName,
      memberNumber: rating.memberNumber,
      name: rating.getName(suffixes: false),
      isFemale: rating.female,
      rating: rating.rating,
      matchCount: matchIds.length,
      stageCount: stageCount,
      rd: rd,
    );
  }

  void _exportCsv(List<_ShooterData> data, StringBuffer output) {
    List<String> csvLines = [
      "Project,Group,Member Number,Name,Sex,Rating,Match Count,Stage Count"
    ];

    for(var d in data) {
      csvLines.add([
        d.projectName,
        d.groupName,
        d.memberNumber,
        "\"${d.name.replaceAll("\"", "\"\"")}\"",
        d.isFemale ? "F" : "M",
        d.rating.toStringAsFixed(2),
        d.matchCount.toString(),
        d.stageCount.toString(),
      ].join(","));
    }

    var csv = csvLines.join("\n");
    var file = File("/tmp/lady_rating_analysis_combined.csv");
    file.writeAsStringSync(csv);
    output.writeln("\nExported ${data.length} records to ${file.path}");
  }

  void _analyzeData(List<_ShooterData> data, StringBuffer output) {
    if(data.isEmpty) {
      output.writeln("No data to analyze");
      return;
    }

    // Separate by sex
    var men = data.where((d) => !d.isFemale).toList();
    var women = data.where((d) => d.isFemale).toList();

    // Participation
    output.writeln("\n--- Participation ---");
    output.writeln("Total: ${data.length}");
    output.writeln("Men: ${men.length} (${(men.length / data.length * 100).toStringAsFixed(1)}%)");
    output.writeln("Women: ${women.length} (${(women.length / data.length * 100).toStringAsFixed(1)}%)");

    // Statistics for ratings
    if(men.isNotEmpty && women.isNotEmpty) {
      output.writeln("\n--- Rating Statistics ---");
      _printStats("Men", men.map((d) => d.rating).toList(), output);
      _printStats("Women", women.map((d) => d.rating).toList(), output);
    }

    // Statistics for match counts
    if(men.isNotEmpty && women.isNotEmpty) {
      output.writeln("\n--- Match Count Statistics ---");
      _printStats("Men", men.map((d) => d.matchCount.toDouble()).toList(), output);
      _printStats("Women", women.map((d) => d.matchCount.toDouble()).toList(), output);
    }

    // Statistics for stage counts
    if(men.isNotEmpty && women.isNotEmpty) {
      output.writeln("\n--- Stage Count Statistics ---");
      _printStats("Men", men.map((d) => d.stageCount.toDouble()).toList(), output);
      _printStats("Women", women.map((d) => d.stageCount.toDouble()).toList(), output);
    }

    // Statistical Tests
    if(men.isNotEmpty && women.isNotEmpty) {
      output.writeln("\n--- Statistical Tests (Null: No difference) ---");
      var menRatings = men.map((d) => d.rating).toList();
      var womenRatings = women.map((d) => d.rating).toList();

      _printStatisticalTests(menRatings, womenRatings, "Rating", output);

      // Statistical tests for match counts
      var menMatchCounts = men.map((d) => d.matchCount.toDouble()).toList();
      var womenMatchCounts = women.map((d) => d.matchCount.toDouble()).toList();
      _printStatisticalTests(menMatchCounts, womenMatchCounts, "Match Count", output);

      // Statistical tests for stage counts
      var menStageCounts = men.map((d) => d.stageCount.toDouble()).toList();
      var womenStageCounts = women.map((d) => d.stageCount.toDouble()).toList();
      _printStatisticalTests(menStageCounts, womenStageCounts, "Stage Count", output);

      // Permutation test for stage counts
      if(menStageCounts.isNotEmpty && womenStageCounts.isNotEmpty) {
        var fileKey = "${men.first.projectName}_${men.first.groupName}_overall_stage".replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        _permutationTestStageCounts(menStageCounts, womenStageCounts, "Overall Stage Count", fileKey, output);
      }

      // Analysis of competition history percentiles
      output.writeln("\n--- Competition History Percentile Analysis ---");
      _printPercentileAnalysis(menMatchCounts, womenMatchCounts, "Match Count", output);
      _printPercentileAnalysis(menStageCounts, womenStageCounts, "Stage Count", output);

      // Analysis of top 25% by rating (above 75th percentile)
      output.writeln("\n--- Top 25% by Rating: Activity Analysis ---");
      var menQ3Rating = _calculatePercentile(menRatings, 75.0);
      var womenQ3Rating = _calculatePercentile(womenRatings, 75.0);

      var topMen = men.where((d) => d.rating > menQ3Rating).toList();
      var topWomen = women.where((d) => d.rating > womenQ3Rating).toList();

      if(topMen.isNotEmpty && topWomen.isNotEmpty) {
        output.writeln("Men above 75th percentile (rating > ${menQ3Rating.toStringAsFixed(2)}): ${topMen.length}");
        output.writeln("Women above 75th percentile (rating > ${womenQ3Rating.toStringAsFixed(2)}): ${topWomen.length}");

        var topMenMatchCounts = topMen.map((d) => d.matchCount.toDouble()).toList();
        var topWomenMatchCounts = topWomen.map((d) => d.matchCount.toDouble()).toList();
        var topMenStageCounts = topMen.map((d) => d.stageCount.toDouble()).toList();
        var topWomenStageCounts = topWomen.map((d) => d.stageCount.toDouble()).toList();

        output.writeln("\n--- Top 25%: Match Count Statistics ---");
        _printStats("Men (Top 25%)", topMenMatchCounts, output);
        _printStats("Women (Top 25%)", topWomenMatchCounts, output);

        output.writeln("\n--- Top 25%: Stage Count Statistics ---");
        _printStats("Men (Top 25%)", topMenStageCounts, output);
        _printStats("Women (Top 25%)", topWomenStageCounts, output);

        output.writeln("\n--- Top 25%: Statistical Tests (Null: No difference) ---");
        _printStatisticalTests(topMenMatchCounts, topWomenMatchCounts, "Match Count (Top 25%)", output);
        _printStatisticalTests(topMenStageCounts, topWomenStageCounts, "Stage Count (Top 25%)", output);

        // Permutation test for top 25% stage counts
        if(topMenStageCounts.isNotEmpty && topWomenStageCounts.isNotEmpty) {
          var fileKey = "${topMen.first.projectName}_${topMen.first.groupName}_top25_stage".replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
          _permutationTestStageCounts(topMenStageCounts, topWomenStageCounts, "Top 25% Stage Count", fileKey, output);
        }
      }
      else {
        output.writeln("Insufficient data for top 25% analysis");
      }

      // Analysis of top 25% by activity: where do they fall in skill distribution?
      output.writeln("\n--- Top 25% by Activity: Rating Percentile Analysis ---");

      // Top 25% by match count
      if(men.length >= 4 && women.length >= 4) {
        var menMatchQ3 = _calculatePercentile(menMatchCounts, 75.0);
        var womenMatchQ3 = _calculatePercentile(womenMatchCounts, 75.0);

        var topActiveMenByMatch = men.where((d) => d.matchCount.toDouble() > menMatchQ3).toList();
        var topActiveWomenByMatch = women.where((d) => d.matchCount.toDouble() > womenMatchQ3).toList();

        if(topActiveMenByMatch.isNotEmpty && topActiveWomenByMatch.isNotEmpty) {
          output.writeln("\n--- Top 25% by Match Count: Rating Analysis ---");
          output.writeln("Men above 75th percentile (match count > ${menMatchQ3.toStringAsFixed(2)}): ${topActiveMenByMatch.length}");
          output.writeln("Women above 75th percentile (match count > ${womenMatchQ3.toStringAsFixed(2)}): ${topActiveWomenByMatch.length}");

          // Calculate rating percentiles within their respective groups
          var topActiveMenRatings = topActiveMenByMatch.map((d) => d.rating).toList();
          var topActiveWomenRatings = topActiveWomenByMatch.map((d) => d.rating).toList();

          // Calculate what percentile these ratings represent within all men/women
          var menRatingsSorted = List<double>.from(menRatings)..sort();
          var womenRatingsSorted = List<double>.from(womenRatings)..sort();

          var menPercentiles = topActiveMenRatings.map((r) => _calculatePercentileRank(r, menRatingsSorted)).toList();
          var womenPercentiles = topActiveWomenRatings.map((r) => _calculatePercentileRank(r, womenRatingsSorted)).toList();

          output.writeln("\nRating Percentiles within Group:");
          output.writeln("  Men (top 25% by activity): Mean ${menPercentiles.average.toStringAsFixed(2)}%, Median ${menPercentiles.median.toStringAsFixed(2)}%");
          output.writeln("  Women (top 25% by activity): Mean ${womenPercentiles.average.toStringAsFixed(2)}%, Median ${womenPercentiles.median.toStringAsFixed(2)}%");

          // Statistical tests on the ratings of top-active competitors
          output.writeln("\n--- Top 25% by Match Count: Rating Statistical Tests ---");
          _printStatisticalTests(topActiveMenRatings, topActiveWomenRatings, "Rating (Top Active)", output);

          // Statistical tests on the percentiles themselves
          output.writeln("\n--- Top 25% by Match Count: Percentile Statistical Tests ---");
          _printStatisticalTests(menPercentiles, womenPercentiles, "Rating Percentile (Top Active)", output);
        }
      }

      // Top 25% by stage count
      if(men.length >= 4 && women.length >= 4) {
        var menStageQ3 = _calculatePercentile(menStageCounts, 75.0);
        var womenStageQ3 = _calculatePercentile(womenStageCounts, 75.0);

        var topActiveMenByStage = men.where((d) => d.stageCount.toDouble() > menStageQ3).toList();
        var topActiveWomenByStage = women.where((d) => d.stageCount.toDouble() > womenStageQ3).toList();

        if(topActiveMenByStage.isNotEmpty && topActiveWomenByStage.isNotEmpty) {
          output.writeln("\n--- Top 25% by Stage Count: Rating Analysis ---");
          output.writeln("Men above 75th percentile (stage count > ${menStageQ3.toStringAsFixed(2)}): ${topActiveMenByStage.length}");
          output.writeln("Women above 75th percentile (stage count > ${womenStageQ3.toStringAsFixed(2)}): ${topActiveWomenByStage.length}");

          // Calculate rating percentiles within their respective groups
          var topActiveMenRatings = topActiveMenByStage.map((d) => d.rating).toList();
          var topActiveWomenRatings = topActiveWomenByStage.map((d) => d.rating).toList();

          // Calculate what percentile these ratings represent within all men/women
          var menRatingsSorted = List<double>.from(menRatings)..sort();
          var womenRatingsSorted = List<double>.from(womenRatings)..sort();

          var menPercentiles = topActiveMenRatings.map((r) => _calculatePercentileRank(r, menRatingsSorted)).toList();
          var womenPercentiles = topActiveWomenRatings.map((r) => _calculatePercentileRank(r, womenRatingsSorted)).toList();

          output.writeln("\nRating Percentiles within Group:");
          output.writeln("  Men (top 25% by activity): Mean ${menPercentiles.average.toStringAsFixed(2)}%, Median ${menPercentiles.median.toStringAsFixed(2)}%");
          output.writeln("  Women (top 25% by activity): Mean ${womenPercentiles.average.toStringAsFixed(2)}%, Median ${womenPercentiles.median.toStringAsFixed(2)}%");

          // Statistical tests on the ratings of top-active competitors
          output.writeln("\n--- Top 25% by Stage Count: Rating Statistical Tests ---");
          _printStatisticalTests(topActiveMenRatings, topActiveWomenRatings, "Rating (Top Active)", output);

          // Statistical tests on the percentiles themselves
          output.writeln("\n--- Top 25% by Stage Count: Percentile Statistical Tests ---");
          _printStatisticalTests(menPercentiles, womenPercentiles, "Rating Percentile (Top Active)", output);
        }
      }

      // Glicko2-specific: Use RD-based confidence intervals if available
      var menWithRD = men.where((d) => d.rd != null).toList();
      var womenWithRD = women.where((d) => d.rd != null).toList();
      if(menWithRD.isNotEmpty && womenWithRD.isNotEmpty) {
        output.writeln("\n--- Rating: Glicko2 RD-Based Confidence Intervals ---");
        // Create a file key from first data point's project/group info
        var fileKey = "${menWithRD.first.projectName}_${menWithRD.first.groupName}".replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        _printGlicko2RDIntervals(menWithRD, womenWithRD, fileKey, output);
      }
    }

    // Correlations
    if(data.length > 1) {
      output.writeln("\n--- Correlations ---");

      // Stage count vs rating
      var stageCounts = data.map((d) => d.stageCount.toDouble()).toList();
      var ratings = data.map((d) => d.rating).toList();
      var stageRatingCorr = _calculateCorrelation(stageCounts, ratings);
      output.writeln("Stage count vs. rating: ${stageRatingCorr.toStringAsFixed(3)}");

      // Match count vs rating
      var matchCounts = data.map((d) => d.matchCount.toDouble()).toList();
      var matchRatingCorr = _calculateCorrelation(matchCounts, ratings);
      output.writeln("Match count vs. rating: ${matchRatingCorr.toStringAsFixed(3)}");

      // Lady vs rating (point-biserial: 0=male, 1=female)
      var sexValues = data.map((d) => d.isFemale ? 1.0 : 0.0).toList();
      var sexRatingCorr = _calculateCorrelation(sexValues, ratings);
      output.writeln("Sex vs. rating: ${sexRatingCorr.toStringAsFixed(3)}");

      // Sex vs match count
      var sexMatchCorr = _calculateCorrelation(sexValues, matchCounts);
      output.writeln("Sex vs. match count: ${sexMatchCorr.toStringAsFixed(3)}");

      // Sex vs stage count
      var sexStageCorr = _calculateCorrelation(sexValues, stageCounts);
      output.writeln("Sex vs. stage count: ${sexStageCorr.toStringAsFixed(3)}");

      // By sex: stage count vs rating
      double? menStageCorr;
      double? womenStageCorr;
      if(men.length > 1) {
        var menStageCounts = men.map((d) => d.stageCount.toDouble()).toList();
        var menRatings = men.map((d) => d.rating).toList();
        menStageCorr = _calculateCorrelation(menStageCounts, menRatings);
        output.writeln("Men: Stage count vs. rating: ${menStageCorr.toStringAsFixed(3)}");
      }

      if(women.length > 1) {
        var womenStageCounts = women.map((d) => d.stageCount.toDouble()).toList();
        var womenRatings = women.map((d) => d.rating).toList();
        womenStageCorr = _calculateCorrelation(womenStageCounts, womenRatings);
        output.writeln("Women: Stage count vs. rating: ${womenStageCorr.toStringAsFixed(3)}");
      }

      // Test if stage count correlation differs between men and women
      if(menStageCorr != null && womenStageCorr != null && men.length > 1 && women.length > 1) {
        var fisherTest = _fisherZTest(menStageCorr, womenStageCorr, men.length, women.length);
        output.writeln("  Fisher's z-test: z=${fisherTest.zStatistic.toStringAsFixed(4)}, p=${fisherTest.pValue.toStringAsFixed(6)}");
        if(fisherTest.pValue < 0.05) {
          if(womenStageCorr > menStageCorr) {
            output.writeln("  *** Women's correlation is significantly higher");
          }
          else {
            output.writeln("  *** Men's correlation is significantly higher");
          }
        }
        else {
          output.writeln("  No significant difference between correlations");
        }
      }

      // By sex: match count vs rating
      double? menMatchCorr;
      double? womenMatchCorr;
      if(men.length > 1) {
        var menMatchCounts = men.map((d) => d.matchCount.toDouble()).toList();
        var menRatings = men.map((d) => d.rating).toList();
        menMatchCorr = _calculateCorrelation(menMatchCounts, menRatings);
        output.writeln("Men: Match count vs. rating: ${menMatchCorr.toStringAsFixed(3)}");
      }

      if(women.length > 1) {
        var womenMatchCounts = women.map((d) => d.matchCount.toDouble()).toList();
        var womenRatings = women.map((d) => d.rating).toList();
        womenMatchCorr = _calculateCorrelation(womenMatchCounts, womenRatings);
        output.writeln("Women: Match count vs. rating: ${womenMatchCorr.toStringAsFixed(3)}");
      }

      // Test if match count correlation differs between men and women
      if(menMatchCorr != null && womenMatchCorr != null && men.length > 1 && women.length > 1) {
        var fisherTest = _fisherZTest(menMatchCorr, womenMatchCorr, men.length, women.length);
        output.writeln("  Fisher's z-test: z=${fisherTest.zStatistic.toStringAsFixed(4)}, p=${fisherTest.pValue.toStringAsFixed(6)}");
        if(fisherTest.pValue < 0.05) {
          if(womenMatchCorr > menMatchCorr) {
            output.writeln("  *** Women's correlation is significantly higher");
          }
          else {
            output.writeln("  *** Men's correlation is significantly higher");
          }
        }
        else {
          output.writeln("  No significant difference between correlations");
        }
      }
    }
  }

  void _printStats(String label, List<double> values, StringBuffer output) {
    if(values.isEmpty) {
      output.writeln("$label: No data");
      return;
    }

    var sorted = List<double>.from(values)..sort();
    var mean = values.average;
    var median = sorted.median;
    var stddev = values.stdDev();
    var min = sorted.first;
    var max = sorted.last;

    var quartiles = _calculateQuartiles(values);
    var p90 = _calculatePercentile(values, 90.0);

    output.writeln("$label:");
    output.writeln("  Count: ${values.length}");
    output.writeln("  Mean: ${mean.toStringAsFixed(2)}");
    output.writeln("  Median: ${median.toStringAsFixed(2)}");
    output.writeln("  Std Dev: ${stddev.toStringAsFixed(2)}");
    output.writeln("  Min: ${min.toStringAsFixed(2)}");
    output.writeln("  Max: ${max.toStringAsFixed(2)}");
    output.writeln("  Q1: ${quartiles.q1.toStringAsFixed(2)}");
    output.writeln("  Q2 (Median): ${quartiles.q2.toStringAsFixed(2)}");
    output.writeln("  Q3: ${quartiles.q3.toStringAsFixed(2)}");
    output.writeln("  90th percentile: ${p90.toStringAsFixed(2)}");
  }

  ({double q1, double q2, double q3}) _calculateQuartiles(List<double> values) {
    if(values.isEmpty) {
      return (q1: 0.0, q2: 0.0, q3: 0.0);
    }

    var sorted = List<double>.from(values)..sort();
    var q2 = sorted.median;

    var lowerHalf = sorted.sublist(0, sorted.length ~/ 2);
    var upperHalf = sorted.sublist((sorted.length + 1) ~/ 2);

    return (
      q1: lowerHalf.isEmpty ? q2 : lowerHalf.median,
      q2: q2,
      q3: upperHalf.isEmpty ? q2 : upperHalf.median,
    );
  }

  double _calculatePercentile(List<double> values, double percentile) {
    if(values.isEmpty) {
      return 0.0;
    }
    if(percentile <= 0) return values.reduce((a, b) => a < b ? a : b);
    if(percentile >= 100) return values.reduce((a, b) => a > b ? a : b);

    var sorted = List<double>.from(values)..sort();
    var index = (percentile / 100.0) * (sorted.length - 1);
    var lower = sorted[index.floor()];
    var upper = sorted[index.ceil()];
    var weight = index - index.floor();
    return lower + weight * (upper - lower);
  }

  double _calculatePercentileRank(double value, List<double> sortedValues) {
    // Calculate what percentile a value falls at within a sorted list
    if(sortedValues.isEmpty) return 0.0;

    // Handle edge cases
    if(value <= sortedValues.first) return 0.0;
    if(value >= sortedValues.last) return 100.0;

    // Find the position using binary search
    var index = sortedValues.indexWhere((v) => v >= value);
    if(index == -1) return 100.0;
    if(index == 0) return 0.0;

    // Linear interpolation between adjacent values
    var lowerIndex = index - 1;
    var upperIndex = index;
    var lowerValue = sortedValues[lowerIndex];
    var upperValue = sortedValues[upperIndex];

    if(lowerValue == upperValue) {
      // All values at this position are equal
      return (lowerIndex / (sortedValues.length - 1)) * 100.0;
    }

    // Interpolate between lower and upper positions
    var weight = (value - lowerValue) / (upperValue - lowerValue);
    var position = lowerIndex + weight;
    return (position / (sortedValues.length - 1)) * 100.0;
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    assert(x.length == y.length);
    if(x.length < 2) return 0.0;

    var n = x.length;
    var xMean = x.average;
    var yMean = y.average;

    var numerator = 0.0;
    var xDenom = 0.0;
    var yDenom = 0.0;

    for(var i = 0; i < n; i++) {
      var xDiff = x[i] - xMean;
      var yDiff = y[i] - yMean;
      numerator += xDiff * yDiff;
      xDenom += xDiff * xDiff;
      yDenom += yDiff * yDiff;
    }

    if(xDenom == 0.0 || yDenom == 0.0) {
      return 0.0;
    }

    return numerator / sqrt(xDenom * yDenom);
  }

  ({double zStatistic, double pValue}) _fisherZTest(double r1, double r2, int n1, int n2) {
    // Fisher's z-transformation: z = 0.5 * ln((1+r)/(1-r))
    double fisherZ(double r) {
      if(r.abs() >= 1.0) return 0.0; // Handle edge case
      return 0.5 * log((1 + r) / (1 - r));
    }

    var z1 = fisherZ(r1);
    var z2 = fisherZ(r2);

    // Standard error of the difference
    var se = sqrt(1.0 / (n1 - 3) + 1.0 / (n2 - 3));

    if(se == 0.0) {
      return (zStatistic: 0.0, pValue: 1.0);
    }

    // Z-statistic for the difference
    var zStatistic = (z1 - z2).abs() / se;

    // Two-tailed p-value using normal distribution
    var pValue = 2 * (1 - Normal.cdf(zStatistic));

    return (zStatistic: zStatistic, pValue: pValue);
  }

  void _printTopLineSummary(List<_ShooterData> data, StringBuffer output) {
    if(data.isEmpty) {
      output.writeln("No data");
      return;
    }

    var men = data.where((d) => !d.isFemale).toList();
    var women = data.where((d) => d.isFemale).toList();

    output.writeln("Total: ${data.length}");
    output.writeln("Men: ${men.length} (${(men.length / data.length * 100).toStringAsFixed(1)}%)");
    output.writeln("Women: ${women.length} (${(women.length / data.length * 100).toStringAsFixed(1)}%)");

    if(men.isNotEmpty) {
      var menRatings = men.map((d) => d.rating).toList();
      output.writeln("\nMen - Rating:");
      output.writeln("  Mean: ${menRatings.average.toStringAsFixed(2)}");
      output.writeln("  Median: ${menRatings.median.toStringAsFixed(2)}");
      output.writeln("  Std Dev: ${menRatings.stdDev().toStringAsFixed(2)}");
    }

    if(women.isNotEmpty) {
      var womenRatings = women.map((d) => d.rating).toList();
      output.writeln("\nWomen - Rating:");
      output.writeln("  Mean: ${womenRatings.average.toStringAsFixed(2)}");
      output.writeln("  Median: ${womenRatings.median.toStringAsFixed(2)}");
      output.writeln("  Std Dev: ${womenRatings.stdDev().toStringAsFixed(2)}");
    }

    if(men.isNotEmpty && women.isNotEmpty) {
      var menRatings = men.map((d) => d.rating).toList();
      var womenRatings = women.map((d) => d.rating).toList();
      var ratingDiff = menRatings.average - womenRatings.average;
      output.writeln("\nRating Difference (Men - Women): ${ratingDiff.toStringAsFixed(2)}");

      // Statistical tests
      _printStatisticalTests(menRatings, womenRatings, "Rating", output);
    }

    if(data.length > 1) {
      var ratings = data.map((d) => d.rating).toList();
      var sexValues = data.map((d) => d.isFemale ? 1.0 : 0.0).toList();
      var sexRatingCorr = _calculateCorrelation(sexValues, ratings);
      output.writeln("\nSex vs. Rating Correlation: ${sexRatingCorr.toStringAsFixed(3)}");
    }
  }

  void _printPercentileAnalysis(List<double> group1, List<double> group2, String label, StringBuffer output) {
    if(group1.isEmpty || group2.isEmpty) {
      return;
    }

    var menMedian = group1.median;
    var womenMedian = group2.median;
    var menQ3 = _calculatePercentile(group1, 75.0);
    var womenQ3 = _calculatePercentile(group2, 75.0);
    var menP90 = _calculatePercentile(group1, 90.0);
    var womenP90 = _calculatePercentile(group2, 90.0);

    output.writeln("\n--- $label: Percentile Comparison ---");
    output.writeln("  Median - Men: ${menMedian.toStringAsFixed(2)}, Women: ${womenMedian.toStringAsFixed(2)}, Difference: ${(menMedian - womenMedian).toStringAsFixed(2)}");
    output.writeln("  Q3 (75th) - Men: ${menQ3.toStringAsFixed(2)}, Women: ${womenQ3.toStringAsFixed(2)}, Difference: ${(menQ3 - womenQ3).toStringAsFixed(2)}");
    output.writeln("  90th percentile - Men: ${menP90.toStringAsFixed(2)}, Women: ${womenP90.toStringAsFixed(2)}, Difference: ${(menP90 - womenP90).toStringAsFixed(2)}");
  }

  void _printStatisticalTests(List<double> group1, List<double> group2, String label, StringBuffer output) {
    if(group1.length < 2 || group2.length < 2) {
      output.writeln("\nInsufficient data for statistical tests");
      return;
    }

    // Two-sample t-test (Welch's t-test for unequal variances)
    var tTestResult = _welchTTest(group1, group2);
    output.writeln("\n--- $label: Two-Sample t-test (Welch's) ---");
    output.writeln("  t-statistic: ${tTestResult.tStatistic.toStringAsFixed(4)}");
    output.writeln("  p-value: ${tTestResult.pValue.toStringAsFixed(6)}");
    output.writeln("  ${tTestResult.pValue < 0.05 ? "***" : tTestResult.pValue < 0.01 ? "**" : tTestResult.pValue < 0.1 ? "*" : ""} ${_interpretPValue(tTestResult.pValue)}");

    // Mann-Whitney U test (non-parametric)
    var mwResult = _mannWhitneyUTest(group1, group2);
    output.writeln("\n--- $label: Mann-Whitney U Test (Non-parametric) ---");
    output.writeln("  U-statistic: ${mwResult.uStatistic.toStringAsFixed(2)}");
    output.writeln("  p-value: ${mwResult.pValue.toStringAsFixed(6)}");
    output.writeln("  ${mwResult.pValue < 0.05 ? "***" : mwResult.pValue < 0.01 ? "**" : mwResult.pValue < 0.1 ? "*" : ""} ${_interpretPValue(mwResult.pValue)}");

    // Effect size (Cohen's d and Cliff's delta)
    var cohensD = _cohensD(group1, group2);
    var cliffsDelta = _cliffsDelta(group1, group2);
    output.writeln("\n--- $label: Effect Size ---");
    output.writeln("  Cohen's d: ${cohensD.toStringAsFixed(4)}");
    output.writeln("  ${_interpretCohensD(cohensD)}");
    output.writeln("  Cliff's δ: ${cliffsDelta.toStringAsFixed(4)}");
    output.writeln("  ${_interpretCliffsDelta(cliffsDelta)}");

    // Confidence interval for mean difference
    var ci = _confidenceIntervalForMeanDifference(group1, group2, 0.95);
    output.writeln("\n--- $label: 95% Confidence Interval for Mean Difference ---");
    output.writeln("  CI: [${ci.lower.toStringAsFixed(2)}, ${ci.upper.toStringAsFixed(2)}]");
    if(ci.lower > 0 || ci.upper < 0) {
      output.writeln("  Difference is statistically significant (CI does not contain 0)");
    }
    else {
      output.writeln("  Difference is not statistically significant (CI contains 0)");
    }
  }

  String _interpretPValue(double pValue) {
    if(pValue < 0.001) return "Highly significant (p < 0.001)";
    if(pValue < 0.01) return "Very significant (p < 0.01)";
    if(pValue < 0.05) return "Significant (p < 0.05)";
    if(pValue < 0.1) return "Marginally significant (p < 0.1)";
    return "Not significant (p >= 0.1)";
  }

  String _interpretCohensD(double d) {
    var absD = d.abs();
    if(absD < 0.2) return "Negligible effect";
    if(absD < 0.5) return "Small effect";
    if(absD < 0.8) return "Medium effect";
    return "Large effect";
  }

  double _cliffsDelta(List<double> group1, List<double> group2) {
    // Cliff's delta: δ = P(X > Y) - P(X < Y)
    // Non-parametric effect size measure that doesn't assume normality
    var n1 = group1.length;
    var n2 = group2.length;
    if(n1 == 0 || n2 == 0) return 0.0;

    var greater = 0;
    var less = 0;

    for(var x in group1) {
      for(var y in group2) {
        if(x > y) {
          greater++;
        }
        else if(x < y) {
          less++;
        }
        // If x == y, neither counter increments (ties don't contribute)
      }
    }

    var totalPairs = n1 * n2;
    return (greater - less) / totalPairs;
  }

  String _interpretCliffsDelta(double delta) {
    // Interpretation based on Romano et al. (2006) and Vargha & Delaney (2000)
    // Thresholds: |δ| < 0.147 (negligible), 0.147-0.33 (small), 0.33-0.474 (medium), ≥0.474 (large)
    var absDelta = delta.abs();
    if(absDelta < 0.147) return "Negligible effect";
    if(absDelta < 0.33) return "Small effect";
    if(absDelta < 0.474) return "Medium effect";
    return "Large effect";
  }

  ({double tStatistic, double pValue}) _welchTTest(List<double> group1, List<double> group2) {
    var n1 = group1.length;
    var n2 = group2.length;

    var mean1 = group1.average;
    var mean2 = group2.average;
    var var1 = group1.stdDev() * group1.stdDev();
    var var2 = group2.stdDev() * group2.stdDev();

    // Welch's t-test statistic
    var se = sqrt(var1 / n1 + var2 / n2);
    var tStatistic = (mean1 - mean2) / se;

    // Degrees of freedom (Welch-Satterthwaite equation)
    var df = pow(var1 / n1 + var2 / n2, 2) /
             (pow(var1 / n1, 2) / (n1 - 1) + pow(var2 / n2, 2) / (n2 - 1));

    // Two-tailed p-value using t-distribution approximation
    // Using normal approximation for large samples, or t-distribution for small
    var pValue = _twoTailedPValue(tStatistic, df);

    return (tStatistic: tStatistic, pValue: pValue);
  }

  ({double uStatistic, double pValue}) _mannWhitneyUTest(List<double> group1, List<double> group2) {
    // Combine and rank
    var combined = <({double value, int group})>[];
    for(var v in group1) {
      combined.add((value: v, group: 1));
    }
    for(var v in group2) {
      combined.add((value: v, group: 2));
    }

    combined.sort((a, b) => a.value.compareTo(b.value));

    // Assign ranks (handle ties)
    var ranks = List<double>.filled(combined.length, 0.0);
    int i = 0;
    while(i < combined.length) {
      int j = i;
      while(j < combined.length && combined[j].value == combined[i].value) {
        j++;
      }

      // Average rank for tied values
      var avgRank = (i + j + 1) / 2.0;
      for(int k = i; k < j; k++) {
        ranks[k] = avgRank;
      }
      i = j;
    }

    // Calculate U statistic
    double r1 = 0.0;
    for(int k = 0; k < combined.length; k++) {
      if(combined[k].group == 1) {
        r1 += ranks[k];
      }
    }

    var n1 = group1.length;
    var n2 = group2.length;
    var u1 = n1 * n2 + (n1 * (n1 + 1)) / 2 - r1;
    var u2 = n1 * n2 - u1;
    var uStatistic = min(u1, u2);

    // Normal approximation for p-value (works well for n1, n2 > 20)
    var meanU = (n1 * n2) / 2.0;
    var varU = (n1 * n2 * (n1 + n2 + 1)) / 12.0;
    var z = (uStatistic - meanU) / sqrt(varU);
    var pValue = _twoTailedPValue(z, double.infinity); // Use normal distribution

    return (uStatistic: uStatistic, pValue: pValue);
  }

  double _cohensD(List<double> group1, List<double> group2) {
    var mean1 = group1.average;
    var mean2 = group2.average;
    var var1 = group1.stdDev() * group1.stdDev();
    var var2 = group2.stdDev() * group2.stdDev();
    var n1 = group1.length;
    var n2 = group2.length;

    // Pooled standard deviation
    var pooledStd = sqrt(((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2));

    if(pooledStd == 0) return 0.0;

    return (mean1 - mean2) / pooledStd;
  }

  ({double lower, double upper}) _confidenceIntervalForMeanDifference(List<double> group1, List<double> group2, double confidence) {
    var n1 = group1.length;
    var n2 = group2.length;
    var mean1 = group1.average;
    var mean2 = group2.average;
    var var1 = group1.stdDev() * group1.stdDev();
    var var2 = group2.stdDev() * group2.stdDev();

    // Standard error
    var se = sqrt(var1 / n1 + var2 / n2);

    // Degrees of freedom (Welch-Satterthwaite)
    var df = pow(var1 / n1 + var2 / n2, 2) /
             (pow(var1 / n1, 2) / (n1 - 1) + pow(var2 / n2, 2) / (n2 - 1));

    // Critical value (using t-distribution approximation)
    var alpha = 1 - confidence;
    var tCritical = _tCriticalValue(df, alpha / 2);

    var diff = mean1 - mean2;
    var margin = tCritical * se;

    return (lower: diff - margin, upper: diff + margin);
  }

  double _twoTailedPValue(double statistic, double df) {
    // Use proper distributions: normal for large df, t-distribution for small df
    var absStat = statistic.abs();
    if(df.isInfinite || df > 100) {
      // Normal distribution: P(|Z| > z) = 2 * (1 - Φ(z))
      return 2 * (1 - Normal.cdf(absStat));
    }
    else {
      // t-distribution: P(|T| > t) = 2 * (1 - F(t))
      var tDist = StudentDistribution(df);
      return 2 * (1 - tDist.cumulativeProbability(absStat));
    }
  }

  double _tCriticalValue(double df, double alpha) {
    // Use proper t-distribution inverse CDF for critical values
    if(df.isInfinite || df > 100) {
      // For large df, use normal distribution
      return Normal.quantile(1 - alpha);
    }
    else {
      // Use Student's t-distribution inverse CDF
      var tDist = StudentDistribution(df);
      return tDist.inverseCumulativeProbability(1 - alpha);
    }
  }

  void _printGlicko2RDIntervals(List<_ShooterData> men, List<_ShooterData> women, String fileKey, StringBuffer output) {
    // Calculate mean rating and mean RD for each group
    var menRatings = men.map((d) => d.rating).toList();
    var menRDs = men.map((d) => d.rd!).toList();
    var womenRatings = women.map((d) => d.rating).toList();
    var womenRDs = women.map((d) => d.rd!).toList();

    var menMeanRating = menRatings.average;
    var menMeanRD = menRDs.average;
    var womenMeanRating = womenRatings.average;
    var womenMeanRD = womenRDs.average;

    // 95% CI = rating ± 2*RD
    var menCI = (lower: menMeanRating - 2 * menMeanRD, upper: menMeanRating + 2 * menMeanRD);
    var womenCI = (lower: womenMeanRating - 2 * womenMeanRD, upper: womenMeanRating + 2 * womenMeanRD);

    output.writeln("Men:");
    output.writeln("  Mean Rating: ${menMeanRating.toStringAsFixed(2)}");
    output.writeln("  Mean RD: ${menMeanRD.toStringAsFixed(2)}");
    output.writeln("  95% CI: [${menCI.lower.toStringAsFixed(2)}, ${menCI.upper.toStringAsFixed(2)}]");

    output.writeln("\nWomen:");
    output.writeln("  Mean Rating: ${womenMeanRating.toStringAsFixed(2)}");
    output.writeln("  Mean RD: ${womenMeanRD.toStringAsFixed(2)}");
    output.writeln("  95% CI: [${womenCI.lower.toStringAsFixed(2)}, ${womenCI.upper.toStringAsFixed(2)}]");

    // Check for overlap
    var overlap = !(menCI.upper < womenCI.lower || womenCI.upper < menCI.lower);
    output.writeln("\nInterval Overlap: ${overlap ? "Yes" : "No"}");
    if(overlap) {
      var overlapLower = max(menCI.lower, womenCI.lower);
      var overlapUpper = min(menCI.upper, womenCI.upper);
      output.writeln("  Overlap Range: [${overlapLower.toStringAsFixed(2)}, ${overlapUpper.toStringAsFixed(2)}]");
    }
    else {
      var gap = menCI.lower > womenCI.upper
          ? menCI.lower - womenCI.upper
          : womenCI.lower - menCI.upper;
      output.writeln("  Gap between intervals: ${gap.toStringAsFixed(2)}");
    }

    // Also show individual-level overlap percentage
    int overlapping = 0;
    int total = 0;
    List<({double rating, double rd})> menRatingsWithRD = [];
    List<({double rating, double rd})> womenRatingsWithRD = [];

    // Build lists first
    for(var man in men) {
      menRatingsWithRD.add((rating: man.rating, rd: man.rd!));
    }
    for(var woman in women) {
      womenRatingsWithRD.add((rating: woman.rating, rd: woman.rd!));
    }

    // Count overlaps
    for(var man in men) {
      var manCI = (lower: man.rating - 2 * man.rd!, upper: man.rating + 2 * man.rd!);
      for(var woman in women) {
        total++;
        var womanCI = (lower: woman.rating - 2 * woman.rd!, upper: woman.rating + 2 * woman.rd!);
        if(!(manCI.upper < womanCI.lower || womanCI.upper < manCI.lower)) {
          overlapping++;
        }
      }
    }
    if(total > 0) {
      var overlapPercent = (overlapping / total * 100);
      output.writeln("\nIndividual-Level Overlap: ${overlapping}/${total} pairs (${overlapPercent.toStringAsFixed(1)}%)");

      // Statistical tests for overlap significance
      output.writeln("\n--- Overlap Significance Tests ---");
      var projectGroupKey = "${menRatingsWithRD.length}_men_${womenRatingsWithRD.length}_women";
      _testOverlapSignificance(menRatingsWithRD, womenRatingsWithRD, overlapping, total, projectGroupKey, output);
    }
  }

  void _testOverlapSignificance(
    List<({double rating, double rd})> men,
    List<({double rating, double rd})> women,
    int observedOverlapping,
    int totalPairs,
    String fileKey,
    StringBuffer output,
  ) {
    // Test 1: Expected overlap under null hypothesis (ratings are the same)
    // If all ratings were the same, overlap would depend only on RDs
    // We can calculate expected overlap by simulating or using a simpler approximation

    // Test 2: Permutation test - shuffle ratings and see how often we get this much overlap
    // This tests if the observed overlap is significantly different from random

    // Test 3: Test if mean difference is within combined uncertainty
    var menMean = men.map((m) => m.rating).average;
    var womenMean = women.map((w) => w.rating).average;
    var meanDiff = menMean - womenMean;

    // Combined uncertainty: sqrt(mean(RD_men)^2 + mean(RD_women)^2)
    var menMeanRD = men.map((m) => m.rd).average;
    var womenMeanRD = women.map((w) => w.rd).average;
    var combinedUncertainty = sqrt(menMeanRD * menMeanRD + womenMeanRD * womenMeanRD);
    var combinedCI = 2 * combinedUncertainty;

    output.writeln("Mean Difference: ${meanDiff.toStringAsFixed(2)}");
    output.writeln("Combined 95% CI (2*√(RD_men² + RD_women²)): ±${combinedCI.toStringAsFixed(2)}");
    if(meanDiff.abs() <= combinedCI) {
      output.writeln("  → Mean difference is within combined uncertainty (not significant)");
    }
    else {
      output.writeln("  → Mean difference exceeds combined uncertainty (significant)");
    }

    // Permutation test
    output.writeln("\n--- Permutation Test (1000 iterations) ---");
    var permutedOverlaps = <int>[];
    var allRatings = [...men.map((m) => m.rating), ...women.map((w) => w.rating)];

    for(int i = 0; i < 1000; i++) {
      // Shuffle ratings but keep RDs with their original groups
      var shuffled = List<double>.from(allRatings)..shuffle();
      var shuffledMen = shuffled.sublist(0, men.length);
      var shuffledWomen = shuffled.sublist(men.length);

      // Reconstruct with original RDs
      var permutedMen = <({double rating, double rd})>[];
      var permutedWomen = <({double rating, double rd})>[];
      for(int j = 0; j < men.length; j++) {
        permutedMen.add((rating: shuffledMen[j], rd: men[j].rd));
      }
      for(int j = 0; j < women.length; j++) {
        permutedWomen.add((rating: shuffledWomen[j], rd: women[j].rd));
      }

      // Count overlaps
      int permutedOverlapping = 0;
      for(var m in permutedMen) {
        var mCI = (lower: m.rating - 2 * m.rd, upper: m.rating + 2 * m.rd);
        for(var w in permutedWomen) {
          var wCI = (lower: w.rating - 2 * w.rd, upper: w.rating + 2 * w.rd);
          if(!(mCI.upper < wCI.lower || wCI.upper < mCI.lower)) {
            permutedOverlapping++;
          }
        }
      }
      permutedOverlaps.add(permutedOverlapping);
    }

    permutedOverlaps.sort();
    var permutedMean = permutedOverlaps.average;
    var permutedMedian = permutedOverlaps[permutedOverlaps.length ~/ 2];
    var permutedStdDev = permutedOverlaps.stdDev();

    // Two-tailed p-value: how extreme is observed compared to permuted distribution?
    var countExtreme = permutedOverlaps.where((o) =>
      o >= observedOverlapping || o <= (2 * permutedMean - observedOverlapping)
    ).length;
    var pValueTwoTailed = countExtreme / 1000.0;

    // One-tailed p-values for both directions
    var countGreaterOrEqual = permutedOverlaps.where((o) => o >= observedOverlapping).length;
    var pValueGreater = countGreaterOrEqual / 1000.0;
    var pValueLess = (1000 - countGreaterOrEqual) / 1000.0;

    output.writeln("  Permuted mean overlap: ${permutedMean.toStringAsFixed(1)}");
    output.writeln("  Permuted median overlap: ${permutedMedian.toStringAsFixed(1)}");
    output.writeln("  Permuted std dev: ${permutedStdDev.toStringAsFixed(1)}");
    output.writeln("  Observed overlap: $observedOverlapping");
    output.writeln("  Difference from mean: ${(observedOverlapping - permutedMean).toStringAsFixed(1)} (${((observedOverlapping - permutedMean) / permutedStdDev).toStringAsFixed(2)} std devs)");

    if(observedOverlapping > permutedMean) {
      output.writeln("  Observed is HIGHER than permuted mean");
      output.writeln("  p-value (one-tailed, greater): ${pValueGreater.toStringAsFixed(4)}");
      output.writeln("  ${pValueGreater < 0.05 ? "***" : pValueGreater < 0.01 ? "**" : pValueGreater < 0.1 ? "*" : ""} ${_interpretPValue(pValueGreater)}");
    }
    else {
      output.writeln("  Observed is LOWER than permuted mean");
      output.writeln("  p-value (one-tailed, less): ${pValueLess.toStringAsFixed(4)}");
      output.writeln("  ${pValueLess < 0.05 ? "***" : pValueLess < 0.01 ? "**" : pValueLess < 0.1 ? "*" : ""} ${_interpretPValue(pValueLess)}");
    }

    output.writeln("  p-value (two-tailed): ${pValueTwoTailed.toStringAsFixed(4)}");
    output.writeln("  ${pValueTwoTailed < 0.05 ? "***" : pValueTwoTailed < 0.01 ? "**" : pValueTwoTailed < 0.1 ? "*" : ""} ${_interpretPValue(pValueTwoTailed)}");

    // Dump permutation test results to CSV file for graphing
    _dumpPermutationTestToFile(permutedOverlaps, observedOverlapping, fileKey);
  }

  void _dumpPermutationTestToFile(List<int> permutedOverlaps, int observedOverlapping, String fileKey) {
    try {
      var csvLines = <String>["Iteration,OverlapCount"];
      for(int i = 0; i < permutedOverlaps.length; i++) {
        csvLines.add("$i,${permutedOverlaps[i]}");
      }
      csvLines.add("observed,$observedOverlapping");

      var csv = csvLines.join("\n");
      var file = File("/tmp/lady_rating_permutation_test_$fileKey.csv");
      file.writeAsStringSync(csv);
    }
    catch(e) {
      // Silently fail if file write doesn't work
    }
  }

  void _permutationTestStageCounts(
    List<double> group1,
    List<double> group2,
    String label,
    String fileKey,
    StringBuffer output,
  ) {
    if(group1.isEmpty || group2.isEmpty) return;

    // Observed mean difference (group1 - group2)
    var observedDiff = group1.average - group2.average;
    var n1 = group1.length;

    // Combine all values
    var allValues = [...group1, ...group2];

    // Permutation test: randomly assign values to two groups
    var permutedDiffs = <double>[];
    var random = Random();

    for(int i = 0; i < 1000; i++) {
      // Shuffle
      var shuffled = List<double>.from(allValues);
      for(int j = shuffled.length - 1; j > 0; j--) {
        var k = random.nextInt(j + 1);
        var temp = shuffled[j];
        shuffled[j] = shuffled[k];
        shuffled[k] = temp;
      }

      // Assign to groups
      var permutedGroup1 = shuffled.sublist(0, n1);
      var permutedGroup2 = shuffled.sublist(n1);

      // Calculate mean difference
      var permutedDiff = permutedGroup1.average - permutedGroup2.average;
      permutedDiffs.add(permutedDiff);
    }

    permutedDiffs.sort();
    var permutedMean = permutedDiffs.average;
    var permutedMedian = permutedDiffs[permutedDiffs.length ~/ 2];
    var permutedStdDev = permutedDiffs.stdDev();

    // Calculate p-values
    var countGreaterOrEqual = permutedDiffs.where((d) => d >= observedDiff).length;
    var pValueGreater = countGreaterOrEqual / 1000.0;
    var pValueLess = (1000 - countGreaterOrEqual) / 1000.0;

    // Two-tailed: count how many are as extreme or more extreme
    var countExtreme = permutedDiffs.where((d) =>
      d.abs() >= observedDiff.abs()
    ).length;
    var pValueTwoTailed = countExtreme / 1000.0;

    output.writeln("\n--- $label: Permutation Test (1000 iterations) ---");
    output.writeln("  Observed mean difference (Men - Women): ${observedDiff.toStringAsFixed(2)}");
    output.writeln("  Permuted mean difference: ${permutedMean.toStringAsFixed(2)}");
    output.writeln("  Permuted median difference: ${permutedMedian.toStringAsFixed(2)}");
    output.writeln("  Permuted std dev: ${permutedStdDev.toStringAsFixed(2)}");
    output.writeln("  Difference from mean: ${(observedDiff - permutedMean).toStringAsFixed(2)} (${((observedDiff - permutedMean) / permutedStdDev).toStringAsFixed(2)} std devs)");

    if(observedDiff > permutedMean) {
      output.writeln("  Observed is HIGHER than permuted mean");
      output.writeln("  p-value (one-tailed, greater): ${pValueGreater.toStringAsFixed(4)}");
      output.writeln("  ${pValueGreater < 0.05 ? "***" : pValueGreater < 0.01 ? "**" : pValueGreater < 0.1 ? "*" : ""} ${_interpretPValue(pValueGreater)}");
    }
    else {
      output.writeln("  Observed is LOWER than permuted mean");
      output.writeln("  p-value (one-tailed, less): ${pValueLess.toStringAsFixed(4)}");
      output.writeln("  ${pValueLess < 0.05 ? "***" : pValueLess < 0.01 ? "**" : pValueLess < 0.1 ? "*" : ""} ${_interpretPValue(pValueLess)}");
    }

    output.writeln("  p-value (two-tailed): ${pValueTwoTailed.toStringAsFixed(4)}");
    output.writeln("  ${pValueTwoTailed < 0.05 ? "***" : pValueTwoTailed < 0.01 ? "**" : pValueTwoTailed < 0.1 ? "*" : ""} ${_interpretPValue(pValueTwoTailed)}");

    // Dump to CSV file
    try {
      var csvLines = <String>["Iteration,MeanDifference"];
      for(int i = 0; i < permutedDiffs.length; i++) {
        csvLines.add("${i + 1},${permutedDiffs[i]}");
      }
      csvLines.add("Observed,$observedDiff");

      var csv = csvLines.join("\n");
      var file = File("/tmp/lady_rating_stagecount_permutation_test_$fileKey.csv");
      file.writeAsStringSync(csv);
    }
    catch(e) {
      // Silently fail if file write doesn't work
    }
  }

}

class _ShooterData {
  final String projectName;
  final String groupName;
  final String memberNumber;
  final String name;
  final bool isFemale;
  final double rating;
  final int matchCount;
  final int stageCount;
  final double? rd; // Rating Deviation (for Glicko2)

  _ShooterData({
    required this.projectName,
    required this.groupName,
    required this.memberNumber,
    required this.name,
    required this.isFemale,
    required this.rating,
    required this.matchCount,
    required this.stageCount,
    this.rd,
  });
}

