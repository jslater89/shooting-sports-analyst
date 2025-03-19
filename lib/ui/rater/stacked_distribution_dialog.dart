

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/math/gamma/gamma_estimator.dart';
import 'package:shooting_sports_analyst/data/math/gaussian/gaussian_estimator.dart';
import 'package:shooting_sports_analyst/data/math/lognormal/lognormal_estimator.dart';
import 'package:shooting_sports_analyst/data/math/weibull/weibull_estimator.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_statistics.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:community_charts_common/community_charts_common.dart' as commonCharts;
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';
import 'package:shooting_sports_analyst/util.dart';

class RatingDistributionDialog extends StatelessWidget {
  const RatingDistributionDialog({
    super.key,
    required this.statistics,
    required this.sport,
    required this.group,
    this.reverseClassifications = true,
    this.ignoredClassifications,
  });

  final Sport sport;
  final RatingGroup group;
  final RaterStatistics statistics;
  final bool reverseClassifications;
  final List<Classification>? ignoredClassifications;

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    // A list of histogram buckets for each step in RatingStatistics' range, containing labeled sub-buckets
    // for colors.
    List<HistogramBucket> buckets = [];

    Map<Classification, HistogramLabel> labels = {};
    List<Classification> classifications;
    if(reverseClassifications) {
      classifications = sport.classifications.values.toList().reversed.toList();
    }
    else {
      classifications = sport.classifications.values.toList();
    }

    List<HistogramLabel> ignoredLabels = [];
    for(var (index, classification) in classifications.indexed) {
      labels[classification] = HistogramLabel(
        name: classification.shortDisplayName,
        color: classification.color,
        index: index,
      );
      if(ignoredClassifications != null && ignoredClassifications!.contains(classification)) {
        ignoredLabels.add(labels[classification]!);
      }
    }

    for(var bucket in statistics.histogram.keys) {
      var bucketStart = bucket * statistics.histogramBucketSize;
      var bucketEnd = bucketStart + statistics.histogramBucketSize;
      var bucketCenter = bucketStart + (statistics.histogramBucketSize / 2);

      List<HistogramData> bucketData = [];
      for(var classification in sport.classifications.values) {
        var count = statistics.histogramsByClass[classification]?[bucket];
        if(count != null) {
          bucketData.add(HistogramData(
            label: labels[classification]!,
            count: count,
            average: statistics.averageByClass[classification],
          ));
        }
      }
      if(bucketData.isNotEmpty) {
        buckets.add(HistogramBucket.multi(bucketStart: bucketStart.toDouble(), bucketEnd: bucketEnd.toDouble(), data: bucketData));
      }
    }

    return AlertDialog(
      title: Text("Distribution vs. histogram (${group.name}, ${statistics.ratingDistribution.runtimeType})"),
      content: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            Expanded(child: StackedDistributionChart(
              buckets: buckets,
              distribution: statistics.ratingDistribution,
              distributionIgnoresLabels: ignoredLabels,
            )),
            const SizedBox(height: 10),
            Text(
              "Log likelihood: ${statistics.fitTests.logLikelihood.round()} • "
              "Kolmogorov-Smirnov: ${statistics.fitTests.kolmogorovSmirnov.toStringAsFixed(4)} • "
              "Chi-square: ${statistics.fitTests.chiSquare.toStringAsFixed(2)} • "
              "Anderson-Darling: ${statistics.fitTests.andersonDarling.toStringAsFixed(2)}",
            ),
          ],
        ),
      )
    );
  }
}

class ScoresDistributionDialog extends StatelessWidget {
  const ScoresDistributionDialog({
    super.key,
    required this.matchScores,
    required this.sport,
    this.stage,
    this.showCdf = false,
    this.ignoredClassifications = const []
  });

  final Sport sport;
  final List<RelativeMatchScore> matchScores;
  final MatchStage? stage;
  final List<Classification> ignoredClassifications;
  final bool showCdf;
  @override
  Widget build(BuildContext context) {
    if(!sport.hasClassifications) {
      throw ArgumentError("Sport ${sport.name} has no classifications");
    }

    Map<MatchEntry, RelativeScore> scores = {};
    for(var s in matchScores) {
      RelativeScore score;
      if(stage != null) {
        score = s.stageScores[stage]!;
      }
      else {
        score = s;
      }
      if(score.percentage == 0.0 || score.isDnf || s.shooter.dq) {
        continue;
      }
      scores[s.shooter] = score;
    }

    var scoreValues = scores.values.map((e) => e.percentage).toList();
    var distribution = WeibullEstimator().estimate(scoreValues);

    // Add a buffer to the start so that > bucketStart && <= bucketEnd fits all scores.
    var bucketSize = 5;
    var minScore = (scoreValues.min - 1).round();
    var maxScore = scoreValues.max;
    var bucketCount = (maxScore - minScore) ~/ bucketSize + 1;

    Map<Classification, HistogramLabel> labels = {};
    List<HistogramLabel> ignoredLabels = [];
    for(var c in sport.classifications.values) {
      labels[c] = HistogramLabel(name: c.shortDisplayName, color: c.color, index: c.index);
      if(ignoredClassifications.contains(c)) {
        ignoredLabels.add(labels[c]!);
      }
    }

    Map<Classification, List<RelativeScore>> scoresByClass = {};
    for(var e in scores.entries) {
      var matchEntry = e.key;
      var relativeScore = e.value;
      var classification = matchEntry.classification;
      if(classification == null || relativeScore.percentage == 0.0) {
        continue;
      }
      scoresByClass.addToList(classification, relativeScore);
    }

    List<HistogramBucket> buckets = [];
    for(var i = 0; i < bucketCount; i++) {
      var bucketStart = minScore + (i * bucketSize);
      var bucketEnd = bucketStart + bucketSize;
      var bucketCenter = bucketStart + (bucketSize / 2);

      List<HistogramData> bucketData = [];
      for(var c in sport.classifications.values) {
        var count = scoresByClass[c]?.where((e) => e.percentage > bucketStart && e.percentage <= bucketEnd).length ?? 0;
        var average = scoresByClass[c]?.map((e) => e.percentage).average;
        bucketData.add(HistogramData(label: labels[c]!, count: count, average: average));
      }
      buckets.add(HistogramBucket.multi(bucketStart: bucketStart.toDouble(), bucketEnd: bucketEnd.toDouble(), data: bucketData));
    }

    var logLikelihood = distribution.logLikelihood(scoreValues);
    var kolmogorovSmirnov = distribution.kolmogorovSmirnovTest(scoreValues);
    var chiSquare = distribution.chiSquareTest(scoreValues);
    var andersonDarling = distribution.andersonDarlingTest(scoreValues);
    var size = MediaQuery.of(context).size;

    return AlertDialog(
      title: Text("Distribution vs. histogram (${distribution.runtimeType})"),
      content: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            Expanded(child: StackedDistributionChart(
              buckets: buckets,
              distribution: distribution,
              distributionIgnoresLabels: ignoredLabels,
              data: showCdf ? scoreValues : null,
            )),
            const SizedBox(height: 10),
            Text(
              "Log likelihood: ${logLikelihood.round()} • "
              "Kolmogorov-Smirnov: ${kolmogorovSmirnov.toStringAsFixed(4)} • "
              "Chi-square: ${chiSquare.toStringAsFixed(2)} • "
              "Anderson-Darling: ${andersonDarling.toStringAsFixed(2)}",
            ),
          ],
        ),
      ),
    );
  }
}
