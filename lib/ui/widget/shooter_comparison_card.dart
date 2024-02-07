/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/util.dart';

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
            Text("${matchScore.place} - ${matchScore.ratio.asPercentage()}%"),
            for(var stageScore in matchScore.stageScores.values)
              ...stageInfo(context, stageScore),
          ],
        ),
      ),
    );
  }

  List<Widget> stageInfo(BuildContext context, RelativeStageScore stageScore) {
    var stage = stageScore.stage;
    if(stage.scoring is IgnoredScoring) return [];

    var color = stageScore.score.dnf ? Colors.grey : Colors.black;
    var headlineTheme = Theme.of(context).textTheme.titleMedium?.copyWith(color: color);
    var textTheme = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);

    return [
      Divider(),
      Text("Stage ${stage.stageId} - ${stage.name}",
        style: headlineTheme, overflow: TextOverflow.ellipsis),
      Text("${stageScore.place} - ${stageScore.ratio.asPercentage()}% - ${stageScore.score.displayString}",
        style: textTheme,
      ),
      // Text("${stageScore.score.a}A ${stageScore.score.c}C ${stageScore.score.d}D ${stageScore.score.m}M ${stageScore.score.ns}NS ${stageScore.score.penaltyCount}P",
      //   style: textTheme,
      // ),
    ];
  }
}
