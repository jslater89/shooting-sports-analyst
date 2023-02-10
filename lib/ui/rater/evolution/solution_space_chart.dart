import 'package:charts_flutter/flutter.dart' as charts;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_evaluation.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';
import 'dart:ui' as ui show Color;

import 'package:uspsa_result_viewer/ui/rater/evolution/pareto_front_chart.dart';

class SolutionSpaceCharts extends StatefulWidget {
  const SolutionSpaceCharts({Key? key, required this.tuner, this.highlight}) : super(key: key);
  
  final EloTuner tuner;
  final EloEvaluator? highlight;

  @override
  State<SolutionSpaceCharts> createState() => _SolutionSpaceChartsState();
}

class _SolutionSpaceChartsState extends State<SolutionSpaceCharts> with TickerProviderStateMixin {
  late TabController controller;

  @override
  void initState() {
    controller = TabController(length: 5, vsync: this, animationDuration: Duration(microseconds: 1));
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: SizedBox(
            height: 20,
            child: TabBar(
              controller: controller,
              tabs: [
                Tab(
                  child: Text("OVR"),
                ),
                Tab(
                  child: Text("MAR"),
                ),
                Tab(
                  child: Text("MAE"),
                ),
                Tab(
                  child: Text("MTE"),
                ),
                Tab(
                  child: Text("PAR"),
                )
              ]
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              _parallelCoordinatesPlot(),
              _maxVsAvgRatPlot(),
              _maxVsAvgErrPlot(),
              _maxVsTotErrPlot(),
              _switchableParetoPlot(),
            ]
          ),
        )
      ],
    );
  }

  List<String> fnNames = [
    "totErr",
    "maxRat",
    "avgRat",
    "ord",
    "avgErr",
  ];
  String xName = "maxRat";
  String yName = "avgRat";
  Widget _switchableParetoPlot() {
    EloEvalFunction? fX = EloEvaluator.evaluationFunctions.entries.firstWhereOrNull((f) => f.key == xName)?.value;
    EloEvalFunction? fY = EloEvaluator.evaluationFunctions.entries.firstWhereOrNull((f) => f.key == yName)?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if(fX != null && fY != null)
          Expanded(child: ParetoFrontChart(tuner: widget.tuner, fX: fX, fY: fY, highlight: widget.highlight)),
        if(fX == null || fY == null)
          Expanded(child: Center(child: Text("No chart selected"))),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("X:"),
            SizedBox(width: 5),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Icon(Icons.chevron_left),
                onTap: () {
                  var idx = fnNames.indexOf(xName);
                  idx -= 1;
                  if(idx < 0) idx = fnNames.length - 1;
                  setState(() {
                    xName = fnNames[idx];
                  });
                },
              ),
            ),
            SizedBox(width: 5),
            SizedBox(width: 50, child: Text(xName, textAlign: TextAlign.center)),
            SizedBox(width: 5),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Icon(Icons.chevron_right),
                onTap: () {
                  var idx = fnNames.indexOf(xName);
                  idx += 1;
                  idx = idx % fnNames.length;
                  setState(() {
                    xName = fnNames[idx];
                  });
                },
              ),
            ),
            SizedBox(width: 10),
            Text("Y:"),
            SizedBox(width: 5),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Icon(Icons.chevron_left),
                onTap: () {
                  var idx = fnNames.indexOf(yName);
                  idx -= 1;
                  if(idx < 0) idx = fnNames.length - 1;
                  setState(() {
                    yName = fnNames[idx];
                  });
                },
              ),
            ),
            SizedBox(width: 5),
            SizedBox(width: 50, child: Text(yName, textAlign: TextAlign.center)),
            SizedBox(width: 5),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Icon(Icons.chevron_right),
                onTap: () {
                  var idx = fnNames.indexOf(yName);
                  idx += 1;
                  idx = idx % fnNames.length;
                  setState(() {
                    yName = fnNames[idx];
                  });
                },
              ),
            ),
            SizedBox(width: 10),
          ],
        ),
      ],
    );
  }

  Widget _maxVsAvgRatPlot() {
    var f1 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "maxRat").value;
    var f2 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "avgRat").value;

    return ParetoFrontChart(tuner: widget.tuner, fX: f1, fY: f2, highlight: widget.highlight);
  }

  Widget _maxVsAvgErrPlot() {
    var f1 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "maxRat").value;
    var f2 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "avgErr").value;

    return ParetoFrontChart(tuner: widget.tuner, fX: f1, fY: f2, highlight: widget.highlight);
  }

  Widget _maxVsTotErrPlot() {
    var f1 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "maxRat").value;
    var f2 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "totErr").value;

    return ParetoFrontChart(tuner: widget.tuner, fX: f1, fY: f2, highlight: widget.highlight);
  }

  Widget _totErrVsOrdPlot() {
    var f1 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "totErr").value;
    var f2 = EloEvaluator.evaluationFunctions.entries.firstWhere((f) => f.key == "ord").value;

    return ParetoFrontChart(tuner: widget.tuner, fX: f1, fY: f2, highlight: widget.highlight);
  }

  Widget _parallelCoordinatesPlot() {
    List<List<double>> evaluatorLines = [];
    List<ui.Color> colors = [];
    List<String> xLabels = List.generate(EloEvaluator.evaluationFunctions.length, (index) => EloEvaluator.evaluationFunctions.keys.toList()[index]);
    List<String> yLabels = [];

    List<EloEvaluator> dominated = [];
    List<EloEvaluator> nonDominated = [];

    for(var e in widget.tuner.evaluatedPopulation) {
      if(widget.tuner.nonDominated.contains(e)) {
        nonDominated.add(e);
      }
      else {
        dominated.add(e);
      }
    }

    EloEvaluator? highlight;

    for(var e in nonDominated) {
      if(e == widget.highlight) {
        highlight = e;
        continue;
      }
      evaluatorLines.add(e.evaluations.keys.map((f) {
        var vMax = widget.tuner.firstGenerationMaximums[f]!;
        return (e.evaluations[f]! / vMax) * 100;
      }).toList());
      colors.add(Colors.green.shade500);
      yLabels.add("");
    }

    // Draw these first so we can see when they start to cluster at the bottom
    for(var e in dominated) {
      if(e == widget.highlight) {
        highlight = e;
        continue;
      }
      evaluatorLines.add(e.evaluations.keys.map((f) {
        var vMax = widget.tuner.firstGenerationMaximums[f]!;
        return (e.evaluations[f]! / vMax) * 100;
      }).toList());
      colors.add(Colors.black.withAlpha(96));
      yLabels.add("");
    }

    if(highlight != null) {
      evaluatorLines.add(highlight.evaluations.keys.map((f) {
        var vMax = widget.tuner.firstGenerationMaximums[f]!;
        return (highlight!.evaluations[f]! / vMax) * 100;
      }).toList());
      colors.add(Colors.yellow.shade600);
      yLabels.add("");
    }

    ChartData data = ChartData(dataRows: evaluatorLines, xUserLabels: xLabels, dataRowsLegends: yLabels, chartOptions: ChartOptions(
      dataContainerOptions: DataContainerOptions(
        dataRowsPaintingOrder: DataRowsPaintingOrder.lastToFirst,
      ),
      legendOptions: LegendOptions(
        isLegendContainerShown: false,
      ),
      lineChartOptions: LineChartOptions(
        hotspotInnerPaintColor: Colors.grey.shade300,
      )
    ), dataRowsColors: colors);

    return LineChart(
      painter: LineChartPainter(
        lineChartContainer: LineChartTopContainer(
          chartData: data,
        ),
      ),
    );
  }
}
