/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/widget/captioned_text.dart';
import 'package:uspsa_result_viewer/ui/widget/score_list.dart';

class ShooterResultCard extends StatelessWidget {
  final RelativeMatchScore? matchScore;
  final RelativeScore? stageScore;
  final bool scoreDQ;

  const ShooterResultCard({Key? key, this.matchScore, this.stageScore, this.scoreDQ = true}) : super(key: key);

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
                  text: "${matchScore!.total.relativePoints.toStringAsFixed(2)} (${matchScore!.total.percent.asPercentage()}%)"
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Time",
                  text: "${matchScore!.total.score.time.toStringAsFixed(2)}s",
                )
              ],
            ),
            SizedBox(height: 10),
            MatchScoreBody(result: matchScore!.total)
          ],
        ),
      ),
    );
  }

  Widget _buildStageCard(BuildContext context) {
    Shooter shooter = stageScore!.score.shooter;
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
                    captionText: "Hit Factor",
                    text: "${stageScore!.score.getHitFactor(scoreDQ: scoreDQ).toStringAsFixed(4)}",
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Time",
                  text: "${stageScore!.score.time.toStringAsFixed(2)}s",
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Stage Score",
                  text: "${stageScore!.relativePoints.toStringAsFixed(2)} (${stageScore!.percent.asPercentage()}%)"
                )
              ],
            ),
            SizedBox(height: 10)
            ]..addAll(
              timeHolder
            )..add(
              MatchScoreBody(result: stageScore)
            ),
        ),
      ),
    );
  }


  Widget _buildShooterLink(BuildContext context, Shooter shooter) {
    if(shooter.originalMemberNumber != "") {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            HtmlOr.openLink("https://uspsa.org/classification/${shooter.originalMemberNumber}");
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${shooter.getName()} - ${shooter.division?.displayString() ?? "NO DIVISION"} ${shooter.classification.displayString()}",
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
        ),
      );
    }
    return Text(
      "${shooter.getName()} - ${shooter.division?.displayString() ?? "NO DIVISION"} ${shooter.classification.displayString()}",
      style: Theme.of(context).textTheme.headline6,
    );
  }
}

class MatchScoreBody extends StatelessWidget {
  final RawScore? result;

  const MatchScoreBody({Key? key, this.result}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CaptionedText(
              captionText: "A",
              text: "${result!.a}",
            ),
            SizedBox(width: 12),
            CaptionedText(
              captionText: "C",
              text: "${result!.c + result!.b}",
            ),
            SizedBox(width: 12),
            CaptionedText(
              captionText: "D",
              text: "${result!.d}",
            ),
            SizedBox(width: 12),
            CaptionedText(
              captionText: "M",
              text: "${result!.m}",
            ),
            SizedBox(width: 12),
            CaptionedText(
              captionText: "NS",
              text: "${result!.ns}",
            )
          ],
        ),
        SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CaptionedText(
              captionText: "Procedural",
              text: "${result!.procedural}",
            ),
            SizedBox(width: 12),
            CaptionedText(
              captionText: "Late Shot",
              text: "${result!.lateShot}",
            ),
          ]
        ),
      ],
    );
  }
}