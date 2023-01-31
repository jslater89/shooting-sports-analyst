import 'dart:math';
import 'dart:ui' as ui show Color;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/genome.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/confirm_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/match_cache_loading_indicator.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/l2s_data.dart' as l2s;
import 'package:uspsa_result_viewer/data/ranking/evolution/wpa_data.dart' as wpa;

class EloTunerPage extends StatefulWidget {
  const EloTunerPage({Key? key}) : super(key: key);

  @override
  State<EloTunerPage> createState() => _EloTunerPageState();
}

class _EloTunerPageState extends State<EloTunerPage> {
  bool matchCacheReady = false;

  EloTuner? tuner;

  @override
  void initState() {
    super.initState();
    _warmUpMatchCache();
  }

  Future<void> _warmUpMatchCache() async {
    // Allow time for the 'loading' screen to display
    await Future.delayed(Duration(milliseconds: 1));

    await MatchCache().ready;
    setState(() {
      matchCacheReady = true;
    });

    var cache = MatchCache();
    List<PracticalMatch> l2Test = [];
    List<PracticalMatch> l2Calibration = [];
    List<PracticalMatch> wpaTest = [];
    List<PracticalMatch> wpaCalibration = [];

    for(var url in l2s.calibration) {
      l2Calibration.add(cache.getMatchImmediate(url)!);
    }
    for(var url in l2s.test) {
      l2Test.add(cache.getMatchImmediate(url)!);
    }
    for(var url in wpa.calibration) {
      wpaCalibration.add(cache.getMatchImmediate(url)!);
    }
    for(var url in wpa.test) {
      wpaTest.add(cache.getMatchImmediate(url)!);
    }

    print("WPA: ${wpaCalibration.length} calibration matches, ${wpaTest.length} eval matches");
    print("L2s: ${l2Calibration.length} calibration matches, ${l2Test.length} eval matches");

    tuner = EloTuner([
      EloEvaluationData(
        name: "L2s Open",
        group: RaterGroup.open,
        trainingData: l2Calibration,
        evaluationData: l2Test,
      ),
      EloEvaluationData(
        name: "L2s CO",
        group: RaterGroup.carryOptics,
        trainingData: l2Calibration,
        evaluationData: l2Test,
      ),
      EloEvaluationData(
        name: "L2s Limited",
        group: RaterGroup.limited,
        trainingData: l2Calibration,
        evaluationData: l2Test,
      ),
      EloEvaluationData(
        name: "WPA Open",
        group: RaterGroup.open,
        trainingData: wpaCalibration,
        evaluationData: wpaTest
      ),
      EloEvaluationData(
        name: "WPA CO",
        group: RaterGroup.carryOptics,
        trainingData: wpaCalibration,
        evaluationData: wpaTest,
      ),
    ]);

    List<Genome> genomes = [];
    genomes.addAll(Iterable.generate(5, (i) => EloSettings().toGenome()));
    genomes.addAll(Iterable.generate(35, (i) => EloGenome.randomGenome()).toList());


    List<EloSettings> initialPopulation = genomes.map((g) => EloGenome.toSettings(g)).toList();

    // show the UI
    await(Future.delayed(Duration(milliseconds: 500)));

    tuner!.tune(initialPopulation, 5, (update) async {
      _updateUi(update);

      // Let the UI get an update in edgewise
      await Future.delayed(Duration(milliseconds: 33));
    });
  }

  EvaluationProgressUpdate? lastUpdate;
  void _updateUi(EvaluationProgressUpdate update) {
    setState(() {
      lastUpdate = update;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        var quit = await showDialog<bool>(context: context, builder: (context) =>
          ConfirmDialog(
            title: "Quit?",
            content: Text("Are you sure?"),
            negativeButtonLabel: "Cancel",
            positiveButtonLabel: "Quit",
          )
        );
        return quit ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Center(child: Text("Elo Tuner")),
          actions: [
            Tooltip(
              message: "Export",
              child: IconButton(
                icon: Icon(Icons.save_alt),
                onPressed: () {
                  if(lastUpdate == null) return;
                  var update = lastUpdate!;

                  var fileContents = update.evaluations.last.map((e) => e.settings.toString()).join("\n\n");
                  HtmlOr.saveFile("sorted-elo-settings.txt", fileContents);
                },
              ),
            )
          ],
        ),
        body:
          !matchCacheReady ? _loadingIndicator() : _body(),
      ),
    );
  }

  Widget _loadingIndicator() {
    var width = MediaQuery.of(context).size.width;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        SizedBox(height: 128, width: width),
        MatchCacheLoadingIndicator(),
      ],
    );
  }

  Widget _body() {
    if(lastUpdate == null || lastUpdate!.evaluations.isEmpty) {
      return Center(child: Text("Awaiting data..."));
    }

    var update = lastUpdate!;
    var currentPopulation = update.evaluations.last;

    var topTen = currentPopulation.sublist(0, min(currentPopulation.length, 10)).map((e) => e.settings.toGenome()).toList();
    var minimums = topTen.minimums();
    var maximums = topTen.maximums();

    var percentErrorAwareTrait = maximums.traitByName(EloGenome.errorAwareTrait.name);
    var percentErrorAware = (maximums.continuousTraits[percentErrorAwareTrait] ?? 0) * 100;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Text("Generation ${update.currentGeneration + 1}/${update.totalGenerations}, "
                  "Genome ${update.currentGenome + 1}/${update.totalGenomes}, "
                  "Training Set ${update.currentTrainingSet + 1}/${update.totalTrainingSets}, "
                  "Match ${update.currentMatch}/${update.totalMatches}",
                style: Theme.of(context).textTheme.headlineSmall),
              Expanded(
                child: ListView.builder(
                  itemCount: currentPopulation.length,
                  itemBuilder: (context, i) => _buildEvalCard(currentPopulation[i], i),
                ),
              )
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        child: _buildChart(update)
                      ),
                    ),
                  )
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Population Statistics", style: Theme.of(context).textTheme.subtitle1),
                          SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Expanded(child: Text("K: ${minimums.traits[EloGenome.kTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.kTrait]?.toStringAsFixed(1) ?? "n/a"}")),
                              Expanded(child: Text("Scale: ${minimums.traits[EloGenome.scaleTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.scaleTrait]?.toStringAsFixed(1) ?? "n/a"}")),
                              Expanded(child: Text("Prob. Base: ${minimums.traits[EloGenome.baseTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.baseTrait]?.toStringAsFixed(1) ?? "n/a"}")),
                            ],
                          ),
                          SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Expanded(child: Text("Match Blend: ${minimums.traits[EloGenome.matchBlendTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.matchBlendTrait]?.toStringAsFixed(2) ?? "n/a"}")),
                              Expanded(child: Text("Pct. Weight: ${minimums.traits[EloGenome.pctWeightTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.pctWeightTrait]?.toStringAsFixed(2) ?? "n/a"}")),
                            ],
                          ),
                          SizedBox(height: 5),
                          Text("Error Aware: ${percentErrorAware.toStringAsFixed(1)}% "),
                          SizedBox(height: 5),
                          Text("Err Thresholds: ${minimums.traits[EloGenome.errorAwareMaxAsPercentScaleTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareMaxAsPercentScaleTrait]?.toStringAsFixed(2) ?? "n/a"}/"
                              "${minimums.traits[EloGenome.errorAwareMinAsPercentMaxTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareMinAsPercentMaxTrait]?.toStringAsFixed(2) ?? "n/a"}/"
                              "${minimums.traits[EloGenome.errorAwareZeroAsPercentMinTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareZeroAsPercentMinTrait]?.toStringAsFixed(2) ?? "n/a"}"),
                          SizedBox(height: 5),
                          Text("Err Multipliers: ${minimums.traits[EloGenome.errorAwareLowerMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareLowerMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}/"
                              "${minimums.traits[EloGenome.errorAwareUpperMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareUpperMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}"),
                        ],
                      ),
                    ),
                  )
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildChart(EvaluationProgressUpdate update) {
    if(update.evaluations.isEmpty) return Container();

    List<double> minErrors = [];
    List<double> avgErrors = [];
    List<double> maxErrors = [];
    List<String> xLabels = [];
    List<String> yLabels = [
      "Min.",
      "Avg.",
      "Max.",
    ];

    int genIndex = 1;
    for(var generation in update.evaluations) {
      var errors = generation.map((e) => e.error).toList();
      if(errors.isNotEmpty) {
        minErrors.add(errors.min * 1000);
        maxErrors.add(errors.max * 1000);
        avgErrors.add(errors.average * 1000);
        xLabels.add("$genIndex");
        genIndex += 1;
      }
      else if(genIndex == 1 && errors.isEmpty) {
        return Container();
      }
    }

    ChartData data = ChartData(dataRows: [minErrors, avgErrors, maxErrors], xUserLabels: xLabels, dataRowsLegends: yLabels, chartOptions: ChartOptions(
      lineChartOptions: LineChartOptions(
        hotspotInnerPaintColor: Colors.grey.shade300,
      )
    ), dataRowsColors: [
      ui.Color.fromRGBO(Colors.blue.red, Colors.blue.green, Colors.blue.blue, 1.0),
      ui.Color.fromRGBO(Colors.green.red, Colors.green.green, Colors.green.blue, 1.0),
      ui.Color.fromRGBO(Colors.red.red, Colors.red.green, Colors.red.blue, 1.0),
    ]);

    return LineChart(
      painter: LineChartPainter(
        lineChartContainer: LineChartTopContainer(
          chartData: data,
        ),
      ),
    );
  }

  Widget _buildEvalCard(EloEvaluation eval, int index) {
    var roundedError = (eval.error * 1000).toStringAsPrecision(3);
    var settings = eval.settings;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("#${index + 1} Genome ${eval.id + 1} "
                "(Err $roundedError)", style: Theme.of(context).textTheme.subtitle1,
              ),
              SizedBox(height: 5),
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text("K: ${settings.K.toStringAsFixed(1)}"),
                      Text("PB: ${settings.probabilityBase.toStringAsFixed(1)}"),
                      Text("Sc: ${settings.scale.round()}"),
                      Text("Pct. Wt.: ${settings.percentWeight.toStringAsFixed(2)}"),
                      Text("MB: ${settings.matchBlend.toStringAsFixed(2)}"),
                      if(settings.errorAwareK) Text("Err thresh: ${settings.errorAwareZeroValue.round()}/${settings.errorAwareMinThreshold.round()}/${settings.errorAwareMaxThreshold.round()}"),
                      if(settings.errorAwareK) Text("Err mult: ${(1 - settings.errorAwareLowerMultiplier).toStringAsFixed(2)}/${(settings.errorAwareUpperMultiplier + 1).toStringAsFixed(2)}")
                    ],
                  ),
                  SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [

                    ],
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
