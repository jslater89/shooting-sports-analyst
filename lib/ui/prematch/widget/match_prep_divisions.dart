/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/route/match_prep_page.dart';

class MatchPrepDivisions extends StatelessWidget {
  const MatchPrepDivisions({super.key, required this.divisions});
  final List<Division> divisions;

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchPrepPageModel>(
      builder: (context, model, child) {
        return DefaultTabController(length: divisions.length,
          child: Column(
            children: [
              TabBar(tabs: divisions.map((d) => Tab(text: d.name)).toList()),
              Expanded(child: TabBarView(children: divisions.map((d) => Text(d.name)).toList())),
            ],
          ),
        );
      },
    );
  }
}
