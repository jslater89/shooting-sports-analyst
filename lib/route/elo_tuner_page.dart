import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_evaluation.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/genome.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/rater/evolution/predator_prey_view.dart';
import 'package:uspsa_result_viewer/ui/rater/evolution/solution_space_chart.dart';
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
  bool showingDominated = false;

  EloTuner? tuner;
  EloEvaluator? selected;

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

    for(var url in l2s.smallCalibration) {
      l2Calibration.add(cache.getMatchImmediate(url)!);
    }
    for(var url in l2s.smallTest) {
      l2Test.add(cache.getMatchImmediate(url)!);
    }
    for(var url in wpa.smallCalibration) {
      wpaCalibration.add(cache.getMatchImmediate(url)!);
    }
    for(var url in wpa.smallTest) {
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
        expectedMaxRating: 2800, // Sailer tax?
      ),
      EloEvaluationData(
        name: "L2s CO",
        group: RaterGroup.carryOptics,
        trainingData: l2Calibration,
        evaluationData: l2Test,
        expectedMaxRating: 2700,
      ),
      // EloEvaluationData(
      //   name: "L2s Limited",
      //   group: RaterGroup.limited,
      //   trainingData: l2Calibration,
      //   evaluationData: l2Test,
      //   expectedMaxRating: 2700,
      // ),
      // EloEvaluationData(
      //   name: "WPA Open",
      //   group: RaterGroup.open,
      //   trainingData: wpaCalibration,
      //   evaluationData: wpaTest,
      //   expectedMaxRating: 2300,
      // ),
      EloEvaluationData(
        name: "WPA CO",
        group: RaterGroup.carryOptics,
        trainingData: wpaCalibration,
        evaluationData: wpaTest,
        expectedMaxRating: 2300,
      ),
    ], callback: (update) async {
      _updateUi(update);

      // Let the UI get an update in edgewise
      await Future.delayed(Duration(milliseconds: 33));
    }, gridSize: 26,
    );

    // show the UI
    await(Future.delayed(Duration(milliseconds: 500)));

    tuner!.tune();
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
            if(tuner != null) Tooltip(
              message: "Toggle dominated",
              child: IconButton(
                icon: Icon(showingDominated ? Icons.remove_red_eye_outlined : Icons.remove_red_eye_rounded),
                onPressed: () {
                  setState(() {
                    showingDominated = !showingDominated;
                  });
                },
              ),
            ),
            if(tuner != null) Tooltip(
              message: "Pause",
              child: IconButton(
                icon: Icon(tuner!.paused ? Icons.play_arrow : Icons.pause),
                onPressed: () {
                  setState(() {
                    tuner!.paused = !tuner!.paused;

                    if(!tuner!.paused) {
                      tuner!.runUntilPaused();
                    }
                  });
                },
              ),
            ),
            if(tuner != null) Tooltip(
              message: "Export",
              child: IconButton(
                icon: Icon(Icons.save_alt),
                onPressed: () {
                  var fileContents = tuner!.nonDominated.map((e) {
                    String output = "Genome ${e.hashCode}";
                    if(tuner!.nonDominated.contains(e)) output += " (non-dom)";
                    output += "\n";

                    for(var name in EloEvaluator.evaluationFunctions.keys) {
                      var evaluation = e.evaluations[EloEvaluator.evaluationFunctions[name]!]!;
                      output += "$name: ${evaluation < 1 ? evaluation.toStringAsPrecision(2) : evaluation.toStringAsFixed(2)}, ";
                    }
                    output += "\n";
                    output += e.settings.toString();
                    return output;
                  }).join("\n\n");
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
    if(tuner == null || lastUpdate == null || tuner!.nonDominated.isEmpty) {
      return Center(child: Text("Awaiting data..."));
    }

    var t = tuner!;
    var update = lastUpdate!;
    List<EloEvaluator> currentPopulation;
    if(showingDominated) {
      currentPopulation = []..addAll(t.currentPopulation);
    }
    else {
      currentPopulation = t.nonDominated.toList();
    }

    var topTen = currentPopulation.sublist(0, min(currentPopulation.length, 10)).map((e) => e.settings.toGenome()).toList();
    var minimums = topTen.minimums();
    var maximums = topTen.maximums();

    var percentErrorAwareTrait = maximums.traitByName(EloGenome.errorAwareTrait.name);
    var percentErrorAware = (maximums.continuousTraits[percentErrorAwareTrait] ?? 0) * 100;

    var genomeString = "";
    if(update.evaluationTarget != null) {
      genomeString += "(progress: ${update.evaluationProgress}/${update.evaluationTotal})";
    }

    int unevaluated = t.currentPopulation.where((e) => !e.evaluated).length;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Text("Generation ${update.currentGeneration + 1}: ${update.currentOperation} $genomeString",
                      style: Theme.of(context).textTheme.headline5),
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
                      flex: 4,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Container(
                                width: double.infinity,
                                height: double.infinity,
                                child: PredatorPreyView<EloEvaluator>(grid: t.grid, nonDominated: t.nonDominated, highlight: selected),
                            ),
                          ),
                        )
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              child: SolutionSpaceCharts(tuner: t, highlight: selected),
                            ),
                          ),
                        )
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
        Padding(
            padding: EdgeInsets.all(2),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(child: Text("Population Statistics", style: Theme.of(context).textTheme.subtitle1)),
                        Expanded(child: Text("${t.nonDominated.length}/${t.currentPopulation.length} nondominated solutions")),
                        Expanded(child: Text("$unevaluated solutions to evaluate")),
                        Expanded(child: Text("${t.totalEvaluations} total solutions evaluated")),
                      ]
                    ),
                    SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(child: Text("K: ${minimums.traits[EloGenome.kTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.kTrait]?.toStringAsFixed(1) ?? "n/a"}")),
                        Expanded(child: Text("Scale: ${minimums.traits[EloGenome.scaleTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.scaleTrait]?.toStringAsFixed(1) ?? "n/a"}")),
                        Expanded(child: Text("Prob. Base: ${minimums.traits[EloGenome.baseTrait]?.toStringAsFixed(1) ?? "n/a"}-${maximums.traits[EloGenome.baseTrait]?.toStringAsFixed(1) ?? "n/a"}")),
                        Expanded(child: Text("Match Blend: ${minimums.traits[EloGenome.matchBlendTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.matchBlendTrait]?.toStringAsFixed(2) ?? "n/a"}")),
                        Expanded(child: Text("Pct. Weight: ${minimums.traits[EloGenome.pctWeightTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.pctWeightTrait]?.toStringAsFixed(2) ?? "n/a"}")),
                      ],
                    ),
                    SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(child: Text("Error Aware: ${percentErrorAware.toStringAsFixed(1)}% ")),
                        Expanded(
                          child: Text("Err Thresholds: ${minimums.traits[EloGenome.errorAwareMaxAsPercentScaleTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareMaxAsPercentScaleTrait]?.toStringAsFixed(2) ?? "n/a"}/"
                              "${minimums.traits[EloGenome.errorAwareMinAsPercentMaxTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareMinAsPercentMaxTrait]?.toStringAsFixed(2) ?? "n/a"}/"
                              "${minimums.traits[EloGenome.errorAwareZeroAsPercentMinTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareZeroAsPercentMinTrait]?.toStringAsFixed(2) ?? "n/a"}"),
                        ),
                        Expanded(
                          child: Text("Err Multipliers: ${minimums.traits[EloGenome.errorAwareLowerMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareLowerMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}/"
                              "${minimums.traits[EloGenome.errorAwareUpperMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}-${maximums.traits[EloGenome.errorAwareUpperMultiplierTrait]?.toStringAsFixed(2) ?? "n/a"}"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
        ),
      ],
    );
  }

  List<Widget> errorWidgets(EloEvaluator eval) {
    if(!eval.evaluated) return [];

    List<Widget> result = [];
    for(var name in EloEvaluator.evaluationFunctions.keys) {
      var evaluation = eval.evaluations[EloEvaluator.evaluationFunctions[name]!]!;
      result.add(Text(
        "$name: ${evaluation < 1 ? evaluation.toStringAsPrecision(2) : evaluation.toStringAsFixed(2)}"
      ));
      result.add(SizedBox(width: 8));
    }
    return result;
  }

  Widget _buildEvalCard(EloEvaluator eval, int index) {
    var settings = eval.settings;
    Color? color = tuner!.nonDominated.contains(eval) ? null : Colors.grey.shade200;
    if(selected == eval) {
      color = Colors.yellowAccent.shade100;
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: GestureDetector(
        onTap: () {
          if(selected == eval) {
            setState(() {
              selected = null;
            });
          }
          else {
            setState(() {
              selected = eval;
            });
          }
        },
        child: Card(
          color: color,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("#${index + 1} Genome ${eval.hashCode} ", style: Theme.of(context).textTheme.subtitle1),
                    SizedBox(width: 8),
                    ...errorWidgets(eval)
                  ],
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
      ),
    );
  }
}
