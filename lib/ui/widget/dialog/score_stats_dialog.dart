/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/util.dart';

class ScoreStatsDialog extends StatefulWidget {
  const ScoreStatsDialog({super.key, required this.scores, this.stage});

  final List<RelativeMatchScore> scores;
  final MatchStage? stage;

  @override
  State<ScoreStatsDialog> createState() => _ScoreStatsDialogState();
}

class _ScoreStatsDialogState extends State<ScoreStatsDialog> {

  double classificationCorrelation = 0.0;

  @override
  void initState() {
    super.initState();

    debugPrint("Calculating score stats for ${widget.scores.length} scores on stage ${widget.stage}");

    late List<RelativeScore> scores;
    if(widget.stage != null) {
      scores = widget.scores.map((e) => e.stageScores[widget.stage]!).toList()..sort((a, b) => a.place.compareTo(b.place));
    }
    else {
      // No need to re-sort, since we're already in match score order
      scores = widget.scores;
    }

    double correlation = 0.0;
    int unclassified = 0;
    // TODO: fix later
    // can probably be made USPSA-specific

    // scores are sorted in order of finish. For each score, add 1 to correlation
    // if nobody who finished in a higher place (i.e., earlier in the list) has a
    // classification lower than that score.
    // for(int i = 0; i < scores.length; i++) {
    //   var iClass = scores[i].shooter.classification ?? Classification.U;
    //   if(iClass == Classification.U || iClass == Classification.unknown) {
    //     unclassified += 1;
    //     continue;
    //   }
    //
    //   int evaluated = 0;
    //   double innerCorrelation = 0.0;
    //   for (int j = 0; j < scores.length ; j++) {
    //     if(i == j) continue;
    //
    //     var jClass = scores[j].score.shooter.classification ?? Classification.U;
    //     if (jClass == Classification.U || jClass == Classification.unknown) continue;
    //
    //     // If J finished better than I and J is of higher or equal class, or if
    //     // J finished worse than I and J is of lower or equal class, we're correlated.
    //     if (j < i && jClass.index <= iClass.index) {
    //       innerCorrelation += 1;
    //     }
    //     else if (j > i && jClass.index >= iClass.index) {
    //       innerCorrelation += 1;
    //     }
    //     evaluated += 1;
    //   }
    //
    //
    //   correlation += innerCorrelation / evaluated;
    //
    // }
    //
    // classificationCorrelation = correlation / (scores.length - unclassified);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Score Statistics"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Correlation factor: ${classificationCorrelation.asPercentage()}")
        ],
      ),
    );
  }
}
