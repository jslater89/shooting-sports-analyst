/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:data/data.dart' show ContinuousDistribution;
import 'package:flutter/material.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';
// import 'package:community_charts_common/community_charts_common.dart' as common;

/// A bucket of histogram data, containing a list of [HistogramData] values that share
/// the same bucket start and bucket end.
class HistogramBucket {
  /// The start of the bucket, in the same units as the data.
  final double bucketStart;
  /// The end of the bucket, in the same units as the data.
  final double bucketEnd;
  /// The size of the bucket, in the same units as the data.
  double get bucketSize => bucketEnd - bucketStart;
  /// The center of the bucket, in the same units as the data.
  double get bucketCenter => bucketStart + (bucketSize / 2);

  /// The total count of all data in the bucket across all sub-populations.
  int get count => data.map((d) => d.count).sum;

  /// The list of sub-populations in the bucket.
  final List<HistogramData> data;
  /// The list of labels for the sub-populations in the bucket.
  late final List<HistogramLabel> labels;

  /// Create a bucket with multiple sub-populations, expressed as [HistogramData] values in [data].
  HistogramBucket.multi({required this.bucketStart, required this.bucketEnd, required this.data}) {
    _fillInData();
  }

  /// Create a bucket with a single sub-population, expressed as a [HistogramData] value.
  HistogramBucket.single({required this.bucketStart, required this.bucketEnd, required HistogramData data}) : data = [data] {
    _fillInData();
  }

  void _fillInData() {
    if(data.isEmpty) {
      throw ArgumentError("HistogramBucket must have at least one HistogramData");
    }

    labels = [];
    for(var data in data) {
      data._bucketStart = bucketStart;
      data._bucketEnd = bucketEnd;

      labels.addIfMissing(data.label);
    }

    labels.sort((a, b) => a.index.compareTo(b.index));
  }
}

/// A single sub-population of histogram data, expressed as a [HistogramLabel] and
/// a count of observations.
///
///
class HistogramData {
  late final double _bucketStart;
  late final double _bucketEnd;
  double get _bucketSize => _bucketEnd - _bucketStart;
  double get _bucketCenter => _bucketStart + (_bucketSize / 2);
  /// The label for the sub-population.
  final HistogramLabel label;
  final int count;
  final double? average;
  Color get color => label.color;

  HistogramData({required this.label, required this.count, this.average});
}

/// A label for a sub-population of histogram data, expressed as a name and color.
/// HistogramData values that share a name will be considered to be part of the same
/// sub-population, and will share a color across buckets in the output histogram.
///
/// HistogramLabels are equal if their names are equal.
class HistogramLabel {
  /// The name of the sub-population.
  final String name;
  /// The color of the sub-population.
  final Color color;
  /// The index of the sub-population, used to sort the sub-populations. Defaults to 0.
  final int index;

  HistogramLabel({required this.name, required this.color, this.index = 0});

  @override
  bool operator ==(Object other) {
    if(other is HistogramLabel) {
      return name == other.name;
    }
    return false;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return "HistogramLabel(name: $name, index: $index)";
  }
}

/// StackedDistributionChart displays one or a pair of charts on the same graph:
/// 1. A histogram of observed values, expressed in [HistogramBucket]s.
/// 2. A distribution of expected values, expressed as a [ContinuousDistribution].
///
/// [HistogramBucket]s can contain several instances of [HistogramData] associated with
/// [HistogramLabel]s, which can be used to express sub-populations within a bucket.
/// They will be shown on the histogram with user-provided colors.
///
/// The chart will attempt to color the distribution line according to the averages of
/// the populations implied by [HistogramData] values that share a [HistogramLabel].
/// The color will be a linear blend between the colors of the two population averages
/// that lie closest above and below the value in question.
///
/// If [data] is provided, the chart will display an empirical CDF instead of the
/// histogram.
class StackedDistributionChart extends StatelessWidget {
  const StackedDistributionChart({
    super.key,
    required this.buckets,
    this.data,
    this.distribution,
    this.distributionIgnoresLabels = const [],
  });

  bool get showCdf => data != null;
  final List<double>? data;
  final List<HistogramBucket> buckets;
  final ContinuousDistribution? distribution;
  final List<HistogramLabel> distributionIgnoresLabels;

  @override
  Widget build(BuildContext context) {
    if(buckets.isEmpty) {
      return Container();
    }

    List<HistogramLabel> labels = [];
    for(var bucket in buckets) {
      labels.addAllIfMissing(bucket.labels);
    }
    labels.sort((a, b) => a.index.compareTo(b.index));

    int maxCount = 0;
    int minBucket = -1 >>> 1; // max int
    int maxBucket = 0;
    int minBucketStart = -1 >>> 1; // max int
    int maxBucketStart = 0;
    int bucketCount = 0;
    int bucketSize = -1;
    for(var bucket in buckets) {
      var count = bucket.count;
      var bucketStart = bucket.bucketStart;
      if(count > maxCount) {
        maxCount = count;
      }
      if(bucketStart < minBucket) {
        minBucket = bucketStart.round();
      }
      if(bucketStart > maxBucket) {
        maxBucket = bucketStart.round();
      }
      if(bucketStart < minBucketStart) {
        minBucketStart = bucketStart.round();
      }
      if(bucketStart > maxBucketStart) {
        maxBucketStart = bucketStart.round();
      }
      if(bucketSize == -1) {
        bucketSize = bucket.bucketSize.round();
      }
      else if(bucket.bucketSize != bucketSize) {
        throw ArgumentError("StackedDistributionChart requires uniform bucket size: ${bucket.bucketSize} != $bucketSize");
      }
    }
    bucketCount = (maxBucket - minBucket) ~/ bucketSize + 1;

    final steps = 250;
    final rangeHigh = (maxBucket + bucketSize).toDouble();
    final rangeLow = minBucket.toDouble();
    final range = rangeHigh - rangeLow;
    final stepSize = range / steps;
    List<_PdfStep> pdfData = [];
    var probMax = 0.0;

    if(distribution != null) {
      for(var r = rangeLow; r <= rangeHigh; r += stepSize) {
        double prob;
        if(showCdf) {
          prob = distribution!.cumulativeProbability(r);
        }
        else {
          prob = distribution!.probability(r);
        }
        pdfData.add(_PdfStep(value: r, probability: prob));
        if(prob > probMax) {
          probMax = prob;
        }
      }
    }

    Map<HistogramLabel, List<HistogramData>> labelData = {};
    for(var bucket in buckets) {
      for(var data in bucket.data) {
        labelData.addToList(data.label, data);
      }
    }

    Map<HistogramLabel, Color> labelColors = {};
    for(var label in labelData.keys) {
      if(distributionIgnoresLabels.contains(label)) {
        continue;
      }
      labelColors[label] = label.color;
    }

    Map<HistogramLabel, double> labelAverages = {};
    for(var label in labelData.keys) {
      if(distributionIgnoresLabels.contains(label)) {
        continue;
      }
      // labelData is a list of all HistogramData for a given label. In the original case
      // (labels are classifications, data is ratings), 'count' is the number of ratings in
      // each bucket and 'average' is the average rating in those buckets, so we can do
      // a weighted average to get the label's overall average.
      double totalWeight = 0.0;
      double totalValue = 0.0;
      for(var data in labelData[label]!) {
        totalWeight += data.count;
        totalValue += data.count * (data.average ?? 0.0);
      }

      // We should only have non-zero total weights, because we should only have labels with
      // data as keys in labelData, but just to be safe, check for it, and leave null if there
      // is no data.
      if(totalValue > 0.0) {
        labelAverages[label] = totalValue / totalWeight;
      }
    }

    List<HistogramLabel> colorLabels = labels.whereNot((element) => distributionIgnoresLabels.contains(element)).toList();
    var pdfSeries = charts.Series<_PdfStep, double>(
      id: "pdf",
      data: pdfData,
      colorFn: (data, index) => _calculateColor(value: data.value, labels: colorLabels, labelColors: labelColors, labelAverages: labelAverages) ?? charts.MaterialPalette.blue.shadeDefault,
      domainFn: (data, index) => data.value,
      measureFn: (data, index) => data.probability,
    );


    List<charts.Series<_HistogramStep, double>> histogramSeries = [];
    charts.Series<_PdfStep, double>? cdfSeries;
    if(showCdf) {
      var cdfColors = Map.fromEntries(colorLabels.map((label) {
        RgbColor c = label.color.toRgbColor();
        var faded = c.withChroma(c.chroma * 0.5);
        return MapEntry(label, faded.toFlutterColor());
      }));
      List<_PdfStep> cdfData = [];
      data!.sort();
      for(var (index, value) in data!.indexed) {
        // empirical CDF is the proportion of values less than or equal to the current value
        cdfData.add(_PdfStep(value: value, probability: index / data!.length));
      }
      cdfSeries = charts.Series<_PdfStep, double>(
        id: "cdf",
        data: cdfData,
        colorFn: (data, index) => _calculateColor(value: data.value, labels: colorLabels, labelColors: cdfColors, labelAverages: labelAverages) ?? charts.MaterialPalette.blue.shadeDefault,
        domainFn: (data, index) => data.value,
        measureFn: (data, index) => data.probability,
      );
    }
    else {
      for(var label in labels) {
        var classHist = labelData[label];
        if(classHist == null) continue;

        List<_HistogramStep> classHistData = [];
        for(var data in classHist) {
          var count = data.count;
          classHistData.add(_HistogramStep(label: data.label, bucketStart: data._bucketCenter, count: count, color: data.color));
        }
        var series = charts.Series<_HistogramStep, double>(
          colorFn: (data, index) => data.color.toChartsColor(),
          id: label.name,
          data: classHistData,
          domainFn: (data, index) => data.bucketStart,
          measureFn: (data, index) => data.count,
        )
        ..setAttribute(charts.rendererIdKey, "histogram")
        ..setAttribute(charts.measureAxisIdKey, "secondaryMeasureAxisId");
        histogramSeries.add(series);
      }
    }

    int minBarWidth = (MediaQuery.of(context).size.width * 0.8 / (bucketCount * 1.75)).round();

    var chart = charts.LineChart(
      [
        if(distribution != null) pdfSeries,
        if(showCdf) cdfSeries!,
        if(!showCdf) ...histogramSeries
      ],
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
        viewport: charts.NumericExtents(minBucketStart - (bucketSize * 0.25), maxBucketStart + (bucketSize * 1.25)),
      ),
      primaryMeasureAxis: distribution != null ? charts.NumericAxisSpec(
        viewport: charts.NumericExtents(0, probMax + probMax * 0.1),
        tickProviderSpec: null,
      ) : null,
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

  charts.Color? _calculateColor({
    required double value,
    required List<HistogramLabel> labels,
    required Map<HistogramLabel, Color> labelColors,
    required Map<HistogramLabel, double> labelAverages,
  }) {
    // Use the default color if there are no labels with average data.
    if(labelAverages.isEmpty) {
      return null;
    }

    var sortedLabels = labels.sorted((a, b) => labelAverages[a]!.compareTo(labelAverages[b]!));

    // Find the two closest classification averages to the rating
    var above = sortedLabels.firstWhereOrNull((l) => labelAverages[l]! > value);
    var below = sortedLabels.lastWhereOrNull((l) => labelAverages[l]! < value);

    if(above != null && below != null) {
      // Figure out how far between ratings we are.
      var distanceToAbove = (value - labelAverages[above]!).abs();
      var distanceToBelow = (value - labelAverages[below]!).abs();
      var totalDistance = distanceToAbove + distanceToBelow;

      // scale to an int between 0 (below) and 19 (above)
      var fromBelow = distanceToBelow / totalDistance;
      var fromBelowSteps = (fromBelow * 20).floor();

      // Interpolate 10 steps between the two colors
      var colorAbove = labelColors[above]!.toRgbColor();
      var colorBelow = labelColors[below]!.toRgbColor();
      // 18 steps, including below and above, for 20
      var steps = colorBelow.lerpTo(colorAbove, 18);
      return steps[fromBelowSteps].toChartsColor();
    }
    else if(above != null) {
      return labelColors[above]!.toChartsColor();
    }
    else if(below != null) {
      return labelColors[below]!.toChartsColor();
    }
    return null;
  }
}

class _PdfStep {
  final double value;
  final double probability;

  _PdfStep({required this.value, required this.probability});
}

class _HistogramStep {
  final HistogramLabel label;
  final double bucketStart;
  final int count;
  final Color color;

  _HistogramStep({required this.label, required this.bucketStart, required this.count, required this.color});
}

extension FlutterColorConverters on Color {
  charts.Color toChartsColor() {
    return charts.Color(r: red, g: green, b: blue);
  }

  RgbColor toRgbColor() {
    return RgbColor(red, green, blue);
  }

  String toHex() {
    return '#${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}';
  }
}

extension RgbColorConverters on RgbColor {
  charts.Color toChartsColor() {
    return charts.Color(r: red, g: green, b: blue);
  }

  Color toFlutterColor() {
    return Color.fromARGB(alpha, red, green, blue);
  }
}
