import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/ui/editable_shooter_card.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';
import 'package:uspsa_result_viewer/ui/shooter_card.dart';

class ScoreList extends StatelessWidget {
  final PracticalMatch? match;
  final int? maxPoints;
  final Stage? stage;
  final List<RelativeMatchScore> baseScores;
  final List<RelativeMatchScore> filteredScores;
  final bool scoreDQ;
  final double minWidth;
  final ScrollController? horizontalScrollController;
  final ScrollController? verticalScrollController;
  final Function(Shooter, Stage?, bool wholeMatch) onScoreEdited;
  final List<Shooter> editedShooters;
  final bool whatIfMode;

  const ScoreList({
    Key? key,
    required this.match,
    required this.stage,
    required this.baseScores,
    required this.filteredScores,
    this.maxPoints,
    this.minWidth = 1024,
    this.verticalScrollController,
    this.horizontalScrollController,
    this.scoreDQ = true,
    required this.onScoreEdited,
    this.whatIfMode = false,
    this.editedShooters = const [],
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget keyWidget;

    int? displayMaxPoints = maxPoints;
    if(maxPoints == null) displayMaxPoints = match!.maxPoints;

    var screenSize = MediaQuery.of(context).size;
    var maxWidth = screenSize.width;

    if(match == null) {
      keyWidget = Container();
    }
    else {
      keyWidget = stage == null ? _buildMatchScoreKey(screenSize, displayMaxPoints) : _buildStageScoreKey(screenSize);
    }

    return SingleChildScrollView(
      controller: horizontalScrollController,
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: max(maxWidth, minWidth),
        ),
        child: GestureDetector(
          onPanUpdate: (details) {
            if(horizontalScrollController != null) {
              _adjustScroll(horizontalScrollController!, amount: -details.delta.dx);
            }
            if(verticalScrollController != null) {
              _adjustScroll(verticalScrollController!, amount: -details.delta.dy);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              keyWidget,
              Expanded(child: Scrollbar(
                thumbVisibility: true,
                controller: verticalScrollController,
                child: ListView.builder(
                  controller: verticalScrollController,
                  itemCount: (filteredScores.length),
                  itemBuilder: (ctx, i) {
                    if(stage == null) return _buildMatchScoreRow(index: i, context: context);
                    else if(stage != null) return _buildStageScoreRow(context, i, stage!);
                    else return Container();
                  }
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildMatchScoreKey(Size screenSize, int? maxPoints) {
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
                    child: Text("Points/$maxPoints"))
                ),
                Expanded(flex: 5, child: Text("Hits")),
              ],
            ),
          )
      ),
    );
  }

  Widget _buildMatchScoreRow({required BuildContext context, required int index}) {
    var score = filteredScores[index];
    return GestureDetector(
      onTap: () async {
        if(whatIfMode) {
          var scoreEdit = await (showDialog<ScoreEdit>(context: context, barrierDismissible: false, builder: (context) {
            return EditableShooterCard(matchScore: score, scoreDQ: scoreDQ,);
          })) ?? null;

          if(scoreEdit != null && scoreEdit.rescore) {
            // Any edits from here are always going to be whole-match changes
            onScoreEdited(score.shooter, null, true);
          }
        }
        else {
          showDialog(context: context, builder: (context) {
            return ShooterResultCard(matchScore: score, scoreDQ: scoreDQ,);
          });
        }
      },
      child: ScoreRow(
        color: index % 2 == 1 ? Colors.grey[200] : Colors.white,
        edited: editedShooters.contains(score.shooter),
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
              Expanded(flex: 2, child: Text("${score.total.percent.asPercentage()}%")),
              Expanded(flex: 2, child: Text(score.total.relativePoints.toStringAsFixed(2))),
              Expanded(flex: 2, child: Text(score.total.score.time.toStringAsFixed(2))),
              Expanded(flex: 3, child: Text("${score.total.score.getTotalPoints(scoreDQ: scoreDQ)} (${score.percentTotalPoints.asPercentage()}%)")),
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
                    child: Text("Points/${stage!.maxPoints}"))
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
      onTap: () async {
        if(whatIfMode) {
          var scoreEdit = await (showDialog<ScoreEdit>(context: context, barrierDismissible: false, builder: (context) {
            return EditableShooterCard(stageScore: stageScore, scoreDQ: scoreDQ,);
          })) ?? null;

          if(scoreEdit != null && scoreEdit.rescore) {
            onScoreEdited(matchScore.shooter, stage, scoreEdit.wholeMatch);
          }
        }
        else {
          showDialog(context: context, builder: (context) {
            return ShooterResultCard(stageScore: stageScore, scoreDQ: scoreDQ,);
          });
        }
      },
      child: ScoreRow(
        color: i % 2 == 1 ? Colors.grey[200] : Colors.white,
        edited: editedShooters.contains(matchScore.shooter),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text("${baseScores.indexOf(matchScore) + 1}")),
              Expanded(flex: 1, child: Text("${stageScore?.place}")),
              Expanded(flex: 3, child: Text(matchScore.shooter.getName())),
              Expanded(flex: 1, child: Text(matchScore.shooter.classification.displayString())),
              Expanded(flex: 3, child: Text(matchScore.shooter.division.displayString())),
              Expanded(flex: 1, child: Text(matchScore.shooter.powerFactor.shortString())),
              Expanded(flex: 3, child: Text("${stageScore?.score.getTotalPoints(scoreDQ: scoreDQ)} (${((stageScore?.score.getPercentTotalPoints(scoreDQ: scoreDQ) ?? 0).asPercentage(decimals: 1))}%)")),
              Expanded(flex: 2, child: Text(stageScore?.score.time.toStringAsFixed(2) ?? "0.00")),
              Expanded(flex: 2, child: Text(stageScore?.score.getHitFactor(scoreDQ: scoreDQ).toStringAsFixed(4) ?? "0.0000")),
              Expanded(flex: 2, child: Text("${stageScore?.percent.asPercentage() ?? "0.00"}%")),
              Expanded(flex: 2, child: Text(stageScore?.relativePoints.toStringAsFixed(2) ?? "0.00")),
              Expanded(flex: 4, child: Text("${stageScore?.score.a}A ${stageScore?.score.c}C ${stageScore?.score.d}D ${stageScore?.score.m}M ${stageScore?.score.ns}NS ${stageScore?.score.penaltyCount}P")),
            ],
          ),
        ),
      ),
    );
  }

  void _adjustScroll(ScrollController c, {required double amount}) {
    // Clamp to in-range values to prevent jumping on arrow key presses
    double newPosition = c.offset + amount;
    newPosition = max(newPosition, 0);
    newPosition = min(newPosition, c.position.maxScrollExtent);

    c.jumpTo(newPosition);
  }
}

