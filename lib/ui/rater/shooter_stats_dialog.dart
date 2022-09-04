import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:charts_flutter/src/text_style.dart' as style;
import 'package:charts_flutter/src/text_element.dart' as element;

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
          Tooltip(
            child: Text("Ratings for ${widget.rating.shooter.getName(suffixes: false)} (${widget.rating.lastClassification.name})"),
            message: "Click a point on the chart to highlight the associated rating event."
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
          )
        ],
      ),
      content: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              // mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 36),
                  child: SizedBox(
                    height: 300,
                    width: 600,
                    child: _buildChart(events)
                  ),
                ),
                ..._buildShooterStats(context),
              ],
            ),
          ),
          Expanded(
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
                          message: e.info.join("\n"),
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
                                        flex: 8,
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
    );
  }

  Widget _buildChart(List<RatingEvent> events) {
    double accumulator = 0;
    double minRating = 10000;
    double maxRating = -10000;
    var ratings = events.map((e) {
      if(e.newRating < minRating) minRating = e.newRating;
      if(e.newRating > maxRating) maxRating = e.newRating;
      return _AccumulatedRatingEvent(e, accumulator += e.ratingChange);
    }).toList();

    var series = charts.Series<_AccumulatedRatingEvent, int>(
      id: 'Results',
      colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
      measureFn: (_AccumulatedRatingEvent e, _) => e.baseEvent.newRating,
      domainFn: (_, int? index) => index!,
      data: ratings,
    );

    return charts.LineChart(
      [series],
      animate: false,
      behaviors: [
        charts.SelectNearest(
          eventTrigger: charts.SelectionTrigger.tap,
          selectionModelType: charts.SelectionModelType.info,
          maximumDomainDistancePx: 400,
        ),
        charts.LinePointHighlighter(
          selectionModelType: charts.SelectionModelType.info
        )
      ],
      selectionModels: [
        charts.SelectionModelConfig(
          type: charts.SelectionModelType.info,
          updatedListener: (model) {
            if(model.hasDatumSelection) {
              final rating = ratings[model.selectedDatum[0].index!];
              _highlight(rating);
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
        viewport: charts.NumericExtents(minRating - 100, maxRating + 100),
        tickProviderSpec: charts.BasicNumericTickProviderSpec(
          dataIsInWholeNumbers: true,
          desiredMinTickCount: 8,
          desiredTickCount: 10,
        ),
        showAxisLine: true,
      ),
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

  _AccumulatedRatingEvent(this.baseEvent, this.accumulated);
}