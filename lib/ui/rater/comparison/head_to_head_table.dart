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

    final careerStats1 = model.careerStats1;
    final careerStats2 = model.careerStats2;
    final totalMatches1 = careerStats1.annualStats.map((e) => e.matchHistory).flattened.length;
    final totalMatches2 = careerStats2.annualStats.map((e) => e.matchHistory).flattened.length;
    final totalWins1 = careerStats1.annualStats.map((e) => e.matchHistory).flattened.where((e) => e.place == 1).length;
    final totalWins2 = careerStats2.annualStats.map((e) => e.matchHistory).flattened.where((e) => e.place == 1).length;
    final pairedMatchResults = model.pairedMatchResults;

    final currentRating1 = model.rating1.rating;
    final currentRating2 = model.rating2.rating;

    bool byStage = careerStats1.byStage;
    int averageWindow = byStage ? 30 : 5;
    final recentAverage1 = model.rating1.averageRating(window: averageWindow);
    final recentAverage2 = model.rating2.averageRating(window: averageWindow);
    final lifetimeAverage1 = model.rating1.averageRating(window: careerStats1.careerStats.events.length);
    final lifetimeAverage2 = model.rating2.averageRating(window: careerStats2.careerStats.events.length);

    final surname1 = model.rating1.lastName;
    final surname2 = model.rating2.lastName;

    final headToHeadMatches = pairedMatchResults.values.where((e) => e.hasBothResults).toList();
    final headToHead1Wins = pairedMatchResults.values
      .where((e) => e.hasBothResults)
      .where((e) => e.match1!.place < e.match2!.place)
      .length;

    final fR = model.rating1.formatNumericRating;
    // final fRc = model.rating1.formatNumericRatingChange;

    const columnWidths = [0.55, 0.45];
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
      cells: [
        [
          TableViewCell(child: _LeftAlignedText(text: "Stat", style: TextStyle(fontWeight: FontWeight.w500))),
          TableViewCell(child: _RightAlignedText(text: "$surname1/$surname2", style: TextStyle(fontWeight: FontWeight.w500))),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Head to head matches")),
          TableViewCell(child: _RightAlignedText(text: "${headToHeadMatches.length}")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Head to head wins")),
          TableViewCell(child: _RightAlignedText(text: "$headToHead1Wins/${headToHeadMatches.length - headToHead1Wins}")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Total matches")),
          TableViewCell(child: _RightAlignedText(text: "$totalMatches1/$totalMatches2")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Total wins")),
          TableViewCell(child: _RightAlignedText(text: "$totalWins1/$totalWins2")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Current rating")),
          TableViewCell(child: _RightAlignedText(text: "${fR(currentRating1)}/${fR(currentRating2)}")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Recent average")),
          TableViewCell(child: _RightAlignedText(text: "${fR(recentAverage1.averageOfIntermediates)}/${fR(recentAverage2.averageOfIntermediates)}")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "Career peak")),
          TableViewCell(child: _RightAlignedText(text: "${fR(lifetimeAverage1.maxRating)}/${fR(lifetimeAverage2.maxRating)}")),
        ],
        if(model.rating1.sport.type.isHitFactor || model.rating1.sport.type == SportType.icore) [
          TableViewCell(child: _LeftAlignedText(text: "Alpha percentage")),
          TableViewCell(child: _RightAlignedText(text: "${careerStats1.careerStats.totalScore?.hitPercentagesText(model.rating1.sport, bestOnly: true)}/${careerStats2.careerStats.totalScore?.hitPercentagesText(model.rating2.sport, bestOnly: true)}")),
        ],
        [
          TableViewCell(child: _LeftAlignedText(text: "DQs")),
          TableViewCell(child: _RightAlignedText(text: "${careerStats1.careerStats.dqs.length}/${careerStats2.careerStats.dqs.length}")),
        ]
      ],
    );
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