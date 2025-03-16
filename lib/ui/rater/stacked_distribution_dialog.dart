

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_statistics.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:community_charts_common/community_charts_common.dart' as commonCharts;

class StackedDistributionDialog extends StatelessWidget {
  const StackedDistributionDialog({super.key, required this.statistics, required this.sport, required this.group});

  final Sport sport;
  final RatingGroup group;
  final RaterStatistics statistics;

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    return AlertDialog(
      title: Text("Distribution vs. histogram (${group.name}, ${statistics.ratingDistribution.runtimeType})"),
      content: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Column(
          children: [
            Expanded(child: StackedDistributionChart(sport: sport, group: group, statistics: statistics)),
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

// TODO: convert this so that it can handle arbitrary data
// Needs, at minimum:
// 1. A distribution
// 2. A total histogram
// 3. Optional sub-histograms with color keys
// 4. An optional color function, or possibly we can figure out how to do that off of the data
class StackedDistributionChart extends StatelessWidget {
  const StackedDistributionChart({super.key, required this.statistics, required this.sport, required this.group});

  final RaterStatistics statistics;
  final Sport sport;
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    List<_HistogramStep> histogramData = [];
    int maxCount = 0;
    int minBucket = -1 >>> 1; // max int
    int maxBucket = 0;
    int bucketCount = 0;
    for(var bucket in statistics.histogram.keys) {
      var count = statistics.histogram[bucket] ?? 0;
      var bucketStart = bucket * statistics.histogramBucketSize;
      histogramData.add(_HistogramStep(rating: bucketStart + (statistics.histogramBucketSize / 2), count: count));
      if(count > maxCount) {
        maxCount = count;
      }
      if(bucketStart < minBucket) {
        minBucket = bucketStart;
      }
      if(bucketStart > maxBucket) {
        maxBucket = bucketStart;
      }
    }
    bucketCount = (maxBucket - minBucket) ~/ statistics.histogramBucketSize + 1;

    final steps = 250;
    final rangeHigh = (maxBucket + statistics.histogramBucketSize).toDouble();
    final rangeLow = minBucket.toDouble();
    final range = rangeHigh - rangeLow;
    final stepSize = range / steps;
    List<_PdfStep> pdfData = [];

    var probMax = 0.0;
    for(var r = rangeLow; r <= rangeHigh; r += stepSize) {
      var prob = statistics.ratingDistribution.probability(r);
      pdfData.add(_PdfStep(rating: r, probability: prob));
      if(prob > probMax) {
        probMax = prob;
      }
    }

    var pdfSeries = charts.Series<_PdfStep, double>(
      id: "pdf",
      data: pdfData,
      colorFn: (data, index) => _calculateColor(data.rating) ?? charts.MaterialPalette.blue.shadeDefault,
      domainFn: (data, index) => data.rating,
      measureFn: (data, index) => data.probability,
    );

    List<charts.Series<_HistogramStep, double>> histogramSeries = [];
    for(var classification in sport.classifications.values.toList().reversed) {
      var classHist = statistics.histogramsByClass[classification]!;
      List<_HistogramStep> classHistData = [];
      for(var bucket in classHist.keys) {
        var count = classHist[bucket] ?? 0;
        var bucketStart = bucket * statistics.histogramBucketSize;
        var bucketCenter = bucketStart + (statistics.histogramBucketSize / 2);
        classHistData.add(_HistogramStep(rating: bucketStart.toDouble(), count: count));
      }
      var series = charts.Series<_HistogramStep, double>(
        colorFn: (data, index) => classification.color.toChartsColor(),
        id: classification.shortDisplayName,
        data: classHistData,
        domainFn: (data, index) => data.rating,
        measureFn: (data, index) => data.count,
      )
      ..setAttribute(charts.rendererIdKey, "histogram")
      ..setAttribute(charts.measureAxisIdKey, "secondaryMeasureAxisId");
      histogramSeries.add(series);
    }

    int minBarWidth = (MediaQuery.of(context).size.width * 0.8 / (bucketCount * 1.75)).round();

    var chart = charts.LineChart(
      [pdfSeries, ...histogramSeries],
      animate: false,
      defaultRenderer: charts.LineRendererConfig(
        strokeWidthPx: 3,
      ),
      customSeriesRenderers: [
        charts.BarRendererConfig(
          customRendererId: "histogram",
          groupingType: charts.BarGroupingType.stacked,
          barGroupInnerPaddingPx: 5,
          cornerStrategy: charts.NoCornerStrategy(),
          strokeWidthPx: 0,
          minBarWidthPx: minBarWidth,
        ),
      ],
      domainAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(statistics.minRating - 50, statistics.maxRating + 50),
      ),
      primaryMeasureAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(0, probMax + probMax * 0.1),
        tickProviderSpec: null,
      ),
      secondaryMeasureAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(0, maxCount + maxCount * 0.1),
        tickProviderSpec: charts.BasicNumericTickProviderSpec(
          dataIsInWholeNumbers: true,
          desiredMinTickCount: 8,
          desiredTickCount: 10,
        ),
      ),
    );
    return chart;
  }

  charts.Color? _calculateColor(double rating) {
    // Find the two closest classification averages to the rating
    var classifications = sport.classifications.values.whereNot((c) => c.name == "Unclassified").toList();

    var above = classifications.sorted((a,b) => b.index.compareTo(a.index)).firstWhereOrNull((c) => statistics.averageByClass[c]! > rating);
    var below = classifications.sorted((a,b) => a.index.compareTo(b.index)).firstWhereOrNull((c) => statistics.averageByClass[c]! < rating);

    if(above != null && below != null) {
      // Figure out how far between ratings we are.
      var distanceToAbove = (rating - statistics.averageByClass[above]!).abs();
      var distanceToBelow = (rating - statistics.averageByClass[below]!).abs();
      var totalDistance = distanceToAbove + distanceToBelow;

      // scale to an int between 0 (below) and 19 (above)
      var fromBelow = distanceToBelow / totalDistance;
      var fromBelowSteps = (fromBelow * 20).floor();

      // Interpolate 10 steps between the two colors
      var colorAbove = RgbColor.fromHex(above.color.toHex());
      var colorBelow = RgbColor.fromHex(below.color.toHex());
      // 18 steps, including below and above, for 20
      var steps = colorBelow.lerpTo(colorAbove, 18);
      return steps[fromBelowSteps].toChartsColor();
    }
    else if(above != null) {
      return above.color.toChartsColor();
    }
    else if(below != null) {
      return below.color.toChartsColor();
    }
    return null;
  }
}

class _PdfStep {
  final double rating;
  final double probability;

  _PdfStep({required this.rating, required this.probability});
}

class _HistogramStep {
  final double rating;
  final int count;

  _HistogramStep({required this.rating, required this.count});
}

extension FlutterColorToChartsColor on Color {
  charts.Color toChartsColor() {
    return charts.Color(r: red, g: green, b: blue);
  }
}

extension RgbColorToChartsColor on RgbColor {
  charts.Color toChartsColor() {
    return charts.Color(r: red, g: green, b: blue);
  }
}

extension ToHex on Color {
  String toHex() {
    return '#${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}';
  }
}
