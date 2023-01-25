import 'dart:math';

import 'package:flutter/material.dart';
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

    List<Genome> genomes = Iterable.generate(27, (i) => EloGenome.randomGenome()).toList();
    genomes.add(EloSettings().toGenome());
    genomes.add(EloSettings().toGenome());
    genomes.add(EloSettings().toGenome());

    List<EloSettings> initialPopulation = genomes.map((g) => EloGenome.toSettings(g)).toList();

    tuner!.tune(initialPopulation, 3);
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
    return Container();
  }
}
