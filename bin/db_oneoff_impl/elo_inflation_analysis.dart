import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:dart_numerics/dart_numerics.dart' as LinearRegression;
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class EloInflationAnalysisCommand extends DbOneoffCommand {
  EloInflationAnalysisCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "EIA";
  @override
  final String title = "Elo Inflation Analysis";

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var project = await db.getRatingProjectByName("L2s Main");

    if(project == null) {
      console.print("Project not found");
      return;
    }

    /// Two tests per group:
    /// 1. Going back to 2020, what are the average/median/stddev of the ratings at the end of each year?
    /// 2. What is the correlation between individual shooter ratings and their history length?
    for(var group in project.dbGroups) {
      console.print("Processing group ${group.name}");
      var ratings = await project.getRatings(group);
      if(ratings.isErr()) {
        console.print("Error getting ratings for group ${group.name}: ${ratings.unwrapErr()}");
        continue;
      }

      var ratingsList = ratings.unwrap();
      if(ratingsList.isEmpty) {
        console.print("No ratings found");
        continue;
      }

      var endOfYearRatings = Map<int, List<double>>();
      var historiesToRatings = Map<int, List<double>>();
      for(var rating in ratingsList) {
        if(rating.length == 0) {
          continue;
        }
        DbRatingEvent lastEvent = rating.events.first;
        for(var event in rating.events) {
          if(event.date.year != lastEvent.date.year) {
            endOfYearRatings.addToList(lastEvent.date.year, lastEvent.newRating);
          }
          lastEvent = event;
        }
        historiesToRatings.addToList(rating.length, rating.rating);
      }

      var annualStats = Map<int, _Stats>();
      var sortedYears = endOfYearRatings.keys.sorted((a, b) => a.compareTo(b));
      for(var year in sortedYears) {
        var ratings = endOfYearRatings[year]!;
        annualStats[year] = _Stats(
          average: ratings.average,
          median: ratings.median,
          stddev: ratings.stdDev(),
        );
        console.print("Annual stats for $year: ${annualStats[year]}");
      }

      var historyLengthStats = Map<int, _Stats>();
      var sortedHistoryLengths = historiesToRatings.keys.sorted((a, b) => a.compareTo(b));
      for(var historyLength in sortedHistoryLengths) {
        var ratings = historiesToRatings[historyLength]!;
        historyLengthStats[historyLength] = _Stats(
          average: ratings.average,
          median: ratings.median,
          stddev: ratings.stdDev(),
        );
      }

      var history25thPercentile = sortedHistoryLengths[sortedHistoryLengths.length ~/ 4];
      var historyMedian = sortedHistoryLengths[sortedHistoryLengths.length ~/ 2];
      var history75thPercentile = sortedHistoryLengths[sortedHistoryLengths.length * 3 ~/ 4];

      console.print("History length 25th percentile ($history25thPercentile): ${historyLengthStats[history25thPercentile]}");
      console.print("History length median ($historyMedian): ${historyLengthStats[historyMedian]}");
      console.print("History length 75th percentile ($history75thPercentile): ${historyLengthStats[history75thPercentile]}");

      var yearX = annualStats.keys.map((e) => e.toDouble()).toList();
      var yearAverageY = annualStats.values.map((e) => e.average).toList();
      var yearMedianY = annualStats.values.map((e) => e.median).toList();
      var historyLengthX = historyLengthStats.keys.map((e) => e.toDouble()).toList();
      var historyLengthAverageY = historyLengthStats.values.map((e) => e.average).toList();
      var historyLengthMedianY = historyLengthStats.values.map((e) => e.median).toList();

      // Calculate linear regressions and R^2 values for year vs. average rating, year vs. median rating, and history length vs. average rating.
      var yearVsAverageRegressionTuple = LinearRegression.fit(yearX, yearAverageY);
      var yearVsMedianRegressionTuple = LinearRegression.fit(yearX, yearMedianY);
      var historyLengthVsAverageRegressionTuple = LinearRegression.fit(historyLengthX, historyLengthAverageY);
      var historyLengthVsMedianRegressionTuple = LinearRegression.fit(historyLengthX, historyLengthMedianY);

      var yearVsAverageSlope = yearVsAverageRegressionTuple.item2;
      var yearVsMedianSlope = yearVsMedianRegressionTuple.item2;
      var historyLengthVsAverageSlope = historyLengthVsAverageRegressionTuple.item2;
      var historyLengthVsMedianSlope = historyLengthVsMedianRegressionTuple.item2;

      var yearVsAverageIntercept = yearVsAverageRegressionTuple.item1;
      var yearVsMedianIntercept = yearVsMedianRegressionTuple.item1;
      var historyLengthVsAverageIntercept = historyLengthVsAverageRegressionTuple.item1;
      var historyLengthVsMedianIntercept = historyLengthVsMedianRegressionTuple.item1;

      var yearVsAverageR2 = _calculateR2(yearVsAverageSlope, yearVsAverageIntercept, yearX, yearAverageY);
      var yearVsMedianR2 = _calculateR2(yearVsMedianSlope, yearVsMedianIntercept, yearX, yearMedianY);
      var historyLengthVsAverageR2 = _calculateR2(historyLengthVsAverageSlope, historyLengthVsAverageIntercept, historyLengthX, historyLengthAverageY);
      var historyLengthVsMedianR2 = _calculateR2(historyLengthVsMedianSlope, historyLengthVsMedianIntercept, historyLengthX, historyLengthMedianY);

      console.print("Year vs. average rating regression: ${yearVsAverageSlope.toStringAsPrecision(3)} * year + ${yearVsAverageIntercept.toStringAsPrecision(3)}, R^2: ${yearVsAverageR2.toStringAsPrecision(3)}");
      console.print("Year vs. median rating regression: ${yearVsMedianSlope.toStringAsPrecision(3)} * year + ${yearVsMedianIntercept.toStringAsPrecision(3)}, R^2: ${yearVsMedianR2.toStringAsPrecision(3)}");
      console.print("History length vs. average rating regression: ${historyLengthVsAverageSlope.toStringAsPrecision(3)} * historyLength + ${historyLengthVsAverageIntercept.toStringAsPrecision(3)}, R^2: ${historyLengthVsAverageR2.toStringAsPrecision(3)}");
      console.print("History length vs. median rating regression: ${historyLengthVsMedianSlope.toStringAsPrecision(3)} * historyLength + ${historyLengthVsMedianIntercept.toStringAsPrecision(3)}, R^2: ${historyLengthVsMedianR2.toStringAsPrecision(3)}");
    }
  }

  double _calculateR2(double slope, double intercept, List<double> x, List<double> y) {
    var totalErrorSquared = 0.0;
    var totalYSquared = 0.0;
    for(var i = 0; i < x.length; i++) {
      var predicted = slope * x[i] + intercept;
      var actual = y[i];
      var error = actual - predicted;
      var errorSquared = error * error;
      totalErrorSquared += errorSquared;
      var ySquared = actual * actual;
      totalYSquared += ySquared;
    }
    var r2 = 1 - (totalErrorSquared / totalYSquared);
    return r2;
  }
}

class _Stats {
  double average;
  double median;
  double stddev;

  _Stats({
    required this.average,
    required this.median,
    required this.stddev,
  });

  @override
  String toString() {
    return "Average: ${average.round()}, Median: ${median.round()}, Stddev: ${stddev.toStringAsFixed(2)}";
  }
}
