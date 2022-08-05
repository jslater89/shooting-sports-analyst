import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';

/// ShooterRatingChangeDialog displays per-stage changes for a shooter.
class ShooterRatingChangeDialog extends StatelessWidget {
  const ShooterRatingChangeDialog({Key? key, required this.rating, required this.match}) : super(key: key);

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
      title: Text("Ratings for ${rating.shooter.getName(suffixes: false)}"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Current rating: ${rating.rating.round()}", style: Theme.of(context).textTheme.subtitle1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                height: 300,
                width: 600,
                child: _buildChart(events)
              ),
            ),
            ...events.reversed.map((e) =>
                Tooltip(
                    message: e.info.join("\n"),
                    child: Text("${e.eventName}: ${e.ratingChange.toStringAsFixed(2)}")
                )
            ).toList()
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<RatingEvent> events) {
    LabelLayoutStrategy? xContainerLabelLayoutStrategy;
    ChartOptions.noLabels();
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
}
