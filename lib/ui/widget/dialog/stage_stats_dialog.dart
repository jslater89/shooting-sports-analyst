/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/match/stage_stats_calculator.dart';

class StageStatsDialog extends StatelessWidget {
  final StageStats stageStats;
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Stage hit statistics"),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("The average number of hits of each type on this stage, with the stage length normalized to 32 rounds."),
            SizedBox(height: 10),
            ...stageStats.hitsToRows(),
          ],
        ),
      )
    );
  }

  StageStatsDialog(this.stageStats);

  static Future<void> show(BuildContext context, StageStats stats) {
    return showDialog(context: context, builder: (context) => StageStatsDialog(stats));
  }
}