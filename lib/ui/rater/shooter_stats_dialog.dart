import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';

/// ShooterRatingChangeDialog displays per-stage changes for a shooter.
class ShooterStatsDialog extends StatelessWidget {
  const ShooterStatsDialog({Key? key, required this.rating, required this.match}) : super(key: key);

  final ShooterRating rating;
  final PracticalMatch match;

  @override
  Widget build(BuildContext context) {
    List<RatingEvent> events = rating.ratingEvents;
    // if(rating.ratingEvents.length < 30) {
    //   events = rating.ratingEvents;
    // }
    // else {
    //   events = rating.ratingEvents.sublist(rating.ratingEvents.length - 30);
    // }

    return AlertDialog(
      title: Text("Ratings for ${rating.shooter.getName(suffixes: false)} (${rating.lastClassification.name})"),
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
              thumbVisibility: true,
              child: SingleChildScrollView(
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
                                Row(
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
    LabelLayoutStrategy? xContainerLabelLayoutStrategy;
    ChartOptions chartOptions = const ChartOptions(
      xContainerOptions: XContainerOptions(
        isXContainerShown: false,
      ),
      yContainerOptions: YContainerOptions(
        isYGridlinesShown: false,
      ),
      lineChartOptions: LineChartOptions(
        hotspotInnerRadius: 0,
        hotspotOuterRadius: 0,
      )
    );
    double accumulator = 0;
    ChartData chartData = ChartData(
      dataRows: [events.map((e) => accumulator += e.ratingChange).toList()],
      xUserLabels: events.map((_) => "").toList(),
      dataRowsLegends: ["Change in Rating"],
      chartOptions: chartOptions,
      dataRowsColors: [Colors.blueGrey],
    );

    var lineChartContainer = LineChartTopContainer(
      chartData: chartData,
      xContainerLabelLayoutStrategy: xContainerLabelLayoutStrategy,
    );

    var lineChart = LineChart(
      painter: LineChartPainter(
        lineChartContainer: lineChartContainer,
      ),
    );
    return lineChart;
  }

  List<Widget> _buildShooterStats(BuildContext context) {
    var average = rating.averageRating();
    var lifetimeAverage = rating.averageRating(window: rating.ratingEvents.length);
    return [
      Row(
        children: [
          Expanded(flex: 4, child: Text("Current rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${rating.rating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
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