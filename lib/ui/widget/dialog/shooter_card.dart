/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/ui/widget/captioned_text.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/score_list.dart';
import 'package:shooting_sports_analyst/util.dart';

class ShooterResultCard extends StatelessWidget {
  final Sport sport;
  final RelativeMatchScore? matchScore;
  final RelativeStageScore? stageScore;
  final bool scoreDQ;

  const ShooterResultCard({Key? key, required this.sport,this.matchScore, this.stageScore, this.scoreDQ = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if(matchScore == null && stageScore == null) {
      throw FlutterError("Match score and stage score both null");
    }
    if(matchScore != null && stageScore != null) {
      throw FlutterError("Match score and stage score both provided");
    }

    if(matchScore != null) return _buildMatchCard(context);
    else return _buildStageCard(context);
  }

  Widget _buildMatchCard(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildShooterLink(context, matchScore!.shooter),
            SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CaptionedText(
                  captionText: "Match Score",
                  text: "${matchScore!.points.toStringAsFixed(2)} (${matchScore!.ratio.asPercentage()}%)"
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Time",
                  text: "${matchScore!.total.finalTime.toStringAsFixed(2)}s",
                )
              ],
            ),
            SizedBox(height: 10),
            MatchScoreBody(result: matchScore!.total, powerFactor: matchScore!.shooter.powerFactor),
          ],
        ),
      ),
    );
  }

  Widget _buildStageCard(BuildContext context) {
    MatchEntry shooter = stageScore!.shooter;
    List<Widget> timeHolder = [];
    var stringTimes = stageScore!.score.stringTimes;

    if(stringTimes.length > 1) {
      List<Widget> children = [];
      int stringNum = 1;
      for(double time in stringTimes) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: CaptionedText(
            captionText: "String ${stringNum++}",
            text: time.toStringAsFixed(2),
          ),
        ));
      }
      timeHolder = [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: children,
        ),
        SizedBox(height: 10),
      ];
    }

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildShooterLink(context, shooter),
            SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CaptionedText(
                    captionText: stageScore!.score.displayLabel,
                    text: stageScore!.score.displayString,
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Time",
                  text: "${stageScore!.score.finalTime.toStringAsFixed(2)}s",
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Stage Score",
                  text: "${stageScore!.points.toStringAsFixed(2)} (${stageScore!.ratio.asPercentage()}%)"
                )
              ],
            ),
            SizedBox(height: 10)
            ]..addAll(
              timeHolder
            )..add(
              MatchScoreBody(result: stageScore!.score, powerFactor: stageScore!.shooter.powerFactor),
            ),
        ),
      ),
    );
  }


  Widget _buildShooterLink(BuildContext context, MatchEntry shooter) {
    var shooterString = shooter.name;
    if(sport.hasDivisions || sport.hasClassifications) {
      shooterString += " -";
      if(sport.hasDivisions) {
        shooterString += " ${shooter.division?.name ?? "NO DIVISION"} ";
      }
      if(sport.hasClassifications) {
        shooterString += " ${shooter.classification?.name ?? "NO CLASSIFICATION"}";
      }
    }
    if(shooter.originalMemberNumber != "") {
      return ClickableLink(
        url: Uri.parse("https://uspsa.org/classification/${shooter.originalMemberNumber}"),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shooterString,
              style: Theme.of(context).textTheme.headline6!.copyWith(
                color: Theme.of(context).primaryColor,
                decoration: TextDecoration.underline,
              ),
            ),
            IconButton(
              icon: Icon(Icons.compare_arrows),
              onPressed: () {
                Navigator.of(context).pop(ShooterDialogAction(launchComparison: true));
              },
            ),
          ],
        ),
      );
    }
    return Text(
      shooterString,
      style: Theme.of(context).textTheme.headline6,
    );
  }
}

class MatchScoreBody extends StatelessWidget {
  final RawScore result;
  final PowerFactor powerFactor;

  const MatchScoreBody({Key? key, required this.result, required this.powerFactor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<Widget> scoreText = [];
    for(var e in powerFactor.targetEvents.values) {
      scoreText.add(CaptionedText(
        captionText: e.name,
        text: "${result.targetEvents[e] ?? 0}",
      ));
      scoreText.add(SizedBox(width: 12));
    }
    if(scoreText.isNotEmpty) scoreText.removeLast();

    List<Widget> penaltyText = [];
    for(var e in powerFactor.penaltyEvents.values) {
      penaltyText.add(CaptionedText(
        captionText: e.name,
        text: "${result.targetEvents[e] ?? 0}",
      ));
      penaltyText.add(SizedBox(width: 12));
    }
    if(penaltyText.isNotEmpty) penaltyText.removeLast();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: scoreText,
        ),
        SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: penaltyText,
        ),
      ],
    );
  }
}