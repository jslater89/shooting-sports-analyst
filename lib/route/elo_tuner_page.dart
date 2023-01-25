import 'dart:math';
import 'dart:ui' as ui show Color;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/genome.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/ui/widget/match_cache_loading_indicator.dart';

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
    var matches = cache.allMatches().where((m) =>
        m.name!.contains(RegExp(r"Area [1-8]"))
    ).toList();
    var calibrationMatches = matches.where((m) =>
        m.name!.contains(RegExp(r"2022.*Area 4")) || m.name!.contains(RegExp(r"2022.*Area 8"))
    ).toList();

    for(var m in calibrationMatches) {
      matches.remove(m);
    }

    print("Tuning dataset:");
    print("Training matches (${matches.length}): $matches");
    print("Calibration matches (${calibrationMatches.length}): $calibrationMatches");

    tuner = EloTuner([
      EloEvaluationData(
        name: "Area Matches/A4/A8 Open",
        group: RaterGroup.open,
        trainingData: matches,
        evaluationData: calibrationMatches,
      ),
      EloEvaluationData(
        name: "Area Matches/A4 CO",
        group: RaterGroup.carryOptics,
        trainingData: matches,
        evaluationData: calibrationMatches,
      ),
      EloEvaluationData(
        name: "Area Matches/A4 Limited",
        group: RaterGroup.limited,
        trainingData: matches,
        evaluationData: calibrationMatches,
      ),
    ]);

    List<Genome> genomes = Iterable.generate(33, (i) => EloGenome.randomGenome()).toList();
    genomes.addAll(Iterable.generate(7, (i) => EloSettings().toGenome()));

    List<EloSettings> initialPopulation = genomes.map((g) => EloGenome.toSettings(g)).toList();

    // show the UI
    await(Future.delayed(Duration(milliseconds: 500)));

    tuner!.tune(initialPopulation, 6, (update) async {
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
        // TODO: ask to quit
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Center(child: Text("Elo Tuner")),
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

    print("mins: $minimums");

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
          flex: 1,
          child: Column(
            children: [
              Expanded(
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
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("K: ${minimums.traits[EloGenome.kTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.kTrait]?.toStringAsFixed(1) ?? "n/a"}"),
                          Text("Scale: ${minimums.traits[EloGenome.scaleTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.scaleTrait]?.toStringAsFixed(1) ?? "n/a"}"),
                          Text("Prob. Base: ${minimums.traits[EloGenome.baseTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.baseTrait]?.toStringAsFixed(1) ?? "n/a"}"),
                          Text("Match Blend: ${minimums.traits[EloGenome.matchBlendTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.matchBlendTrait]?.toStringAsFixed(2) ?? "n/a"}"),
                          Text("Error Aware: ${percentErrorAware.toStringAsFixed(1)}%"),
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
          child: Text("#${index + 1} Genome ${eval.id + 1} "
            "Err $roundedError "
            "K:${settings.K.toStringAsFixed(1)} "
            "PB:${settings.probabilityBase.toStringAsFixed(1)} "
            "Sc:${settings.scale.round()} "
            "MB: ${settings.matchBlend.toStringAsFixed(2)} "
            "EA: ${settings.errorAwareK} ",
          ),
        ),
      ),
    );
  }
}
