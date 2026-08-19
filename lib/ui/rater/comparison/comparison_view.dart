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
    return Column(
      children: [
        RatingComparisonChart(
          rating1: model.rating1,
          careerStats1: model.careerStats1,
          displayedStats1: model.displayedStats1!,
          rating2: model.rating2,
          careerStats2: model.careerStats2,
          displayedStats2: model.displayedStats2!,
          onMatchIdHighlighted: (matchId) {
            model.highlightedMatchId = matchId;
          },
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: 1, child: HeadToHeadStatsTable()),
              SizedBox(width: 10),
              Expanded(flex: 3, child: RatingMatchComparisonTable()),
            ],
          )
        ),
      ],
    );
  }
}