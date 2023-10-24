/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class ShooterComparisonCard extends StatelessWidget {
  const ShooterComparisonCard({
    Key? key,
    required this.shooter,
    required this.matchScore,
    required this.onShooterRemoved,
  }) : super(key: key);

  final Shooter shooter;
  final RelativeMatchScore matchScore;
  final void Function(Shooter shooter) onShooterRemoved;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(shooter.getName(suffixes: false),
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
                IconButton(
                  icon: Icon(Icons.remove),
                  onPressed: () {
                    onShooterRemoved(shooter);
                  },
                )
              ],
            ),
            Text("${matchScore.total.place} - ${matchScore.total.percent.asPercentage()}%"),
            for(var stageScore in matchScore.stageScores.values)
              ...stageInfo(context, stageScore),
          ],
        ),
      ),
    );
  }

  List<Widget> stageInfo(BuildContext context, RelativeScore stageScore) {
    var stage = stageScore.stage!;
    if(stage.type == Scoring.chrono) return [];

    var color = stageScore.score.isDnf ? Colors.grey : Colors.black;
    var headlineTheme = Theme.of(context).textTheme.titleMedium?.copyWith(color: color);
    var textTheme = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);

    return [
      Divider(),
      Text("Stage ${stage.internalId} - ${stage.name}",
        style: headlineTheme, overflow: TextOverflow.ellipsis),
      Text("${stageScore.place} - ${stageScore.percent.asPercentage()}% - ${stageScore.score.getHitFactor().toStringAsFixed(4)}HF",
        style: textTheme,
      ),
      Text("${stageScore.score.a}A ${stageScore.score.c}C ${stageScore.score.d}D ${stageScore.score.m}M ${stageScore.score.ns}NS ${stageScore.score.penaltyCount}P",
        style: textTheme,
      ),
    ];
  }
}
