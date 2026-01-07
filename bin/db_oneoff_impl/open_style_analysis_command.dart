/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dart_console/src/console.dart';
import 'package:data/stats.dart' show StudentDistribution;
import 'package:normal/normal.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/model/career_stats.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

/// Do people shoot Open differently?
///
/// Look at alpha percentages in Open vs. CO to compare.
class OpenStyleAnalysisCommand extends DbOneoffCommand {
  OpenStyleAnalysisCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "OSA";
  @override
  final String title = "Open Style Analysis";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");
    if(project == null) {
      console.print("Project not found");
      return;
    }

    var openGroup = project.groupForDivisionSync(uspsaOpen);
    var coGroup = project.groupForDivisionSync(uspsaCarryOptics);

    var openRatingsRes = await project.getRatings(openGroup!);
    var coRatingsRes = await project.getRatings(coGroup!);

    if(openRatingsRes.isErr() || coRatingsRes.isErr()) {
      console.print("Error getting ratings: ${openRatingsRes.unwrapErr()} ${coRatingsRes.unwrapErr()}");
      return;
    }

    var openRatings = openRatingsRes.unwrap();
    var coRatings = coRatingsRes.unwrap();

    // Map of Open member numbers to Open ratings.
    Map<String, _SingleCompetitor> crossoverMap = {};
    List<_CrossoverCompetitor> crossoverCompetitors = [];

    List<_SingleCompetitor> openCompetitors = [];
    List<_SingleCompetitor> coCompetitors = [];
    Map<int, List<_SingleCompetitor>> openAlphaPercentagesByYear = {};
    Map<int, List<_SingleCompetitor>> coAlphaPercentagesByYear = {};

    var progressBar = LabeledProgressBar(maxValue: openRatings.length, canHaveErrors: true, initialLabel: "Processing Open ratings");
    for(var openRating in openRatings) {
      progressBar.tick("Processing Open rating: ${openRating.name}");

      if(openRating.length < 10) {
        continue;
      }

      var wrapped = project.wrapDbRatingSync(openRating);
      var openCareerStats = CareerStats(uspsaSport, wrapped);
      var careerAlphaPercentage = openCareerStats.careerStats.totalScore?.hitPercentages(uspsaSport).entries.firstWhereOrNull((e) => e.key.name == "A")?.value ?? 0.0;
      var careerCharliePercentage = openCareerStats.careerStats.totalScore?.hitPercentages(uspsaSport).entries.firstWhereOrNull((e) => e.key.name == "C")?.value ?? 0.0;

      var openCompetitor = _SingleCompetitor(
        rating: wrapped,
        alphaPercentage: careerAlphaPercentage,
        charliePercentage: careerCharliePercentage,
      );
      openCompetitors.add(openCompetitor);

      for(var year in openCareerStats.years) {
        var hitPercentages = openCareerStats.statsForYear(year)?.totalScore?.hitPercentages(uspsaSport);
        if(hitPercentages != null) {
          var annualOpenCompetitor = _SingleCompetitor(
            rating: wrapped,
            alphaPercentage: hitPercentages.entries.firstWhereOrNull((e) => e.key.name == "A")?.value ?? 0.0,
            charliePercentage: hitPercentages.entries.firstWhereOrNull((e) => e.key.name == "C")?.value ?? 0.0,
          );
          openAlphaPercentagesByYear.addToList(year, annualOpenCompetitor);
        }
      }

      for(var memberNumber in wrapped.allPossibleMemberNumbers) {
        crossoverMap[memberNumber] = openCompetitor;
      }
    }
    progressBar.complete();

    progressBar = LabeledProgressBar(maxValue: coRatings.length, canHaveErrors: true, initialLabel: "Processing Carry Optics ratings");
    for(var coRating in coRatings) {
      progressBar.tick("Processing Carry Optics rating: ${coRating.name}");

      if(coRating.length < 10) {
        continue;
      }

      var wrapped = project.wrapDbRatingSync(coRating);
      var coCareerStats = CareerStats(uspsaSport, wrapped);
      for(var year in coCareerStats.years) {
        var hitPercentages = coCareerStats.statsForYear(year)?.totalScore?.hitPercentages(uspsaSport);
        if(hitPercentages != null) {
          var annualCoCompetitor = _SingleCompetitor(
            rating: wrapped,
            alphaPercentage: hitPercentages.entries.firstWhereOrNull((e) => e.key.name == "A")?.value ?? 0.0,
            charliePercentage: hitPercentages.entries.firstWhereOrNull((e) => e.key.name == "C")?.value ?? 0.0,
          );
          coAlphaPercentagesByYear.addToList(year, annualCoCompetitor);
        }
      }

      var careerAlphaPercentage = coCareerStats.careerStats.totalScore?.hitPercentages(uspsaSport).entries.firstWhereOrNull((e) => e.key.name == "A")?.value ?? 0.0;
      var careerCharliePercentage = coCareerStats.careerStats.totalScore?.hitPercentages(uspsaSport).entries.firstWhereOrNull((e) => e.key.name == "C")?.value ?? 0.0;

      var coCompetitor = _SingleCompetitor(
        rating: wrapped,
        alphaPercentage: careerAlphaPercentage,
        charliePercentage: careerCharliePercentage,
      );
      coCompetitors.add(coCompetitor);

      for(var memberNumber in coRating.allPossibleMemberNumbers) {
        var openCompetitor = crossoverMap[memberNumber];
        if(openCompetitor != null) {

          crossoverCompetitors.add(_CrossoverCompetitor(
            openRating: openCompetitor.rating,
            coRating: wrapped,
            openAlphaPercentage: openCompetitor.alphaPercentage,
            openCharliePercentage: openCompetitor.charliePercentage,
            coAlphaPercentage: careerAlphaPercentage,
            coCharliePercentage: careerCharliePercentage,
          ));
          progressBar.error("Found crossover competitor: ${openCompetitor.rating.name} (Open ${openCompetitor.rating.formattedRating()}, CO ${wrapped.formattedRating()})");
          break;
        }
      }
    }

    progressBar.complete();

    // Dump annual numbers to text files
    for(var year in openAlphaPercentagesByYear.keys) {
      var file = File("/tmp/open_alpha_percentages_${year}.csv");
      file.writeAsStringSync(openAlphaPercentagesByYear[year]?.
        map((e) => "${e.rating.memberNumber},\"${e.rating.name}\",${e.alphaPercentage},${e.charliePercentage},${e.otherPercentage},${e.rating.rating}, ${e.rating.length}").join("\n") ?? "");
    }
    for(var year in coAlphaPercentagesByYear.keys) {
      var file = File("/tmp/co_alpha_percentages_${year}.csv");
      file.writeAsStringSync(coAlphaPercentagesByYear[year]?.
        map((e) => "${e.rating.memberNumber},\"${e.rating.name}\",${e.alphaPercentage},${e.charliePercentage},${e.otherPercentage},${e.rating.rating}, ${e.rating.length}").join("\n") ?? "");
    }

    // Dump crossover data to CSV
    var csv = StringBuffer();
    csv.writeln("Open Member Number,Open Name,Open Alpha Percentage,Open Charlie Percentage,Open Other Percentage,Open Length,Carry Optics Member Number,Carry Optics Name,Carry Optics Alpha Percentage,Carry Optics Charlie Percentage,Carry Optics Other Percentage,Carry Optics Length");
    for(var competitor in crossoverCompetitors) {
      csv.writeln("${competitor.openRating.memberNumber},\"${competitor.openRating.name}\",${competitor.openAlphaPercentage},${competitor.openCharliePercentage},${competitor.openOtherPercentage},${competitor.openRating.length},${competitor.coRating.memberNumber},\"${competitor.coRating.name}\",${competitor.coAlphaPercentage},${competitor.coCharliePercentage},${competitor.coOtherPercentage},${competitor.coRating.length }");
    }
    var file = File("/tmp/crossover_data.csv");
    file.writeAsStringSync(csv.toString());

    // Dump overall data to text files
    var openFile = File("/tmp/open_alpha_percentages.csv");
    openFile.writeAsStringSync(openCompetitors.map((e) => "${e.rating.memberNumber},\"${e.rating.name}\",${e.alphaPercentage},${e.charliePercentage},${e.otherPercentage},${e.rating.rating}, ${e.rating.length}").join("\n"));
    var coFile = File("/tmp/co_alpha_percentages.csv");
    coFile.writeAsStringSync(coCompetitors.map((e) => "${e.rating.memberNumber},\"${e.rating.name}\",${e.alphaPercentage},${e.charliePercentage},${e.otherPercentage},${e.rating.rating}, ${e.rating.length}  ").join("\n"));

    if(openCompetitors.isEmpty || coCompetitors.isEmpty) {
      console.print("Insufficient data for analysis");
      return;
    }

    // Print summary statistics
    console.print("\n=== Summary Statistics ===");
    console.print("\nOpen Division:");
    console.print("  Sample size: ${openCompetitors.length}");
    console.print("  Mean: ${openCompetitors.map((e) => e.alphaPercentage).average.toStringAsFixed(4)}");
    console.print("  Median: ${openCompetitors.map((e) => e.alphaPercentage).toList().median.toStringAsFixed(4)}");
    console.print("  Std Dev: ${openCompetitors.map((e) => e.alphaPercentage).stdDev().toStringAsFixed(4)}");
    console.print("  Min: ${openCompetitors.map((e) => e.alphaPercentage).min.toStringAsFixed(4)}");
    console.print("  Max: ${openCompetitors.map((e) => e.alphaPercentage).max.toStringAsFixed(4)}");

    console.print("\nCarry Optics Division:");
    console.print("  Sample size: ${coCompetitors.length}");
    console.print("  Mean: ${coCompetitors.map((e) => e.alphaPercentage).average.toStringAsFixed(4)}");
    console.print("  Median: ${coCompetitors.map((e) => e.alphaPercentage).toList().median.toStringAsFixed(4)}");
    console.print("  Std Dev: ${coCompetitors.map((e) => e.alphaPercentage).stdDev().toStringAsFixed(4)}");
    console.print("  Min: ${coCompetitors.map((e) => e.alphaPercentage).min.toStringAsFixed(4)}");
    console.print("  Max: ${coCompetitors.map((e) => e.alphaPercentage).max.toStringAsFixed(4)}");

    // Normality tests
    console.print("\n=== Normality Tests ===");
    var openNormality = _testNormality(openCompetitors.map((e) => e.alphaPercentage).toList());
    var coNormality = _testNormality(coCompetitors.map((e) => e.alphaPercentage).toList());

    console.print("\nOpen Division:");
    console.print("  D'Agostino-Pearson test:");
    console.print("    K² statistic: ${openNormality.k2Statistic.toStringAsFixed(4)}");
    console.print("    p-value: ${openNormality.pValue.toStringAsFixed(6)}");
    console.print("    ${openNormality.pValue < 0.05 ? "Not normally distributed (p < 0.05)" : "Normally distributed (p >= 0.05)"}");
    console.print("    Skewness: ${openNormality.skewness.toStringAsFixed(4)}");
    console.print("    Kurtosis: ${openNormality.kurtosis.toStringAsFixed(4)}");

    console.print("\nCarry Optics Division:");
    console.print("  D'Agostino-Pearson test:");
    console.print("    K² statistic: ${coNormality.k2Statistic.toStringAsFixed(4)}");
    console.print("    p-value: ${coNormality.pValue.toStringAsFixed(6)}");
    console.print("    ${coNormality.pValue < 0.05 ? "Not normally distributed (p < 0.05)" : "Normally distributed (p >= 0.05)"}");
    console.print("    Skewness: ${coNormality.skewness.toStringAsFixed(4)}");
    console.print("    Kurtosis: ${coNormality.kurtosis.toStringAsFixed(4)}");

    // Difference tests
    console.print("\n=== Tests for Difference ===");

    // Welch's t-test (works even if variances are unequal)
    var tTestResult = _welchTTest(openCompetitors.map((e) => e.alphaPercentage).toList(), coCompetitors.map((e) => e.alphaPercentage).toList());
    console.print("\nWelch's t-test (Two-Sample):");
    console.print("  t-statistic: ${tTestResult.tStatistic.toStringAsFixed(4)}");
    console.print("  Degrees of freedom: ${tTestResult.df.toStringAsFixed(2)}");
    console.print("  p-value: ${tTestResult.pValue.toStringAsFixed(6)}");
    console.print("  ${_interpretPValue(tTestResult.pValue)}");
    console.print("  Mean difference: ${(openCompetitors.map((e) => e.alphaPercentage).average - coCompetitors.map((e) => e.alphaPercentage).average).toStringAsFixed(4)}");

    // Mann-Whitney U test (non-parametric, doesn't require normality)
    var mwResult = _mannWhitneyUTest(openCompetitors.map((e) => e.alphaPercentage).toList(), coCompetitors.map((e) => e.alphaPercentage).toList());
    console.print("\nMann-Whitney U Test (Non-parametric):");
    console.print("  U-statistic: ${mwResult.uStatistic.toStringAsFixed(2)}");
    console.print("  p-value: ${mwResult.pValue.toStringAsFixed(6)}");
    console.print("  ${_interpretPValue(mwResult.pValue)}");

    // Effect size
    var cohensD = _cohensD(openCompetitors.map((e) => e.alphaPercentage).toList(), coCompetitors.map((e) => e.alphaPercentage).toList());
    console.print("\nEffect Size:");
    console.print("  Cohen's d: ${cohensD.toStringAsFixed(4)}");
    console.print("  ${_interpretCohensD(cohensD)}");

    // Confidence interval for mean difference
    var ci = _confidenceIntervalForMeanDifference(openCompetitors.map((e) => e.alphaPercentage).toList(), coCompetitors.map((e) => e.alphaPercentage).toList(), 0.95);
    console.print("\n95% Confidence Interval for Mean Difference:");
    console.print("  CI: [${ci.lower.toStringAsFixed(4)}, ${ci.upper.toStringAsFixed(4)}]");
    if(ci.lower > 0 || ci.upper < 0) {
      console.print("  Difference is statistically significant (CI does not contain 0)");
    }
    else {
      console.print("  Difference is not statistically significant (CI contains 0)");
    }
  }

  ({double k2Statistic, double pValue, double skewness, double kurtosis}) _testNormality(List<double> data) {
    if(data.length < 8) {
      // D'Agostino-Pearson test requires at least 8 samples
      return (k2Statistic: 0.0, pValue: 1.0, skewness: 0.0, kurtosis: 0.0);
    }

    var n = data.length;
    var mean = data.average;
    var stdDev = data.stdDev();

    if(stdDev == 0.0) {
      return (k2Statistic: 0.0, pValue: 1.0, skewness: 0.0, kurtosis: 0.0);
    }

    // Calculate skewness
    var skewness = _calculateSkewness(data, mean, stdDev);

    // Calculate kurtosis
    var kurtosis = _calculateKurtosis(data, mean, stdDev);

    // D'Agostino-Pearson K² test
    // This combines tests of skewness and kurtosis
    var z1 = _skewnessToZ(skewness, n);
    var z2 = _kurtosisToZ(kurtosis, n);

    var k2 = z1 * z1 + z2 * z2;

    // K² follows a chi-square distribution with 2 degrees of freedom
    // Using approximation: P(χ² > k²) ≈ 1 - Normal.cdf(sqrt(2*k² - 1))
    // For better accuracy, we can use the chi-square CDF approximation
    var pValue = _chiSquarePValue(k2, 2);

    return (k2Statistic: k2, pValue: pValue, skewness: skewness, kurtosis: kurtosis);
  }

  double _calculateSkewness(List<double> data, double mean, double stdDev) {
    if(stdDev == 0.0) return 0.0;

    var n = data.length;
    var sum = 0.0;
    for(var value in data) {
      var diff = (value - mean) / stdDev;
      sum += diff * diff * diff;
    }
    return sum / n;
  }

  double _calculateKurtosis(List<double> data, double mean, double stdDev) {
    if(stdDev == 0.0) return 0.0;

    var n = data.length;
    var sum = 0.0;
    for(var value in data) {
      var diff = (value - mean) / stdDev;
      sum += diff * diff * diff * diff;
    }
    // Excess kurtosis (subtract 3 to get excess kurtosis, where normal distribution has kurtosis = 3)
    return (sum / n) - 3.0;
  }

  double _skewnessToZ(double skewness, int n) {
    // Transformation for skewness to z-score (D'Agostino transformation)
    var s = skewness;
    var beta2 = (3 * (n * n + 27 * n - 70) * (n + 1) * (n + 3)) / ((n - 2) * (n + 5) * (n + 7) * (n + 9));
    var w2 = -1 + sqrt(2 * (beta2 - 1));
    var delta = 1 / sqrt(log(sqrt(w2)));
    var alpha = sqrt(2 / (w2 - 1));

    var z = delta * log(s / alpha + sqrt((s / alpha) * (s / alpha) + 1));
    return z;
  }

  double _kurtosisToZ(double kurtosis, int n) {
    // Transformation for kurtosis to z-score (simplified D'Agostino approach)
    var e = kurtosis;

    // Expected value and variance of excess kurtosis under normality
    var meanE = -6.0 / (n + 1);
    var varE = (24 * n * (n - 2) * (n - 3)) / ((n + 1) * (n + 1) * (n + 3) * (n + 5));

    if(varE <= 0) return 0.0;

    var se = sqrt(varE);

    // Standard z-score transformation
    // For better normality, we apply Anscombe transformation
    var a = 6 + (8 / se) * (2 / se + sqrt(1 + 4 / (se * se)));
    var zRaw = (e - meanE) / se;

    // Anscombe transformation for kurtosis
    var b = (1 - 2 / a) / (1 + zRaw * sqrt(2 / (a - 4)));

    if(b <= 0 || b >= 1 || a <= 4) {
      // Fallback to simple z-score if transformation fails
      return zRaw;
    }

    var z = (1 - 2 / (9 * a) - pow(b, 1 / 3)) / sqrt(2 / (9 * a));

    // Ensure we return a valid number
    if(z.isNaN || z.isInfinite) {
      return zRaw;
    }

    return z;
  }

  double _chiSquarePValue(double chiSquare, int df) {
    // Approximation for chi-square CDF
    // For df = 2, we can use: P(χ² > x) = exp(-x/2)
    if(df == 2) {
      return exp(-chiSquare / 2);
    }

    // For other df, use normal approximation: sqrt(2*χ²) - sqrt(2*df - 1) ~ N(0,1)
    if(df > 30) {
      var z = sqrt(2 * chiSquare) - sqrt(2 * df - 1);
      return 2 * (1 - Normal.cdf(z.abs()));
    }

    // For small df, use a more accurate approximation
    // P(χ² > x) ≈ 1 - Normal.cdf((x - df) / sqrt(2*df))
    var z = (chiSquare - df) / sqrt(2 * df);
    return 2 * (1 - Normal.cdf(z.abs()));
  }

  ({double tStatistic, double pValue, double df}) _welchTTest(List<double> group1, List<double> group2) {
    var n1 = group1.length;
    var n2 = group2.length;

    var mean1 = group1.average;
    var mean2 = group2.average;
    var var1 = group1.stdDev() * group1.stdDev();
    var var2 = group2.stdDev() * group2.stdDev();

    // Welch's t-test statistic
    var se = sqrt(var1 / n1 + var2 / n2);
    if(se == 0.0) {
      return (tStatistic: 0.0, pValue: 1.0, df: 0.0);
    }
    var tStatistic = (mean1 - mean2) / se;

    // Degrees of freedom (Welch-Satterthwaite equation)
    var df = pow(var1 / n1 + var2 / n2, 2) /
             (pow(var1 / n1, 2) / (n1 - 1) + pow(var2 / n2, 2) / (n2 - 1));

    // Two-tailed p-value using t-distribution
    var pValue = _twoTailedPValue(tStatistic, df);

    return (tStatistic: tStatistic, pValue: pValue, df: df);
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
    if(varU == 0.0) {
      return (uStatistic: uStatistic, pValue: 1.0);
    }
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
    if(se == 0.0) {
      return (lower: 0.0, upper: 0.0);
    }

    // Degrees of freedom (Welch-Satterthwaite)
    var df = pow(var1 / n1 + var2 / n2, 2) /
             (pow(var1 / n1, 2) / (n1 - 1) + pow(var2 / n2, 2) / (n2 - 1));

    // Critical value (using t-distribution)
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

  String _interpretPValue(double pValue) {
    if(pValue < 0.001) return "Highly significant (p < 0.001) ***";
    if(pValue < 0.01) return "Very significant (p < 0.01) **";
    if(pValue < 0.05) return "Significant (p < 0.05) *";
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
}

class _CrossoverCompetitor {
  ShooterRating openRating;
  ShooterRating coRating;

  double openAlphaPercentage;
  double openCharliePercentage;
  double get openOtherPercentage => 1 - (openAlphaPercentage + openCharliePercentage);
  double coAlphaPercentage;
  double coCharliePercentage;
  double get coOtherPercentage => 1 - (coAlphaPercentage + coCharliePercentage);

  _CrossoverCompetitor({
    required this.openRating,
    required this.coRating,
    required this.openAlphaPercentage,
    required this.openCharliePercentage,
    required this.coAlphaPercentage,
    required this.coCharliePercentage,
  });
}

class _SingleCompetitor {
  ShooterRating rating;
  double alphaPercentage;
  double charliePercentage;
  double get otherPercentage => 1 - (alphaPercentage + charliePercentage);

  _SingleCompetitor({
    required this.rating,
    required this.alphaPercentage,
    required this.charliePercentage,
  });
}