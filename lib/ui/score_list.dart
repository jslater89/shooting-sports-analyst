import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';
import 'package:uspsa_result_viewer/ui/shooter_card.dart';

class ScoreList extends StatelessWidget {
  final PracticalMatch match;
  final Stage stage;
  final List<RelativeMatchScore> baseScores;
  final List<RelativeMatchScore> filteredScores;
  final double minWidth;

  const ScoreList({Key key, @required this.match, @required this.stage, @required this.baseScores, @required this.filteredScores, this.minWidth = 1024}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget keyWidget;

    var screenSize = MediaQuery.of(context).size;
    var maxWidth = screenSize.width;

    if(match == null) {
      keyWidget = Container();
    }
    else {
      keyWidget = stage == null ? _buildMatchScoreKey(screenSize) : _buildStageScoreKey(screenSize);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: max(maxWidth, minWidth),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            keyWidget,
            Expanded(child: ListView.builder(
                itemCount: (filteredScores?.length ?? 0),
                itemBuilder: (ctx, i) {
                  if(stage == null) return _buildMatchScoreRow(index: i, context: context);
                  else return _buildStageScoreRow(context, i, stage);
                }
            )),
          ],
        ),
      ),
    );
  }


  Widget _buildMatchScoreKey(Size screenSize) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: max(screenSize.width, minWidth)
      ),
      child: Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide()
            ),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(flex: 1, child: Text("Row")),
                Expanded(flex: 1, child: Text("Place")),
                Expanded(flex: 3, child: Text("Name")),
                Expanded(flex: 1, child: Text("Class")),
                Expanded(flex: 3, child: Text("Division")),
                Expanded(flex: 1, child: Text("PF")),
                Expanded(flex: 2, child: Text("Match %")),
                Expanded(flex: 2, child: Text("Match Pts.")),
                Expanded(flex: 2, child: Text("Time")),
                Expanded(flex: 3, child: Tooltip(
                    message: "The number of points out of the maximum possible for this stage.",
                    child: Text("Points/${match.maxPoints}"))
                ),
                Expanded(flex: 5, child: Text("Hits")),
              ],
            ),
          )
      ),
    );
  }

  Widget _buildMatchScoreRow({BuildContext context, int index}) {
    var score = filteredScores[index];
    return GestureDetector(
      onTap: () {
        showDialog(context: context, builder: (context) {
          return ShooterResultCard(matchScore: score,);
        });
      },
      child: ScoreRow(
        color: index % 2 == 1 ? Colors.grey[200] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text("${baseScores.indexOf(score) + 1}")),
              Expanded(flex: 1, child: Text("${score.total.place}")),
              Expanded(flex: 3, child: Text(score.shooter.getName())),
              Expanded(flex: 1, child: Text(score.shooter.classification.displayString())),
              Expanded(flex: 3, child: Text(score.shooter.division.displayString())),
              Expanded(flex: 1, child: Text(score.shooter.powerFactor.shortString())),
              Expanded(flex: 2, child: Text((score.total.percent * 100).toStringAsFixed(2))),
              Expanded(flex: 2, child: Text(score.total.relativePoints.toStringAsFixed(2))),
              Expanded(flex: 2, child: Text(score.total.score.time.toStringAsFixed(2))),
              Expanded(flex: 3, child: Text("${score.total.score.totalPoints} (${(score.percentTotalPoints * 100).toStringAsFixed(2)}%)")),
              Expanded(flex: 5, child: Text("${score.total.score.a}A ${score.total.score.c}C ${score.total.score.d}D ${score.total.score.m}M ${score.total.score.ns}NS ${score.total.score.penaltyCount}P")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageScoreKey(Size screenSize) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: max(screenSize.width, minWidth)
      ),
      child: Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide()
            ),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text("Row")),
                Expanded(flex: 1, child: Text("Place")),
                Expanded(flex: 3, child: Text("Name")),
                Expanded(flex: 1, child: Text("Class")),
                Expanded(flex: 3, child: Text("Division")),
                Expanded(flex: 1, child: Text("PF")),
                Expanded(flex: 3, child: Tooltip(
                    message: "The number of points out of the maximum possible for this stage.",
                    child: Text("Points/${stage.maxPoints}"))
                ),
                Expanded(flex: 2, child: Text("Time")),
                Expanded(flex: 2, child: Text("Hit Factor")),
                Expanded(flex: 2, child: Text("Stage %")),
                Expanded(flex: 2, child: Text("Match Pts.")),
                Expanded(flex: 4, child: Text("Hits")),
              ],
            ),
          )
      ),
    );
  }
  Widget _buildStageScoreRow(BuildContext context, int i, Stage stage) {

    var matchScore = filteredScores[i];
    var stageScore = filteredScores[i].stageScores[stage];

    return GestureDetector(
      onTap: () {
        showDialog(context: context, builder: (context) {
          return ShooterResultCard(stageScore: stageScore,);
        });
      },
      child: ScoreRow(
        color: i % 2 == 1 ? Colors.grey[200] : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text("${baseScores.indexOf(matchScore) + 1}")),
              Expanded(flex: 1, child: Text("${stageScore.place}")),
              Expanded(flex: 3, child: Text(matchScore.shooter.getName())),
              Expanded(flex: 1, child: Text(matchScore.shooter.classification.displayString())),
              Expanded(flex: 3, child: Text(matchScore.shooter.division.displayString())),
              Expanded(flex: 1, child: Text(matchScore.shooter.powerFactor.shortString())),
              Expanded(flex: 3, child: Text("${stageScore.score.totalPoints} (${(stageScore.score.percentTotalPoints * 100).toStringAsFixed(1)}%)")),
              Expanded(flex: 2, child: Text(stageScore.score.time.toStringAsFixed(2))),
              Expanded(flex: 2, child: Text(stageScore.score.hitFactor.toStringAsFixed(4))),
              Expanded(flex: 2, child: Text((stageScore.percent * 100).toStringAsFixed(2))),
              Expanded(flex: 2, child: Text(stageScore.relativePoints.toStringAsFixed(2))),
              Expanded(flex: 4, child: Text("${stageScore.score.a}A ${stageScore.score.c}C ${stageScore.score.d}D ${stageScore.score.m}M ${stageScore.score.ns}NS ${stageScore.score.penaltyCount}P")),
            ],
          ),
        ),
      ),
    );
  }


}

