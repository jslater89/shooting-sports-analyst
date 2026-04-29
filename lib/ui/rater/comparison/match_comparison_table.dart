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

  late final double _uiScaleFactor;
  final double _rowHeight = 40;

  List<ShootingMatch> _sortedMatches = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;

    context.read<RatingComparisonModel>().addListener(_updateHighlightedMatch);
  }

  String? _lastHighlightedMatchId;
  void _updateHighlightedMatch() {
    final model = context.read<RatingComparisonModel>();
    final highlightedMatchId = model.highlightedMatchId;
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<RatingComparisonModel>(context);


    final matches = model.pairedMatchResults.values.map((e) => e.match).nonNulls.toList();

    _sortedMatches = matches..sort(ShootingMatch.dateComparator);
    final _uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;

    const columnWidths = [0.20, 0.10, 0.50, 0.20];

    return Scrollbar(
      thumbVisibility: true,
      controller: _scrollController,
      child: TableView.builder(
        verticalDetails: ScrollableDetails.vertical(
          controller: _scrollController,
        ),
        // 3 columns: result 1 or n/a, match date, match name, result 2 or n/a
        columnCount: 4,
        pinnedRowCount: 1,
        // plus one for the header row
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
                  width: 1 * _uiScaleFactor,
                ),
              ),
            );
          }
          else {
            decoration = TableSpanDecoration(
              border: TableSpanBorder(
                trailing: BorderSide(
                  color: ThemeColors.onBackgroundColorFaded(context),
                  width: 1 * _uiScaleFactor,
                ),
              ),
            );
          }
          return TableSpan(
            backgroundDecoration: decoration,
            extent: FixedTableSpanExtent(_rowHeight * _uiScaleFactor),
          );
        },
        cellBuilder: (context, vicinity) {
          if(vicinity.row == 0) {
            return Center(child: _buildHeaderCell(context, model, vicinity));
          }
          else {
            return Center(child: _buildCell(
              context,
              model,
              _sortedMatches,
              vicinity,
              model.pairedMatchResults,
            ));
          }
        },
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, RatingComparisonModel model, TableVicinity vicinity) {
    if(vicinity.column == 0) {
      return Text("${model.rating1.name}", style: TextStyle(fontWeight: FontWeight.w500));
    }
    else if(vicinity.column == 1) {
      return Text("Match Date", style: TextStyle(fontWeight: FontWeight.w500));
    }
    else if(vicinity.column == 2) {
      return Text("Match Name", style: TextStyle(fontWeight: FontWeight.w500));
    }
    else {
      return Text("${model.rating2.name}", style: TextStyle(fontWeight: FontWeight.w500));
    }
  }

  Widget _buildCell(
    BuildContext context,
    RatingComparisonModel model,
    List<ShootingMatch> matches,
    TableVicinity vicinity,
    Map<String, PairedMatchHistory> pairedMatchResults,
  ) {
    final match = matches[vicinity.row - 1];
    final pairedResult = pairedMatchResults[match.sourceIds.first];

    final TextStyle? dimmedStyle = pairedResult!.hasBothResults ? null : TextStyle(color: ThemeColors.fadedTextColor(context));

    // Null if it's not head to head, true if head to head and rating1 wins, false if head to head and rating2 wins.
    bool? rating1Wins;
    if(pairedResult.hasBothResults) {
      if(pairedResult.match1!.place < pairedResult.match2!.place) {
        rating1Wins = true;
      }
      else if(pairedResult.match1!.place > pairedResult.match2!.place) {
        rating1Wins = false;
      }
    }

    if(vicinity.column == 0) {
      TextStyle? style = dimmedStyle;
      if(rating1Wins == true) {
        style = TextStyle(color: ThemeColors.equalContrastGreen(context));
      }
      else if(rating1Wins == false) {
        style = TextStyle(color: ThemeColors.equalContrastRed(context));
      }
      if(pairedResult.match1 != null) {
        return Center(child: Text("${pairedResult.match1!.place} (${pairedResult.match1!.displayPercentage})", style: style));
      }
      else {
        return Center(child: Text("-", style: style));
      }
    }
    else if(vicinity.column == 1) {
      return Text("${programmerYmdFormat.format(match.date)}", textAlign: TextAlign.start, style: dimmedStyle);
    }
    else if(vicinity.column == 2) {
      return ClickableLink(
        onTap: () {
          _launchScoreView(pairedResult.match1?.divisionEntered, match);
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
      TextStyle? style = dimmedStyle;
      if(pairedResult.match2 != null) {
        if(rating1Wins == false) {
          style = TextStyle(color: ThemeColors.equalContrastGreen(context));
        }
        else if(rating1Wins == true) {
          style = TextStyle(color: ThemeColors.equalContrastRed(context));
        }
        return Center(child: Text("${pairedResult.match2!.place} (${pairedResult.match2!.displayPercentage})", style: style));
      }
      else {
        return Center(child: Text("-", style: style));
      }
    }
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
