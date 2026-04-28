import 'dart:math';

import 'package:flutter/widgets.dart';

import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:community_charts_common/community_charts_common.dart' as common;
// ignore: implementation_imports
import 'package:community_charts_flutter/src/text_style.dart' as style;
// ignore: implementation_imports
import 'package:community_charts_flutter/src/text_element.dart' as element;
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/ranking/model/career_stats.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/chart/rating_accumulator.dart';
import 'package:shooting_sports_analyst/ui_util.dart';
import 'package:shooting_sports_analyst/util.dart';

final NumberFormat _nf = NumberFormat("####");

class RatingComparisonChart extends StatefulWidget {
  const RatingComparisonChart({
    super.key,
    required this.rating1,
    required this.careerStats1,
    required this.displayedStats1,
    required this.rating2,
    required this.careerStats2,
    required this.displayedStats2,
    this.onMatchIdHighlighted,
  });

  final ShooterRating rating1;
  final CareerStats careerStats1;
  final PeriodicStats displayedStats1;

  final ShooterRating rating2;
  final CareerStats careerStats2;
  final PeriodicStats displayedStats2;

  final void Function(String?)? onMatchIdHighlighted;

  @override
  State<RatingComparisonChart> createState() => _RatingComparisonChartState();
}

class _RatingComparisonChartState extends State<RatingComparisonChart> {
  double get _width {
    final size = MediaQuery.of(context).size;
    return max(600, size.width * 0.9);
  }
  double get _height {
    final size = MediaQuery.of(context).size;
    return size.height > size.width ? _width / 1.5 : _width / 3;
  }

  charts.LineChart? _chart;
  // The domain axis is a unix timestamp
  charts.Series<AccumulatedRatingEvent, int>? _series1;
  charts.Series<AccumulatedRatingEvent, int>? _series2;

  // We keep both accumulated results so that we can set identical axis ranges for both series.
  AccumulatedRatingResult? _accumulatedResult1;
  AccumulatedRatingResult? _accumulatedResult2;

  void _buildChart() {
    if(_accumulatedResult1 == null) {
      _accumulatedResult1 = accumulateRatingEvents(
        rating: widget.rating1,
        careerStats: widget.careerStats1,
        displayedStats: widget.displayedStats1,
      );
    }
    if(_accumulatedResult2 == null) {
      _accumulatedResult2 = accumulateRatingEvents(
        rating: widget.rating2,
        careerStats: widget.careerStats2,
        displayedStats: widget.displayedStats2,
      );
    }
    if(_series1 == null) {
      _series1 = _buildSeries(_accumulatedResult1!, charts.MaterialPalette.blue.shadeDefault);
    }
    if(_series2 == null) {
      _series2 = _buildSeries(_accumulatedResult2!, charts.MaterialPalette.green.shadeDefault);
    }

    if(_chart == null) {

      double measureMinimum = min(_accumulatedResult1!.minimumChartValue, _accumulatedResult2!.minimumChartValue);
      double measureMaximum = max(_accumulatedResult1!.maximumChartValue, _accumulatedResult2!.maximumChartValue);

      int domainMinimum = min(_accumulatedResult1!.rating.firstSeen.millisecondsSinceEpoch ~/ 1000, _accumulatedResult2!.rating.firstSeen.millisecondsSinceEpoch ~/ 1000);
      int domainMaximum = max(_accumulatedResult1!.rating.lastSeen.millisecondsSinceEpoch ~/ 1000, _accumulatedResult2!.rating.lastSeen.millisecondsSinceEpoch ~/ 1000);

      final domainCenter = (domainMinimum + domainMaximum) / 2;

      Set<int> years = {};
      years.addAll(_accumulatedResult1!.yearIndices.keys);
      years.addAll(_accumulatedResult2!.yearIndices.keys);
      final sortedYears = years.toList()..sort();

      List<charts.LineAnnotationSegment<Object>> yearAnnotations = [];
      for(var year in sortedYears) {

        var yearTimestamp = DateTime(year, 1, 1).millisecondsSinceEpoch ~/ 1000;

        // Draw the first year annotation at the first event
        if(yearTimestamp < domainMinimum) {
          yearTimestamp = domainMinimum;
        }

        // No need for the index/adjust flow from the shooter stats dialog because
        // we're using timestamps for the domain axis.
        yearAnnotations.add(charts.LineAnnotationSegment<Object>(
          yearTimestamp,
          charts.RangeAnnotationAxisType.domain,
          startLabel: year.toString(),
          labelDirection: charts.AnnotationLabelDirection.vertical,
          labelPosition: charts.AnnotationLabelPosition.inside,
          labelStyleSpec: charts.TextStyleSpec(color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex())),
          color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
          strokeWidthPx: 1,
        ));
      }

      _ComparisonTooltipRenderer.rating1 = widget.rating1;
      _ComparisonTooltipRenderer.rating2 = widget.rating2;
      _ComparisonTooltipRenderer.uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;

      _chart = charts.LineChart(
        [_series1!, _series2!],
        animate: false,
        behaviors: [
          charts.SelectNearest(
            eventTrigger: charts.SelectionTrigger.hover,
            selectionModelType: charts.SelectionModelType.info,
            selectionMode: common.SelectionMode.expandToDomain,
            maximumDomainDistancePx: 100,
          ),
          charts.SelectNearest(
            eventTrigger: charts.SelectionTrigger.tap,
            selectionModelType: charts.SelectionModelType.action,
            maximumDomainDistancePx: 100,
          ),
          charts.LinePointHighlighter(
            selectionModelType: charts.SelectionModelType.info,
            symbolRenderer: _ComparisonTooltipRenderer(),
          ),
          charts.RangeAnnotation([
            ...yearAnnotations,
          ]),
        ],
        selectionModels: [
          charts.SelectionModelConfig(
              type: charts.SelectionModelType.info,
              updatedListener: (model) {
                if(model.hasDatumSelection) {
                  AccumulatedRatingEvent? picked1;
                  AccumulatedRatingEvent? picked2;
                  for(var datum in model.selectedDatum) {
                    if(datum.series.id == _series1!.id) {
                      picked1 = datum.series.data[datum.index!];
                    }
                    else if(datum.series.id == _series2!.id) {
                      picked2 = datum.series.data[datum.index!];
                    }
                  }

                  if(picked1 == null && picked2 == null) {
                    widget.onMatchIdHighlighted?.call(null);
                    return;
                  }

                  String? referenceMatchId;
                  int referenceDateMillis;
                  if(picked1 != null) {
                    referenceDateMillis = picked1.date.millisecondsSinceEpoch ~/ 1000;
                    referenceMatchId = picked1.baseEvent.match.sourceIds.first;
                  }
                  else {
                    referenceDateMillis = picked2!.date.millisecondsSinceEpoch ~/ 1000;
                    referenceMatchId = picked2.baseEvent.match.sourceIds.first;
                  }

                  widget.onMatchIdHighlighted?.call(referenceMatchId);

                  _ComparisonTooltipRenderer.context = context;
                  _ComparisonTooltipRenderer.event1 = picked1;
                  _ComparisonTooltipRenderer.event2 = picked2;
                  _ComparisonTooltipRenderer.renderToLeft = referenceDateMillis > domainCenter;
                }
              },
            ),
          ],
        domainAxis: charts.NumericAxisSpec(
          viewport: charts.NumericExtents(domainMinimum, domainMaximum),
          renderSpec: charts.NoneRenderSpec(
            axisLineStyle: charts.LineStyleSpec(
              color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
              thickness: 1,
            ),
          ),
        ),
        primaryMeasureAxis: charts.NumericAxisSpec(
          viewport: charts.NumericExtents(measureMinimum, measureMaximum),
          tickProviderSpec: charts.BasicNumericTickProviderSpec(
            dataIsInWholeNumbers: true,
            desiredMinTickCount: 8,
            desiredTickCount: 10,
          ),
          tickFormatterSpec: charts.BasicNumericTickFormatterSpec.fromNumberFormat(_nf),
          renderSpec: charts.GridlineRendererSpec(
            labelStyle: charts.TextStyleSpec(
              color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
            ),
            axisLineStyle: charts.LineStyleSpec(
              color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
              thickness: 1,
            ),
            lineStyle: charts.LineStyleSpec(
              color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
              thickness: 1,
            ),
          ),
          showAxisLine: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildChart();
    return SizedBox(
      width: _width,
      height: _height,
      child: _chart!,
    );
  }

  charts.Series<AccumulatedRatingEvent, int> _buildSeries(AccumulatedRatingResult accumulatedResult, charts.Color color) {
    return charts.Series<AccumulatedRatingEvent, int>(
      id: accumulatedResult.rating.name,
      data: accumulatedResult.events,
      colorFn: (e, __) => color,
      measureFn: (AccumulatedRatingEvent e, _) {
        return chartMeasureForShooterEvent(accumulatedResult.rating, e.baseEvent);
      },
      domainFn: (e, __) => e.date.millisecondsSinceEpoch ~/ 1000,
      measureLowerBoundFn: (e, __) {
        return chartMeasureForShooterEvent(accumulatedResult.rating, e.baseEvent) - e.errorAt;
      },
      measureUpperBoundFn: (e, __) {
        return chartMeasureForShooterEvent(accumulatedResult.rating, e.baseEvent) + e.errorAt;
      },
    );
  }
}

class _ComparisonTooltipRenderer extends charts.CircleSymbolRenderer {
  static BuildContext? context;
  static double uiScaleFactor = 1.0;
  static ShooterRating? rating1;
  static ShooterRating? rating2;
  static AccumulatedRatingEvent? event1;
  static AccumulatedRatingEvent? event2;
  static bool renderToLeft = false;

  // Add this flag to prevent drawing multiple times for the same hover
  static int _lastDrawHash = 0;

  @override
  void paint(
    charts.ChartCanvas canvas,
    Rectangle<num> bounds, {
    List<int>? dashPattern,
    charts.Color? fillColor,
    charts.FillPatternType? fillPattern,
    charts.Color? strokeColor,
    double? strokeWidthPx,
  }) {
    // Draw the highlight circle for this series
    super.paint(
      canvas,
      bounds,
      dashPattern: dashPattern,
      fillColor: fillColor,
      strokeColor: strokeColor,
      strokeWidthPx: strokeWidthPx ?? 2.0,
    );

    if (event1 == null && event2 == null) return;
    if (context == null) return;

    // Create a simple hash to detect if we already drew the tooltip for this selection
    final currentHash = Object.hash(event1?.date, event2?.date);
    if (currentHash == _lastDrawHash) {
      return; // Already drew tooltip for this exact selection
    }
    _lastDrawHash = currentHash;

    // Build tooltip text (same as before, but cleaner)
    final rating1Value = event1 != null
        ? chartMeasureForShooterEvent(rating1!, event1!.baseEvent)
        : null;

    final rating2Value = event2 != null
        ? chartMeasureForShooterEvent(rating2!, event2!.baseEvent)
        : null;

    final lines = <String>[];

    final date = event1?.date ?? event2?.date;
    if (date != null) {
      lines.add(DateFormat.yMMMd().format(date));
    }

    String? rating1Line;
    String? rating2Line;
    if (rating1Value != null) {
      rating1Line = "${rating1!.name}: ${rating1Value.toStringWithSignificantDigits(4)}±${event1!.errorAt.toStringWithSignificantDigits(3)}";
    }
    if (rating2Value != null) {
      rating2Line = "${rating2!.name}: ${rating2Value.toStringWithSignificantDigits(4)}±${event2!.errorAt.toStringWithSignificantDigits(3)}";
    }

    if(rating1Value != null && rating2Value != null) {
      if(rating1Value > rating2Value) {
        lines.add(rating1Line!);
        lines.add(rating2Line!);
      }
      else {
        lines.add(rating2Line!);
        lines.add(rating1Line!);
      }
    }
    else {
      if(rating1Value != null) {
        lines.add(rating1Line!);
      }
      else if(rating2Value != null) {
        lines.add(rating2Line!);
      }
    }

    final tooltipText = lines.join('\n');
    if (tooltipText.isEmpty) return;

    final textStyle = style.TextStyle()
      ..color = charts.Color.fromHex(code: ThemeColors.onBackgroundColor(context!).toHex())
      ..fontSize = (13 * uiScaleFactor).round();

    final textElement = element.TextElement(tooltipText, style: textStyle);
    final textMeasurement = textElement.measurement;

    // Positioning
    final offsetX = renderToLeft ? -textMeasurement.horizontalSliceWidth - 25 * uiScaleFactor : 18 * uiScaleFactor;
    final offsetY = -textMeasurement.verticalSliceWidth - 45 * uiScaleFactor;

    final tx = (bounds.left + offsetX).round();
    final ty = (bounds.top + offsetY).round();

    // Background box
    final padding = 10 * uiScaleFactor;
    final bgRect = Rectangle<num>(
      tx - padding,
      ty - padding,
      textMeasurement.horizontalSliceWidth + padding * 2.25,
      textMeasurement.verticalSliceWidth + padding * 2.25,
    );

    canvas.drawRRect(
      bgRect,
      fill: charts.Color.fromHex(code: ThemeColors.backgroundColor(context!).toHex()),
      stroke: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context!).toHex()),
      radius: 8 * uiScaleFactor,
      roundTopLeft: true,
      roundTopRight: true,
      roundBottomLeft: true,
      roundBottomRight: true,
      strokeWidthPx: 2,
    );

    // Draw text
    canvas.drawText(textElement, tx, ty);
  }
}