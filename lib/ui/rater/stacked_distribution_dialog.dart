

import 'package:collection/collection.dart';
import 'package:data/data.dart' show ContinuousDistribution;
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/math/gamma/gamma_estimator.dart';
import 'package:shooting_sports_analyst/data/math/weibull/weibull_estimator.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_statistics.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';
import 'package:shooting_sports_analyst/util.dart';

class RatingDistributionDialog extends StatefulWidget {
  const RatingDistributionDialog({
    super.key,
    required this.statistics,
    required this.sport,
    required this.group,
    this.reverseClassifications = true,
    this.ignoredClassifications,
    this.showCdf = false,
  });

  final Sport sport;
  final RatingGroup group;
  final RaterStatistics statistics;
  final bool reverseClassifications;
  final List<Classification>? ignoredClassifications;
  final bool showCdf;
  @override
  State<RatingDistributionDialog> createState() => _RatingDistributionDialogState();
}

class _RatingDistributionDialogState extends State<RatingDistributionDialog> {
  late bool showingCdf;
  late ContinuousDistributionEstimator estimator;
  late ContinuousDistribution distribution;
  late List<double> ratingValues;
  late double minRating;
  late double maxRating;

  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    showingCdf = widget.showCdf;
    estimator = widget.statistics.ratingDistribution.estimator;
    distribution = widget.statistics.ratingDistribution;
    ratingValues = widget.statistics.allRatings.toList();
    minRating = ratingValues.min;
    maxRating = ratingValues.max;
    controller = TextEditingController(text: AvailableEstimator.fromEstimator(estimator).uiLabel);
  }

  void changeDistribution(ContinuousDistributionEstimator estimator) {
    distribution = estimator.estimate(ratingValues);
    setState(() {
      estimator = estimator;
    });
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    // A list of histogram buckets for each step in RatingStatistics' range, containing labeled sub-buckets
    // for colors.
    List<HistogramBucket> buckets = [];

    Map<Classification, HistogramLabel> labels = {};
    List<Classification> classifications;
    if(widget.reverseClassifications) {
      classifications = widget.sport.classifications.values.toList().reversed.toList();
    }
    else {
      classifications = widget.sport.classifications.values.toList();
    }

    List<HistogramLabel> ignoredLabels = [];
    for(var (index, classification) in classifications.indexed) {
      labels[classification] = HistogramLabel(
        name: classification.shortDisplayName,
        color: classification.color,
        index: index,
      );
      if(widget.ignoredClassifications != null && widget.ignoredClassifications!.contains(classification)) {
        ignoredLabels.add(labels[classification]!);
      }
    }

    for(var bucket in widget.statistics.histogram.keys) {
      var bucketStart = bucket * widget.statistics.histogramBucketSize;
      var bucketEnd = bucketStart + widget.statistics.histogramBucketSize;
      var bucketCenter = bucketStart + (widget.statistics.histogramBucketSize / 2);

      List<HistogramData> bucketData = [];
      for(var classification in widget.sport.classifications.values) {
        var count = widget.statistics.histogramsByClass[classification]?[bucket];
        if(count != null) {
          bucketData.add(HistogramData(
            label: labels[classification]!,
            count: count,
            average: widget.statistics.averageByClass[classification],
          ));
        }
      }
      if(bucketData.isNotEmpty) {
        buckets.add(HistogramBucket.multi(bucketStart: bucketStart.toDouble(), bucketEnd: bucketEnd.toDouble(), data: bucketData));
      }
    }

    return AlertDialog(
      title: Text("Distribution vs. histogram (${widget.group.name}, ${widget.statistics.ratingDistribution.runtimeType})"),
      content: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DistributionSelector(onSelected: changeDistribution, initialSelection: AvailableEstimator.fromEstimator(estimator)),
                const SizedBox(width: 16),
                TextButton(
                  child: Text(showingCdf ? "HISTOGRAM" : "CDF"),
                  onPressed: () {
                    setState(() {
                      showingCdf = !showingCdf;
                    });
                  },
                )
              ],
            ),
            Expanded(child: StackedDistributionChart(
              buckets: buckets,
              distribution: distribution,
              distributionIgnoresLabels: ignoredLabels,
              data: showingCdf ? ratingValues : null,
            )),
            const SizedBox(height: 10),
            Text(distribution.parameterString),
            const SizedBox(height: 8),
            Text(
              "Log likelihood: ${widget.statistics.fitTests.logLikelihood.round()} • "
              "Kolmogorov-Smirnov: ${widget.statistics.fitTests.kolmogorovSmirnov.toStringAsFixed(4)} • "
              "Chi-square: ${widget.statistics.fitTests.chiSquare.toStringAsFixed(2)} • "
              "Anderson-Darling: ${widget.statistics.fitTests.andersonDarling.toStringAsFixed(2)}",
            ),
          ],
        ),
      )
    );
  }
}

class ScoresDistributionDialog extends StatefulWidget {
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
  State<ScoresDistributionDialog> createState() => _ScoresDistributionDialogState();
}

class _ScoresDistributionDialogState extends State<ScoresDistributionDialog> {
  late bool showingCdf;
  late ContinuousDistributionEstimator estimator;
  late ContinuousDistribution distribution;
  late List<double> scoreValues;
  late double minScore;
  late double maxScore;

  @override
  void initState() {
    super.initState();
    showingCdf = widget.showCdf;
    estimator = WeibullEstimator();
    scoreValues = widget.matchScores.map((e) => e.percentage).where((e) => e > 0).toList();
    distribution = estimator.estimate(scoreValues);
    minScore = scoreValues.min;
    maxScore = scoreValues.max;
  }

  void changeDistribution(ContinuousDistributionEstimator estimator) {
    distribution = estimator.estimate(scoreValues);
    setState(() {
      estimator = estimator;
    });
  }

  @override
  Widget build(BuildContext context) {
    if(!widget.sport.hasClassifications) {
      throw ArgumentError("Sport ${widget.sport.name} has no classifications");
    }

    Map<MatchEntry, RelativeScore> scores = {};
    for(var s in widget.matchScores) {
      RelativeScore score;
      if(widget.stage != null) {
        score = s.stageScores[widget.stage]!;
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

    // Add a buffer to the start so that > bucketStart && <= bucketEnd fits all scores.
    var bucketSize = 5;
    var bucketCount = (maxScore - minScore) ~/ bucketSize + 1;

    Map<Classification, HistogramLabel> labels = {};
    List<HistogramLabel> ignoredLabels = [];
    for(var c in widget.sport.classifications.values) {
      labels[c] = HistogramLabel(name: c.shortDisplayName, color: c.color, index: c.index);
      if(widget.ignoredClassifications.contains(c)) {
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
      for(var c in widget.sport.classifications.values) {
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
            Row(
              children: [
                DistributionSelector(onSelected: changeDistribution, initialSelection: AvailableEstimator.fromEstimator(estimator)),
                const SizedBox(width: 16),
                TextButton(
                  child: Text(showingCdf ? "HISTOGRAM" : "CDF"),
                  onPressed: () {
                    setState(() {
                      showingCdf = !showingCdf;
                    });
                  },
                )
              ],
            ),
            Expanded(child: StackedDistributionChart(
              buckets: buckets,
              distribution: distribution,
              distributionIgnoresLabels: ignoredLabels,
              data: showingCdf ? scoreValues : null,
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

class DistributionSelector extends StatefulWidget {
  const DistributionSelector({super.key, required this.onSelected, this.initialSelection});

  final void Function(ContinuousDistributionEstimator estimator) onSelected;
  final AvailableEstimator? initialSelection;

  @override
  State<DistributionSelector> createState() => _DistributionSelectorState();
}

class _DistributionSelectorState extends State<DistributionSelector> {
  late AvailableEstimator selectedEstimator;
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    selectedEstimator = widget.initialSelection ?? AvailableEstimator.values.first;
    controller = TextEditingController(text: selectedEstimator.uiLabel);
  }

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<AvailableEstimator>(
      controller: controller,
      dropdownMenuEntries: AvailableEstimator.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
      onSelected: (value) {
        widget.onSelected(value!.estimator);
        setState(() {
          selectedEstimator = value;
        });
      },
    );
  }
}
