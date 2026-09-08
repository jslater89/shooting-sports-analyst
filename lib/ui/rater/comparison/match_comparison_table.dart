/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_model.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

class RatingMatchComparisonTable extends StatefulWidget {
  const RatingMatchComparisonTable({super.key});

  @override
  State<RatingMatchComparisonTable> createState() => _RatingMatchComparisonTableState();
}

class _RatingMatchComparisonTableState extends State<RatingMatchComparisonTable> {
  late ScrollController _scrollController;
  late RatingComparisonModel _model;

  late final double _uiScaleFactor;
  final double _rowHeight = 40;

  List<ShootingMatch> _sortedMatches = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;

    _model = context.read<RatingComparisonModel>();
    _model.addListener(_updateHighlightedMatch);
  }

  String? _lastHighlightedMatchId;
  void _updateHighlightedMatch() {
    final highlightedMatchId = _model.highlightedMatchId;
    if(highlightedMatchId == null) {
      _lastHighlightedMatchId = null;
      return;
    }

    if(highlightedMatchId == _lastHighlightedMatchId) {
      return;
    }
    _lastHighlightedMatchId = highlightedMatchId;

    final matchIndex = _sortedMatches.indexWhere((e) => e.sourceIds.contains(highlightedMatchId));
    if(matchIndex != -1) {
      _scrollController.animateTo(
        matchIndex * _uiScaleFactor * _rowHeight,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _model.removeListener(_updateHighlightedMatch);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<RatingComparisonModel>(context);
    final competitorCount = model.competitorCount;

    final List<ShootingMatch> matches;
    if(model.showOnlyMatchesWithAllResults) {
      matches = model.matchesWithAllResults.values.map((e) => e.match).nonNulls.toList();
    }
    else {
      matches = model.sharedMatchResults.values.map((e) => e.match).nonNulls.toList();
    }

    _sortedMatches = matches..sort(ShootingMatch.dateComparator);
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;

    // Columns: date, name, then one result column per competitor.
    final columnCount = competitorCount + 2;
    final resultWidth = 0.55 / competitorCount;
    final columnWidths = <double>[
      0.12,
      0.33,
      for(int i = 0; i < competitorCount; i++) resultWidth,
    ];

    return Scrollbar(
      thumbVisibility: true,
      controller: _scrollController,
      child: TableView.builder(
        verticalDetails: ScrollableDetails.vertical(
          controller: _scrollController,
        ),
        columnCount: columnCount,
        pinnedRowCount: 1,
        rowCount: matches.length + 1,
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
            extent: FixedTableSpanExtent(_rowHeight * uiScaleFactor),
          );
        },
        cellBuilder: (context, vicinity) {
          if(vicinity.row == 0) {
            return TableViewCell(child: Center(child: _buildHeaderCell(context, model, vicinity)));
          }
          else {
            return TableViewCell(child: Center(child: _buildCell(
              context,
              model,
              _sortedMatches,
              vicinity,
            )));
          }
        },
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, RatingComparisonModel model, TableVicinity vicinity) {
    final competitorCount = model.competitorCount;
    if(vicinity.column == 0) {
      return Text("Match Date", style: TextStyle(fontWeight: FontWeight.w500));
    }
    else if(vicinity.column == 1) {
      final filterLabel = competitorCount > 2
        ? "Tap to toggle showing only matches with all results"
        : "Tap to toggle showing only matches with both results";
      return Tooltip(
        message: filterLabel,
        child: GestureDetector(
          onTap: () {
            model.showOnlyMatchesWithAllResults = !model.showOnlyMatchesWithAllResults;
          },
          child: Text("Match Name", style: TextStyle(fontWeight: FontWeight.w500))
        ),
      );
    }
    else {
      return Text("${model.ratings[vicinity.column - 2].name}", style: TextStyle(fontWeight: FontWeight.w500));
    }
  }

  Widget _buildCell(
    BuildContext context,
    RatingComparisonModel model,
    List<ShootingMatch> matches,
    TableVicinity vicinity,
  ) {
    final match = matches[vicinity.row - 1];
    final shared = model.sharedMatchResults[match.sourceIds.first]!;

    final TextStyle? dimmedStyle = shared.hasAllResults ? null : TextStyle(color: ThemeColors.fadedTextColor(context));

    if(vicinity.column == 0) {
      return Text("${programmerYmdFormat.format(match.date)}", textAlign: TextAlign.start, style: dimmedStyle);
    }
    else if(vicinity.column == 1) {
      Division? division;
      for(var entry in shared.entries) {
        if(entry != null) {
          division = entry.divisionEntered;
          break;
        }
      }
      return ClickableLink(
        onTap: () {
          _launchScoreView(division, match);
        },
        child: Text(
          key: GlobalObjectKey(match.sourceIds.first),
          "${match.name}",
          textAlign: TextAlign.start,
          style: dimmedStyle
        ),
      );
    }
    else {
      return _buildResultCell(context, model, shared, vicinity.column - 2, dimmedStyle);
    }
  }

  Widget _buildResultCell(
    BuildContext context,
    RatingComparisonModel model,
    SharedMatchHistory shared,
    int competitorIndex,
    TextStyle? dimmedStyle,
  ) {
    final entry = shared.entries[competitorIndex];
    if(entry == null) {
      return Center(child: Text("-", style: dimmedStyle));
    }

    TextStyle? style = dimmedStyle;
    final competitorCount = model.competitorCount;

    if(competitorCount == 2 && shared.hasAllResults) {
      // Pairwise green/red winner-loser coloring.
      final otherIndex = competitorIndex == 0 ? 1 : 0;
      final other = shared.entries[otherIndex]!;
      if(entry.place < other.place) {
        style = TextStyle(color: ThemeColors.equalContrastGreen(context));
      }
      else if(entry.place > other.place) {
        style = TextStyle(color: ThemeColors.equalContrastRed(context));
      }
    }
    else if(competitorCount > 2 && shared.presentCount >= 2) {
      // Best-of-present green; others default.
      final winners = shared.bestPlaceIndices();
      if(winners.contains(competitorIndex) && winners.length < shared.presentCount) {
        style = TextStyle(color: ThemeColors.equalContrastGreen(context));
      }
    }

    return Center(child: Text("${entry.place} (${entry.displayPercentage})", style: style));
  }

  void _launchScoreView(Division? division, ShootingMatch match, {MatchStage? stage}) {
    var filters = FilterSet(match.sport, empty: true)
      ..mode = FilterMode.or;
    if(division != null) {
      filters.divisions = FilterSet.divisionListToMap(match.sport, [division]);
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return ResultPage(
        canonicalMatch: match,
        initialStage: stage,
        initialFilters: filters,
        allowWhatIf: true,
      );
    }));
  }
}
