import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';

class RaterStatsDialog extends StatelessWidget {
  const RaterStatsDialog(this.statistics, {Key? key}) : super(key: key);

  final RaterStatistics statistics;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Statistics"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildStatsRows(context),
        ),
      ),
    );
  }

  List<Widget> _buildStatsRows(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total shooters", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${statistics.shooters}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${statistics.averageRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max ratings", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${statistics.minRating.round()}-${statistics.maxRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8),
        child: Text("Class statistics", style: Theme.of(context).textTheme.bodyText1),
      ),
      classKeyRow(context),
      Divider(height: 2, thickness: 1.5),
      rowForClass(context, Classification.GM),
      Divider(height: 2, thickness: 1),
      rowForClass(context, Classification.M),
      Divider(height: 2, thickness: 1),
      rowForClass(context, Classification.A),
      Divider(height: 2, thickness: 1),
      rowForClass(context, Classification.B),
      Divider(height: 2, thickness: 1),
      rowForClass(context, Classification.C),
      Divider(height: 2, thickness: 1),
      rowForClass(context, Classification.D),
      Divider(height: 2, thickness: 1),
      rowForClass(context, Classification.U),
      Divider(height: 2, thickness: 1),
      Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8),
        child: Text("Histogram", style: Theme.of(context).textTheme.bodyText1),
      ),
      SizedBox(
        height: 275,
        width: 400,
        child: buildHistogram(context)
      ),
    ];
  }

  Widget classKeyRow(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text("Class", style: Theme.of(context).textTheme.bodyText1)),
        Expanded(flex: 2, child: Text("Shooters", style: Theme.of(context).textTheme.bodyText1, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text("Min-Max (Avg)", style: Theme.of(context).textTheme.bodyText1, textAlign: TextAlign.right)),
      ],
    );
  }
  Widget rowForClass(BuildContext context, Classification clas) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(clas.name, style: Theme.of(context).textTheme.bodyText2)),
        Expanded(
          flex: 2,
          child: Text("${statistics.countByClass[clas]}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)
        ),
        Expanded(
            flex: 2,
            child: Text("${statistics.minByClass[clas]!.round()}-${statistics.maxByClass[clas]!.round()} "
                "(${statistics.averageByClass[clas]!.round()})",
                style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)
        ),
      ],
    );
  }

  Widget buildHistogram(BuildContext context) {
    ChartOptions chartOptions = const ChartOptions(
      legendOptions: LegendOptions(
        isLegendContainerShown: false,
      ),
      xContainerOptions: XContainerOptions(
        isXContainerShown: true,
      ),
      yContainerOptions: YContainerOptions(
        isYGridlinesShown: false,
      ),
      iterativeLayoutOptions: IterativeLayoutOptions()
    );
    LabelLayoutStrategy strategy = DefaultIterativeLabelLayoutStrategy(
      options: chartOptions,
    );

    var hist = <int, int>{}..addAll(statistics.histogram);
    var minKey = hist.keys.min;
    var maxKey = hist.keys.max;

    for(int i = minKey; i < maxKey; i += 100) {
      hist[i] ??= 0;
    }
    var keys = statistics.histogram.keys.toList();
    keys.sort();

    var data = <double>[];
    var labels = <String>[];
    for(var key in keys) {
      data.add(hist[key]!.toDouble());
      labels.add((key * 100).toString());
    }

    ChartData chartData = ChartData(
      dataRows: [data],
      xUserLabels: labels,
      dataRowsLegends: [""],
      chartOptions: chartOptions,
      dataRowsColors: [Colors.blueGrey],
    );

    var barChartContainer = VerticalBarChartTopContainer(
      xContainerLabelLayoutStrategy: strategy,
      chartData: chartData,
    );

    return VerticalBarChart(
      painter: VerticalBarChartPainter(
        verticalBarChartContainer: barChartContainer,
      )
    );
  }
}
