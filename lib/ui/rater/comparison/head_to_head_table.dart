/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/ranking/model/career_stats.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_model.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

class HeadToHeadStatsTable extends StatelessWidget {
  const HeadToHeadStatsTable({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<RatingComparisonModel>(context);
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final count = model.competitorCount;

    final surnames = model.ratings.map((r) => r.lastName).toList();
    final fR = model.rating1.formatNumericRating;

    // Per-person stats
    final totalMatches = <int>[];
    final totalWins = <int>[];
    final currentRatings = <double>[];
    final recentAverages = <double>[];
    final careerPeaks = <double>[];
    final dqs = <int>[];
    final alphaPcts = <String>[];

    for(int i = 0; i < count; i++) {
      final career = model.careerStatsAt(i);
      final rating = model.ratings[i];
      final byStage = career.byStage;
      final averageWindow = byStage ? 30 : 5;

      totalMatches.add(career.annualStats.map((e) => e.matchHistory).flattened.length);
      totalWins.add(career.annualStats.map((e) => e.matchHistory).flattened.where((e) => e.place == 1).length);
      currentRatings.add(rating.rating);
      recentAverages.add(rating.averageRating(window: averageWindow).averageOfIntermediates);
      careerPeaks.add(rating.averageRating(window: career.careerStats.events.length).maxRating);
      dqs.add(career.careerStats.dqs.length);
      alphaPcts.add(career.careerStats.totalScore?.hitPercentagesText(rating.sport, bestOnly: true) ?? "-");
    }

    final showAlpha = model.rating1.sport.type.isHitFactor || model.rating1.sport.type == SportType.icore;

    // Column widths: label + one per competitor
    final labelWidth = count == 2 ? 0.40 : 0.28;
    final personWidth = (1.0 - labelWidth) / count;
    final columnWidths = [labelWidth, for(int i = 0; i < count; i++) personWidth];

    final cells = <List<TableViewCell>>[
      // Header
      [
        TableViewCell(child: _LeftAlignedText(text: "Stat", style: TextStyle(fontWeight: FontWeight.w500))),
        for(int i = 0; i < count; i++)
          TableViewCell(child: _RightAlignedText(text: surnames[i], style: TextStyle(fontWeight: FontWeight.w500))),
      ],
      _statRow("Total matches", totalMatches.map((v) => "$v").toList()),
      _statRow("Total wins", totalWins.map((v) => "$v").toList()),
      _statRow("Current rating", currentRatings.map((v) => fR(v)).toList()),
      _statRow("Recent average", recentAverages.map((v) => fR(v)).toList()),
      _statRow("Career peak", careerPeaks.map((v) => fR(v)).toList()),
      if(showAlpha)
        _statRow("Alpha percentage", alphaPcts),
      _statRow("DQs", dqs.map((v) => "$v").toList()),
    ];

    // Pairwise H2H block
    final pairwiseRows = <List<TableViewCell>>[];
    if(count == 2) {
      final (wins0, wins1) = model.pairwiseRecord(0, 1);
      final h2hMatches = model.matchesWithAllResults.length;
      pairwiseRows.add([
        TableViewCell(child: _LeftAlignedText(text: "H2H matches")),
        TableViewCell(child: _RightAlignedText(text: "$h2hMatches")),
        TableViewCell(child: SizedBox.shrink()),
      ]);
      pairwiseRows.add([
        TableViewCell(child: _LeftAlignedText(text: "H2H wins")),
        TableViewCell(child: _RightAlignedText(text: "$wins0")),
        TableViewCell(child: _RightAlignedText(text: "$wins1")),
      ]);
    }
    else {
      // N=3: all-three count + pairwise records spanning columns
      pairwiseRows.add([
        TableViewCell(child: _LeftAlignedText(text: "H2H (all three)")),
        TableViewCell(child: _RightAlignedText(text: "${model.allCompetitorMatchCount}")),
        for(int i = 1; i < count; i++)
          TableViewCell(child: SizedBox.shrink()),
      ]);
      for(int i = 0; i < count; i++) {
        for(int j = i + 1; j < count; j++) {
          final (winsI, winsJ) = model.pairwiseRecord(i, j);
          pairwiseRows.add([
            TableViewCell(child: _LeftAlignedText(text: "${surnames[i]} vs ${surnames[j]}")),
            TableViewCell(child: _RightAlignedText(text: "$winsI-$winsJ")),
            for(int k = 1; k < count; k++)
              TableViewCell(child: SizedBox.shrink()),
          ]);
        }
      }
    }

    cells.addAll(pairwiseRows);

    return TableView.list(
      columnBuilder: (column) {
        return TableSpan(
          extent: FractionalTableSpanExtent(columnWidths[column]),
        );
      },
      rowBuilder: (row) {
        TableSpanDecoration? decoration;
        if(row == 0) {
          decoration = TableSpanDecoration(
            border: TableSpanBorder(
              trailing: BorderSide(
                color: ThemeColors.onBackgroundColor(context),
                width: 1 * uiScaleFactor,
              ),
            ),
          );
        }
        else {
          decoration = TableSpanDecoration(
            border: TableSpanBorder(
              trailing: BorderSide(
                color: ThemeColors.onBackgroundColorFaded(context),
                width: 1 * uiScaleFactor,
              ),
            ),
          );
        }
        return TableSpan(
          backgroundDecoration: decoration,
          extent: FixedTableSpanExtent(40 * uiScaleFactor),
        );
      },
      cells: cells,
    );
  }

  List<TableViewCell> _statRow(String label, List<String> values) {
    return [
      TableViewCell(child: _LeftAlignedText(text: label)),
      for(var v in values)
        TableViewCell(child: _RightAlignedText(text: v)),
    ];
  }
}

class _LeftAlignedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _LeftAlignedText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.centerLeft, child: Text(text, style: style));
  }
}

class _RightAlignedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _RightAlignedText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.centerRight, child: Text(text, style: style));
  }
}
