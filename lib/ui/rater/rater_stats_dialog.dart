import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/ui/widget/box_and_whisker.dart';

class RaterStatsDialog extends StatefulWidget {
  const RaterStatsDialog(this.group, this.statistics, {Key? key}) : super(key: key);

  final RaterGroup group;
  final RaterStatistics statistics;

  static const _width = 500.0;

  @override
  State<RaterStatsDialog> createState() => _RaterStatsDialogState();
}

class _RaterStatsDialogState extends State<RaterStatsDialog> {
  /// Show histogram or quartiles.
  bool histogram = true;

  /// Show class statistics or date of entry.
  bool classStats = true;

  List<int> sortedYears = [];

  @override
  void initState() {
    super.initState();

    sortedYears = widget.statistics.yearOfEntryHistogram.keys.sorted((a, b) => a.compareTo(b));
    print("For rater group ${widget.group.uiLabel}:");
    int first = sortedYears.first;
    for(var y in sortedYears) {
      if(y == first) {
        print("\t$y or before:\t${widget.statistics.yearOfEntryHistogram[y]!} shooters");
      }
      else {
        print("\t$y:\t\t\t${widget.statistics.yearOfEntryHistogram[y]!} shooters");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("${widget.group.uiLabel} Statistics"),
      content: SizedBox(
        width: RaterStatsDialog._width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildStatsRows(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatsRows(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total shooters", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${widget.statistics.shooters}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average rating", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${widget.statistics.averageRating.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max ratings", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${widget.statistics.minRating.round()}-${widget.statistics.maxRating.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average history length", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${widget.statistics.averageHistory.toStringAsFixed(1)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() {
              classStats = !classStats;
            }),
            child: Text(classStats ? "Class statistics" : "Date of first match", style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Theme.of(context).colorScheme.tertiary)),
          )
        ),
      ),
      if(classStats) ...[
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
      ],
      if(!classStats) ...[
        entryDateKeyRow(context),
        Divider(height: 2, thickness: 1.5),
        ...entryDateRows(context),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() {
              histogram = !histogram;
            }),
            child: Text(histogram ? "Histogram" : "Quartiles", style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Theme.of(context).colorScheme.tertiary)),
          )
        ),
      ),
      SizedBox(
        height: RaterStatsDialog._width * 0.675,
        width: RaterStatsDialog._width,
        child: buildHistogram(context)
      ),
    ];
  }

  Widget entryDateKeyRow(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 1, child: Container()),
        Expanded(flex: 2, child: Text("Year", style: Theme.of(context).textTheme.bodyLarge)),
        Expanded(flex: 2, child: Text("Shooters", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right)),
        Expanded(flex: 1, child: Container()),
      ],
    );
  }

  List<Widget> entryDateRows(BuildContext context) {
    List<Widget> rows = [];
    for(var y in sortedYears) {
      String year = "$y";
      if(y == sortedYears.first) {
        year += " or before";
      }

      String shooterCount = "${widget.statistics.yearOfEntryHistogram[y]!}";

      rows.add(Row(
        children: [
          Expanded(flex: 1, child: Container()),
          Expanded(flex: 2, child: Text(year, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(shooterCount, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
          Expanded(flex: 1, child: Container()),
        ],
      ));

      rows.add(Divider(height: 2, thickness: 1));
    }

    return rows;
  }

  Widget classKeyRow(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text("Class", style: Theme.of(context).textTheme.bodyLarge)),
        Expanded(flex: 2, child: Text("Shooters", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text("Min-Max (Avg)", style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.right)),
      ],
    );
  }

  Widget rowForClass(BuildContext context, Classification clas) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(clas.name, style: Theme.of(context).textTheme.bodyMedium)),
        Expanded(
          flex: 2,
          child: Text("${widget.statistics.countByClass[clas]}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)
        ),
        Expanded(
            flex: 2,
            child: Text("${widget.statistics.minByClass[clas]!.round()}-${widget.statistics.maxByClass[clas]!.round()} "
                "(${widget.statistics.averageByClass[clas]!.round()})",
                style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)
        ),
      ],
    );
  }

  Widget buildHistogram(BuildContext context) {
    return histogram ? _barChartHistogram(context) : _boxPlot(context);
  }

  Widget _boxPlot(BuildContext context) {
    Map<Classification, Widget> plots = {};

    double maxOverall = double.negativeInfinity;
    double minOverall = double.infinity;

    for(var cls in Classification.values.reversed) {
      if(cls == Classification.unknown) continue;

      var ratings = widget.statistics.ratingsByClass[cls]!;
      var len = ratings.length;

      if(ratings.first < minOverall) minOverall = ratings.first;
      if(ratings.last > maxOverall) maxOverall = ratings.last;

      plots[cls] = BoxAndWhiskerPlot(
        direction: PlotDirection.vertical,
        minimum: ratings.first,
        maximum: ratings.last,
        median: ratings[len ~/ 2],
        lowerQuartile: ratings[(len * .25).floor()],
        upperQuartile: ratings[min(len - 1, (len * .75).floor())],
        rangeMin: widget.statistics.minRating * 0.975,
        rangeMax: widget.statistics.maxRating * 1.025,
        fillBox: true,
        upperBoxColor: cls.color,
        lowerBoxColor: cls.color,
        whiskerColor: cls.color,
        strokeWidth: 2.0,
      );
    }

    var average = (maxOverall + minOverall) / 2;
    var threeQuarters = (maxOverall + average) / 2;
    var oneQuarter = (minOverall + average) / 2;

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children:[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(maxOverall.round().toString(), style: Theme.of(context).textTheme.caption!),
                    Text(threeQuarters.round().toString(), style: Theme.of(context).textTheme.caption!),
                    Text(average.round().toString(), style: Theme.of(context).textTheme.caption!),
                    Text(oneQuarter.round().toString(), style: Theme.of(context).textTheme.caption!),
                    Text(minOverall.round().toString(), style: Theme.of(context).textTheme.caption!),
                  ],
                ),
              ),
              Text(""),
            ]
          ),
        ),
        ...plots.keys.map((cls) {
          return Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: plots[cls]!,
                  ),
                ),
                Text(cls.displayString()),
              ],
            ),
          );
        }).toList(),
      ]
    );
  }

  Widget _barChartHistogram(BuildContext context) {
    ChartOptions chartOptions = const ChartOptions(
      legendOptions: LegendOptions(
        //isLegendContainerShown: false,
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

    List<List<double>> series = [];
    var legends = <String>[];

    var hist = <int, int>{}..addAll(widget.statistics.histogram);
    var minKey = hist.keys.min;
    var maxKey = hist.keys.max;

    var keys = widget.statistics.histogram.keys.toList();
    keys.sort();

    for(var classification in Classification.values /*.reversed */) {
      if(classification == Classification.unknown) continue;

      var classHist = widget.statistics.histogramsByClass[classification]!;

      List<double> data = [];
      for(int i = minKey; i < maxKey + 1; i += 1) {
        data.add(classHist[i]?.toDouble() ?? 0.0);
      }

      legends.add(classification.name);
      series.add(data);
    }

    var labels = <String>[];
    for(int i = minKey; i < maxKey + 1; i += 1) {
      labels.add((i * widget.statistics.histogramBucketSize).toString());
    }

    ChartData chartData = ChartData(
      dataRows: series,
      xUserLabels: labels,
      dataRowsLegends: legends,
      chartOptions: chartOptions,
      dataRowsColors: Classification.values
          //.reversed
          .where((c) => c != Classification.unknown)
          .map((c) => c.color
      ).toList(),
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

extension _ChartColor on Classification {
  Color get color {
    switch(this) {

      case Classification.GM:
        return Colors.red;
      case Classification.M:
        return Colors.orange;
      case Classification.A:
        return Colors.yellow;
      case Classification.B:
        return Colors.green;
      case Classification.C:
        return Colors.blue;
      case Classification.D:
        return Color.fromARGB(0xff, 0x09, 0x1f, 0x92);
      case Classification.U:
        return Colors.deepPurple;
      case Classification.unknown:
        return Colors.deepPurple;
    }
  }
}