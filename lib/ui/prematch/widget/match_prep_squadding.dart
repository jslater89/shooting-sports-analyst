/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/route/match_prep_page.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';
import 'package:shooting_sports_analyst/util.dart';

class MatchPrepSquadding extends StatelessWidget {
  const MatchPrepSquadding({super.key});

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Consumer<MatchPrepPageModel>(
      builder: (context, model, child) {
        Map<String, List<String>> squadsBySchedule = {};
        for(var squad in model.knownSquads) {
          if(squad.length > 0) {
            var schedule = squad.substring(0, 1);
            squadsBySchedule.addToList(schedule, squad);
          }
        }
        final crossAxisCount = MediaQuery.of(context).size.width / (400 * uiScaleFactor);

        List<Widget> children = [];
        for(var (index, entry) in squadsBySchedule.entries.indexed) {
          children.add(
            _MatchPrepSquaddingSchedule(
              schedule: entry.key,
              squads: entry.value,
              crossAxisCount: crossAxisCount.round(),
            ),
          );
          if(index < squadsBySchedule.entries.length - 1) {
            children.add(Divider(height: 16 * uiScaleFactor, thickness: 2 * uiScaleFactor));
          }
        }

        return SingleChildScrollView(
          child: Column(
            children: children,
          ),
        );
      }
    );
  }
}

class _MatchPrepSquaddingSchedule extends StatelessWidget {
  const _MatchPrepSquaddingSchedule({
    required this.schedule,
    required this.squads,
    required this.crossAxisCount,
  });

  final String schedule;
  final List<String> squads;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    int rowCount = (squads.length / crossAxisCount).ceil();
    List<List<String>> rows = [];
    for(var i = 0; i < rowCount; i++) {
      rows.add(squads.sublist(i * crossAxisCount, min(i * crossAxisCount + crossAxisCount, squads.length)));
    }
    if(!rows.isEmpty) {
      if(rows.last.length < crossAxisCount) {
        rows.last.addAll(List.generate(crossAxisCount - rows.last.length, (index) => ""));
      }
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ...rows.map((row) => Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children:
            row.map((squad) {
              if(squad == "") {
                return Expanded(child: Container());
              }
              else {
                return Expanded(child: _SquadCard(squad: squad));
              }
            }).toList(),
        )),
      ],
    );
  }
}

class _SquadCard extends StatelessWidget {
  const _SquadCard({required this.squad});

  final String squad;

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Consumer<MatchPrepPageModel>(
      builder: (context, model, child) {
        final competitors = model.futureMatch.getRegistrationsFor(model.sport, squads: [squad]);
        competitors.sort((a, b) {
          var aName = a.shooterName;
          var bName = b.shooterName;
          if(aName == null && bName == null) {
            return 0;
          }
          if(aName == null) {
            return 1;
          }
          if(bName == null) {
            return -1;
          }

          String aLastName;
          String bLastName;
          ShooterRating? aRating;
          ShooterRating? bRating;
          if(model.matchedRegistrations.containsKey(a)) {
            aRating = model.matchedRegistrations[a];
          }
          if(model.matchedRegistrations.containsKey(b)) {
            bRating = model.matchedRegistrations[b];
          }

          if(aRating != null) {
            aLastName = aRating.lastName;
          }
          else {
            aLastName = aName.split(" ").last;
          }
          if(bRating != null) {
            bLastName = bRating.lastName;
          }
          else {
            bLastName = bName.split(" ").last;
          }

          return aLastName.compareTo(bLastName);
        });
        return Card(
          child: Padding(
            padding: EdgeInsets.all(8 * uiScaleFactor),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Text(squad, style: Theme.of(context).textTheme.titleMedium)),
                Divider(),
                _CompetitorKey(hasDivisions: model.sport.hasDivisions),
                ...competitors.mapIndexed((index, competitor) => _CompetitorRow(competitor: competitor, index: index)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompetitorKey extends StatelessWidget {
  static const _nameFlex = 3;
  static const _divisionFlex = 1;
  static const _ratingFlex = 1;
  const _CompetitorKey({this.hasDivisions = true});

  final bool hasDivisions;

  @override
  Widget build(BuildContext context) {
    return ScoreRow(
      hoverEnabled: false,
      useSurfaceColors: true,
      index: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(flex: _nameFlex, child: Text("Name", style: Theme.of(context).textTheme.titleSmall)),
                if(hasDivisions) Expanded(flex: _divisionFlex, child: Text("Division", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _ratingFlex, child: Text("Rating", style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            Divider(height: 2, thickness: 1, endIndent: 4),
          ],
        ),
      ),
    );
  }
}

class _CompetitorRow extends StatelessWidget {
  const _CompetitorRow({required this.competitor, required this.index});

  final MatchRegistration competitor;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchPrepPageModel>(
      builder: (context, model, child) {
        final division = model.sport.divisions.lookupByName(competitor.shooterDivisionName);
        final hasDivisions = model.sport.hasDivisions;
        final rating = model.matchedRegistrations[competitor];
        final row = ScoreRow(
          index: index,
          hoverEnabled: rating != null,
          useSurfaceColors: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                Expanded(flex: _CompetitorKey._nameFlex, child: Text(competitor.shooterName ?? "Unknown")),
                if(hasDivisions) Expanded(flex: _CompetitorKey._divisionFlex, child: Text(division?.shortDisplayName ?? "(n/a)")),
                Expanded(flex: _CompetitorKey._ratingFlex, child: Text(rating?.formattedRating() ?? "(unrated)")),
              ],
            ),
          ),
        );
        if(rating == null) {
          return row;
        }
        else {
          return ClickableLink(
            decorateColor: false,
            underline: false,
            onTap: () {
              ShooterStatsDialog.show(context, rating, sport: model.sport);
            },
            child: row,
          );
        }
      },
    );
  }
}