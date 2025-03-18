

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_statistics.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:community_charts_common/community_charts_common.dart' as commonCharts;
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';

class StackedDistributionDialog extends StatelessWidget {
  const StackedDistributionDialog({super.key, required this.statistics, required this.sport, required this.group, this.reverseClassifications = true, this.ignoredClassifications});

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
              sport: sport,
              group: group,
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
