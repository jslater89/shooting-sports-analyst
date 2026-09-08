/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_chart.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_model.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/head_to_head_table.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/match_comparison_table.dart';

class RatingComparisonView extends StatefulWidget {
  const RatingComparisonView({super.key});

  @override
  State<RatingComparisonView> createState() => _RatingComparisonViewState();
}

class _RatingComparisonViewState extends State<RatingComparisonView> {
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final model = context.read<RatingComparisonModel>();

    while(!ready) {
      await Future.delayed(Duration(milliseconds: 100));
      ready = model.ready;
    }

    setState(() {
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<RatingComparisonModel>(context);

    if(!ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final h2hFlex = model.competitorCount > 2 ? 2 : 1;

    return Column(
      children: [
        RatingComparisonChart(
          ratings: model.ratings,
          careerStats: [
            for(int i = 0; i < model.competitorCount; i++) model.careerStatsAt(i),
          ],
          displayedStats: [
            for(int i = 0; i < model.competitorCount; i++) model.displayedStatsAt(i)!,
          ],
          onMatchIdHighlighted: (matchId) {
            model.highlightedMatchId = matchId;
          },
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: h2hFlex, child: HeadToHeadStatsTable()),
              SizedBox(width: 10),
              Expanded(flex: 3, child: RatingMatchComparisonTable()),
            ],
          )
        ),
      ],
    );
  }
}
