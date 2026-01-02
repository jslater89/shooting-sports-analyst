/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_model.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_divisions.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_predictions.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_rating_links.dart';
import 'package:shooting_sports_analyst/ui/prematch/widget/match_prep_squadding.dart';

final _log = SSALogger("MatchPrepPage");

/// A match prep page displays details of a match prep. It has controls for showing
/// predictions, ratings, a breakdown of registrations, the registration mapping dialog,
/// and other items of interest.
class MatchPrepPage extends StatefulWidget {
  const MatchPrepPage({super.key, required this.prep});

  final MatchPrep prep;

  @override
  State<MatchPrepPage> createState() => _MatchPrepPageState();
}

class _MatchPrepPageState extends State<MatchPrepPage> with TickerProviderStateMixin {

  late MatchPrepPageModel _model;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _model = MatchPrepPageModel(prep: widget.prep);
    _model.init();
    _tabController = TabController(length: _MatchPrepPageTab.values.length, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _model,
      child: EmptyScaffold(
        title: _model.futureMatch.eventName,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: _MatchPrepPageTab.values.map((tab) => Tab(text: tab.uiLabel)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ..._MatchPrepPageTab.values.map((tab) => tab.build(context, _model)).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MatchPrepPageTab {
  ratingLinks,
  squadding,
  divisions,
  predictions;

  String get uiLabel =>
    switch(this) {
      _MatchPrepPageTab.ratingLinks => "Rating Links",
      _MatchPrepPageTab.squadding => "Squadding",
      _MatchPrepPageTab.divisions => "Divisions",
      _MatchPrepPageTab.predictions => "Predictions",
    };

  Widget build(BuildContext context, MatchPrepPageModel model) =>
    switch(this) {
      _MatchPrepPageTab.ratingLinks =>
        MatchPrepRatingLinks(groups: model.ratingProject.groups),
      _MatchPrepPageTab.squadding =>
        MatchPrepSquadding(),
      _MatchPrepPageTab.divisions =>
        MatchPrepDivisions(groups: model.ratingProject.groups),
      _MatchPrepPageTab.predictions =>
        MatchPrepPredictions(),
    };
}
