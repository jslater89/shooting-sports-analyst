/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';

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
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/chart/rating_accumulator.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

final NumberFormat _nf = NumberFormat("####");

final List<charts.Color> _comparisonSeriesColors = [
  charts.MaterialPalette.blue.shadeDefault,
  charts.MaterialPalette.green.shadeDefault,
  charts.MaterialPalette.deepOrange.shadeDefault,
];

class RatingComparisonChart extends StatefulWidget {
  const RatingComparisonChart({
    super.key,
    required this.ratings,
    required this.careerStats,
    required this.displayedStats,
    this.onMatchIdHighlighted,
  });

  final List<ShooterRating> ratings;
  final List<CareerStats> careerStats;
  final List<PeriodicStats> displayedStats;

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
  List<charts.Series<AccumulatedRatingEvent, int>?> _series = [];
  List<AccumulatedRatingResult?> _accumulatedResults = [];
  int _builtForCount = 0;

  void _ensureCapacity(int count) {
    if(_series.length != count || _builtForCount != count) {
      _series = List.filled(count, null);
      _accumulatedResults = List.filled(count, null);
      _chart = null;
      _builtForCount = count;
    }
  }

  void _buildChart(BuildContext context) {
    final count = widget.ratings.length;
    _ensureCapacity(count);

    final showErrorBands = true; //count <= 2;

    for(int i = 0; i < count; i++) {
      if(_accumulatedResults[i] == null) {
        _accumulatedResults[i] = accumulateRatingEvents(
          rating: widget.ratings[i],
          careerStats: widget.careerStats[i],
          displayedStats: widget.displayedStats[i],
        );
      }
      if(_series[i] == null) {
        _series[i] = _buildSeries(
          _accumulatedResults[i]!,
          widget.ratings[i],
          _comparisonSeriesColors[i % _comparisonSeriesColors.length],
          showErrorBands: showErrorBands,
        );
      }
    }

    if(_chart == null) {
      double measureMinimum = _accumulatedResults.map((r) => r!.minimumChartValue).reduce(min);
      double measureMaximum = _accumulatedResults.map((r) => r!.maximumChartValue).reduce(max);

      int domainMinimum = _accumulatedResults
        .map((r) => r!.rating.firstSeen.millisecondsSinceEpoch ~/ 1000)
        .reduce(min);
      int domainMaximum = _accumulatedResults
        .map((r) => r!.rating.lastSeen.millisecondsSinceEpoch ~/ 1000)
        .reduce(max);

      final domainCenter = (domainMinimum + domainMaximum) / 2;

      Set<int> years = {};
      for(var result in _accumulatedResults) {
        years.addAll(result!.yearIndices.keys);
      }
      final sortedYears = years.toList()..sort();

      List<charts.LineAnnotationSegment<Object>> yearAnnotations = [];
      for(var year in sortedYears) {
        var yearTimestamp = DateTime(year, 1, 1).millisecondsSinceEpoch ~/ 1000;

        if(yearTimestamp < domainMinimum) {
          yearTimestamp = domainMinimum;
        }

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

      final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
      _ComparisonTooltipRenderer.ratings = [...widget.ratings];
      _ComparisonTooltipRenderer.uiScaleFactor = uiScaleFactor;

      final seriesList = _series.map((s) => s!).toList();

      _chart = charts.LineChart(
        seriesList,
        animate: false,
        behaviors: [
          charts.SeriesLegend(
            position: charts.BehaviorPosition.top,
            outsideJustification: charts.OutsideJustification.middleDrawArea,
            horizontalFirst: true,
            desiredMaxColumns: count,
            cellPadding: EdgeInsets.only(
              right: 12 * uiScaleFactor,
              bottom: 4 * uiScaleFactor,
            ),
            entryTextStyle: charts.TextStyleSpec(
              color: charts.Color.fromHex(code: ThemeColors.onBackgroundColor(context).toHex()),
              fontSize: (13 * uiScaleFactor).round(),
            ),
          ),
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
                  final picked = List<AccumulatedRatingEvent?>.filled(count, null);
                  for(var datum in model.selectedDatum) {
                    for(int i = 0; i < count; i++) {
                      if(datum.series.id == _series[i]!.id) {
                        picked[i] = datum.series.data[datum.index!];
                      }
                    }
                  }

                  if(picked.every((e) => e == null)) {
                    widget.onMatchIdHighlighted?.call(null);
                    return;
                  }

                  AccumulatedRatingEvent? reference;
                  for(var e in picked) {
                    if(e != null) {
                      reference = e;
                      break;
                    }
                  }

                  widget.onMatchIdHighlighted?.call(reference!.baseEvent.match.sourceIds.first);

                  _ComparisonTooltipRenderer.context = context;
                  _ComparisonTooltipRenderer.events = picked;
                  _ComparisonTooltipRenderer.renderToLeft =
                    (reference!.date.millisecondsSinceEpoch ~/ 1000) > domainCenter;
                }
              },
            ),
            charts.SelectionModelConfig(
              type: charts.SelectionModelType.action,
              updatedListener: (model) {
                if(model.hasDatumSelection) {
                  AccumulatedRatingEvent? referenceEvent;
                  for(var datum in model.selectedDatum) {
                    for(int i = 0; i < count; i++) {
                      if(datum.series.id == _series[i]!.id) {
                        referenceEvent = datum.series.data[datum.index!];
                        break;
                      }
                    }
                    if(referenceEvent != null) break;
                  }

                  if(referenceEvent == null) return;

                  _launchScoreView(
                    context,
                    referenceEvent.baseEvent.entry.division,
                    referenceEvent.baseEvent.match,
                    stage: referenceEvent.baseEvent.stage,
                  );
                }
              },
            )
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
  void didUpdateWidget(covariant RatingComparisonChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final competitorsChanged = oldWidget.ratings.length != widget.ratings.length
      || !_sameCompetitors(oldWidget.ratings, widget.ratings);
    if(competitorsChanged) {
      // Competitor list changed — rebuild chart from scratch.
      _series = [];
      _accumulatedResults = [];
      _chart = null;
      _builtForCount = 0;
    }
  }

  bool _sameCompetitors(List<ShooterRating> a, List<ShooterRating> b) {
    if(a.length != b.length) return false;
    for(int i = 0; i < a.length; i++) {
      if(a[i].wrappedRating.id != b[i].wrappedRating.id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    _buildChart(context);
    return SizedBox(
      width: _width,
      height: _height,
      child: _chart!,
    );
  }

  charts.Series<AccumulatedRatingEvent, int> _buildSeries(
    AccumulatedRatingResult accumulatedResult,
    ShooterRating rating,
    charts.Color color, {
    required bool showErrorBands,
  }) {
    return charts.Series<AccumulatedRatingEvent, int>(
      id: accumulatedResult.rating.name,
      data: accumulatedResult.events,
      colorFn: (e, __) => color,
      measureFn: (AccumulatedRatingEvent e, _) {
        return rating.scaleRating(e.baseEvent.newRating);
      },
      domainFn: (e, __) => e.date.millisecondsSinceEpoch ~/ 1000,
      measureLowerBoundFn: showErrorBands ? (e, __) {
        return rating.scaleRating(e.baseEvent.newRating - e.errorAt);
      } : null,
      measureUpperBoundFn: showErrorBands ? (e, __) {
        return rating.scaleRating(e.baseEvent.newRating + e.errorAt);
      } : null,
    );
  }

  void _launchScoreView(BuildContext context, Division? division, ShootingMatch match, {MatchStage? stage}) {
    var filters = FilterSet(match.sport, empty: true)
      ..mode = FilterMode.or;
    if(division != null) {
      filters.divisions = FilterSet.divisionListToMap(match.sport, [division]);
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return ResultPage(
        canonicalMatch: match,
        initialStage: stage,
        initialFilters: filters,
        allowWhatIf: true,
      );
    }));
  }
}

class _ComparisonTooltipRenderer extends charts.CircleSymbolRenderer {
  static BuildContext? context;
  static double uiScaleFactor = 1.0;
  static List<ShooterRating> ratings = [];
  static List<AccumulatedRatingEvent?> events = [];
  static bool renderToLeft = false;

  static bool _drawnThisFrame = false;
  static bool _resetScheduled = false;

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
    super.paint(
      canvas,
      bounds,
      dashPattern: dashPattern,
      fillColor: fillColor,
      strokeColor: strokeColor,
      strokeWidthPx: strokeWidthPx ?? 2.0,
    );

    if(events.every((e) => e == null)) return;
    if(context == null) return;

    // LinePointHighlighter paints once per series. Draw the tooltip on the
    // first call and skip the rest of this frame so boxes don't stack.
    if(_drawnThisFrame) {
      return;
    }
    _drawnThisFrame = true;
    if(!_resetScheduled) {
      _resetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _drawnThisFrame = false;
        _resetScheduled = false;
      });
    }

    final lines = <String>[];

    DateTime? date;
    for(var e in events) {
      if(e != null) {
        date = e.date;
        break;
      }
    }
    if(date != null) {
      lines.add(DateFormat.yMMMd().format(date));
    }

    // Collect (ratingValue, line) pairs and sort by rating descending.
    final ratingLines = <(double, String)>[];
    for(int i = 0; i < ratings.length && i < events.length; i++) {
      final event = events[i];
      if(event == null) continue;
      final rating = ratings[i];
      final value = event.baseEvent.newRating;
      final line = "${rating.name}: ${rating.formatNumericRating(value)}±${rating.formatNumericRatingChange(event.errorAt)}";
      ratingLines.add((value, line));
    }
    ratingLines.sort((a, b) => b.$1.compareTo(a.$1));
    for(var entry in ratingLines) {
      lines.add(entry.$2);
    }

    final tooltipText = lines.join('\n');
    if(tooltipText.isEmpty) return;

    final textStyle = style.TextStyle()
      ..color = charts.Color.fromHex(code: ThemeColors.onBackgroundColor(context!).toHex())
      ..fontSize = (13 * uiScaleFactor).round();

    final textElement = element.TextElement(tooltipText, style: textStyle);
    final textMeasurement = textElement.measurement;

    final offsetX = renderToLeft ? -textMeasurement.horizontalSliceWidth - 25 * uiScaleFactor : 18 * uiScaleFactor;
    final offsetY = -textMeasurement.verticalSliceWidth - 45 * uiScaleFactor;

    final tx = (bounds.left + offsetX).round();
    final ty = (bounds.top + offsetY).round();

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

    canvas.drawText(textElement, tx, ty);
  }
}
