import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:charts_flutter/src/text_style.dart' as style;
import 'package:charts_flutter/src/text_element.dart' as element;
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

/// ShooterRatingChangeDialog displays per-stage changes for a shooter.
class ShooterStatsDialog extends StatefulWidget {
  const ShooterStatsDialog({Key? key, required this.rating, required this.match}) : super(key: key);

  final ShooterRating rating;
  final PracticalMatch match;

  @override
  State<ShooterStatsDialog> createState() => _ShooterStatsDialogState();
}

class _ShooterStatsDialogState extends State<ShooterStatsDialog> {
  final ScrollController _controller = ScrollController();

  RatingEvent? _highlighted;

  @override
  Widget build(BuildContext context) {
    List<RatingEvent> events = widget.rating.ratingEvents;
    // if(rating.ratingEvents.length < 30) {
    //   events = rating.ratingEvents;
    // }
    // else {
    //   events = rating.ratingEvents.sublist(rating.ratingEvents.length - 30);
    // }

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              child: Text("Ratings for ${widget.rating.shooter.getName(suffixes: false)} (${widget.rating.lastClassification.name})"),
              onTap: () {
                HtmlOr.openLink("https://uspsa.org/classification/${widget.rating.shooter.originalMemberNumber}");
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
          )
        ],
      ),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            child: _buildChart(widget.rating),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    // mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._buildShooterStats(context),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Scrollbar(
                    controller: _controller,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _controller,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...events.reversed.map((e) =>
                              Tooltip(
                                message: e.info.keys.map((line) => sprintf(line, e.info[line])).join("\n"),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        key: GlobalObjectKey(e.hashCode),
                                        color: e == _highlighted ? Colors.black12 : null,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              flex: 10,
                                              child: Text("${e.eventName}", style: Theme.of(context).textTheme.bodyText2!.copyWith(color: e.ratingChange < 0 ? Theme.of(context).errorColor : null)),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Align(
                                                  alignment: Alignment.centerRight,
                                                  child: Text("${e.ratingChange.toStringAsFixed(2)}", style: Theme.of(context).textTheme.bodyText2!.copyWith(color: e.ratingChange < 0 ? Theme.of(context).errorColor : null))
                                              ),
                                            )
                                          ],
                                        ),
                                      ),
                                      Divider(
                                        height: 2,
                                        thickness: 1,
                                      )
                                    ],
                                  ),
                                ),
                              )
                          ).toList()
                        ],
                      ),
                    ),
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TODO: let raters build their own series, optionally?
  // Mostly for points rater, which doesn't do charts well
  // Doesn't do recreating well
  charts.Series<_AccumulatedRatingEvent, int>? _series;
  charts.LineChart? _chart;
  late NumberFormat _nf;
  late List<_AccumulatedRatingEvent> _ratings;

  Widget _buildChart(ShooterRating rating) {
    double accumulator = 0;
    double minRating = 10000;
    double maxRating = -10000;
    double minWithError = 10000;
    double maxWithError = -10000;

    var size = MediaQuery.of(context).size;

    if(_series == null) {
      _ratings = rating.ratingEvents.mapIndexed((i, e) {
        if(e.newRating < minRating) minRating = e.newRating;
        if(e.newRating > maxRating) maxRating = e.newRating;

        double error = 0;
        if(rating is EloShooterRating) {
          error = rating.standardErrorWithOffset(offset: rating.ratingEvents.length - (i + 1));

          // print("Comparison: ${error.toStringAsFixed(2)} vs ${e2.toStringAsFixed(2)}");
        }

        var plusError = e.newRating + error;
        var minusError = e.newRating - error;
        if(plusError > maxWithError) maxWithError = plusError;
        if(minusError < minWithError) minWithError = minusError;

        return _AccumulatedRatingEvent(e, accumulator += e.ratingChange, error);
      }).toList();
      
      _nf = NumberFormat("####");
      _series = charts.Series<_AccumulatedRatingEvent, int>(
        id: 'Results',
        colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
        measureFn: (_AccumulatedRatingEvent e, _) => e.baseEvent.newRating,
        domainFn: (_, int? index) => index!,
        measureLowerBoundFn: (e, i) {
          if(rating is EloShooterRating) {
            return e.baseEvent.newRating - e.errorAt;
          }
          return null;
        },
        measureUpperBoundFn: (e, i) {
          if(rating is EloShooterRating) {
            return e.baseEvent.newRating + e.errorAt;
          }
          return null;
        },
        data: _ratings,
      );
    }

    if(_chart == null) {
      _chart = charts.LineChart(
        [_series!],
        animate: false,
        behaviors: [
          charts.SelectNearest(
            eventTrigger: charts.SelectionTrigger.hover,
            selectionModelType: charts.SelectionModelType.info,
            maximumDomainDistancePx: 100,
          ),
          charts.SelectNearest(
            eventTrigger: charts.SelectionTrigger.tap,
            selectionModelType: charts.SelectionModelType.action,
            maximumDomainDistancePx: 100,
          ),
          charts.LinePointHighlighter(
            selectionModelType: charts.SelectionModelType.info,
            symbolRenderer: _EloTooltipRenderer(),
          ),
        ],
        selectionModels: [
          charts.SelectionModelConfig(
            type: charts.SelectionModelType.info,
            updatedListener: (model) {
              if(model.hasDatumSelection) {
                final rating = _ratings[model.selectedDatum[0].index!];
                _EloTooltipRenderer.index = model.selectedDatum[0].index!;
                _EloTooltipRenderer.indexTotal = _ratings.length;
                _EloTooltipRenderer.rating = rating.baseEvent.newRating;
                _EloTooltipRenderer.error = rating.errorAt;
                _highlight(rating);
              }
            },
          ),
          charts.SelectionModelConfig(
            type: charts.SelectionModelType.action,
            updatedListener: (model) {
              if(model.hasDatumSelection) {
                final rating = _ratings[model.selectedDatum[0].index!];
                Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                  return ResultPage(canonicalMatch: rating.baseEvent.match, allowWhatIf: false);
                }));

              }
            },
          )
        ],
        domainAxis: charts.NumericAxisSpec(
          renderSpec: charts.NoneRenderSpec(
              axisLineStyle: charts.LineStyleSpec(
                thickness: 1,
              )
          ),
          showAxisLine: true,
        ),
        primaryMeasureAxis: charts.NumericAxisSpec(
          viewport: charts.NumericExtents(minWithError - 50, maxWithError + 50),
          tickProviderSpec: charts.BasicNumericTickProviderSpec(
            dataIsInWholeNumbers: true,
            desiredMinTickCount: 8,
            desiredTickCount: 10,
          ),
          tickFormatterSpec: charts.BasicNumericTickFormatterSpec.fromNumberFormat(_nf),
          showAxisLine: true,
        ),
      );
    }

    double width = max(600, size.width * 0.9);
    double height = size.height > size.width ? width / 1.5 : width / 3;
    return SizedBox(
      height: height,
      width: width,
      child: _chart!,
    );
  }

  void _highlight(_AccumulatedRatingEvent e) {
    setState(() {
      _highlighted = e.baseEvent;
    });

    var ctx = GlobalObjectKey(e.baseEvent.hashCode).currentContext;
    if(ctx != null) Scrollable.ensureVisible(ctx);
  }

  List<Widget> _buildShooterStats(BuildContext context) {
    var average = widget.rating.averageRating();
    var lifetimeAverage = widget.rating.averageRating(window: widget.rating.ratingEvents.length);
    return [
      Row(
        children: [
          Expanded(flex: 4, child: Text("Current rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${widget.rating.rating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Peak rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${lifetimeAverage.maxRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
          Divider(height: 2, thickness: 1)
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average rating (past 30 events)", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${average.averageOfIntermediates.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max rating (past 30 events)", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${average.minRating.round()}-${average.maxRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
          Divider(height: 2, thickness: 1)
        ],
      ),
      Divider(height: 2, thickness: 1),
    ];
  }
}

class _AccumulatedRatingEvent {
  RatingEvent baseEvent;
  double accumulated;
  double errorAt;

  _AccumulatedRatingEvent(this.baseEvent, this.accumulated, this.errorAt);
}

class _EloTooltipRenderer extends charts.CircleSymbolRenderer {
  static late double rating;
  static late double error;
  static late int index;
  static late int indexTotal;

  @override
  void paint(charts.ChartCanvas canvas, Rectangle<num> bounds, {List<int>? dashPattern, charts.Color? fillColor, charts.FillPatternType? fillPattern, charts.Color? strokeColor, double? strokeWidthPx}) {
    super.paint(canvas, bounds, dashPattern: dashPattern, fillColor: fillColor, strokeColor: strokeColor, strokeWidthPx: strokeWidthPx);

    var proportion = index.toDouble() / (indexTotal.toDouble() - 1);
    var leftOffset = -(proportion * 60) + 10;

    var ratingText = "${rating.round()}";
    if(error != 0) {
      ratingText += "±${error.round()}";
    }

    canvas.drawRect(
        Rectangle(bounds.left - 5, bounds.top - 30, bounds.width + 10, bounds.height + 10),
        fill: charts.Color.transparent
    );
    var textStyle = style.TextStyle();
    textStyle.color = charts.Color.black;
    textStyle.fontSize = 12;
    canvas.drawText(
        element.TextElement("$ratingText", style: textStyle),
        (bounds.left + leftOffset).round(),
        (bounds.top - 40).round()
    );
  }
}