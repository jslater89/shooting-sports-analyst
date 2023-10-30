/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/route/compare_shooter_results.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/editable_shooter_card.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/shooter_card.dart';
import 'package:uspsa_result_viewer/util.dart';
import 'package:uspsa_result_viewer/data/model.dart' as old;

class ScoreList extends StatelessWidget {
  final ShootingMatch? match;
  final int? maxPoints;
  final MatchStage? stage;
  final List<RelativeMatchScore> baseScores;
  final List<RelativeMatchScore> filteredScores;
  final bool scoreDQ;
  final double minWidth;
  final ScrollController? horizontalScrollController;
  final ScrollController? verticalScrollController;
  final Function(MatchEntry, MatchStage?, bool wholeMatch) onScoreEdited;
  final List<MatchEntry> editedShooters;
  final bool whatIfMode;
  final Map<RaterGroup, Rater>? ratings;

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
    this.ratings,
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
                if(ratings != null) Consumer<ScoreDisplaySettingsModel>(
                    builder: (context, model, _) {
                      var message;
                      switch(model.value.ratingMode) {
                        case RatingDisplayMode.preMatch:
                          message = "The shooter's rating prior to this match.";
                          break;
                        case RatingDisplayMode.postMatch:
                          message = "The shooter's rating after this match.";
                          break;
                        case RatingDisplayMode.change:
                          message = "The shooter's change in rating at this match.";
                          break;
                      }
                      return Expanded(flex: 1, child: Tooltip(
                        message: message,
                        child: Text("Rating"),
                      ));
                    }
                ),
                Expanded(flex: 1, child: Text("Class")),
                Expanded(flex: 2, child: Text("Division")),
                Expanded(flex: 1, child: Text("PF")),
                Expanded(flex: 2, child: Text("Match %")),
                Expanded(flex: 2, child: Text("Match Pts.")),
                if(match?.inProgress ?? false) Expanded(flex: 1, child: Text("Through", textAlign: TextAlign.end)),
                if(match?.inProgress ?? false) SizedBox(width: 15),
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
    var stagesComplete = 0;
    if(match?.inProgress ?? false) {
      stagesComplete = score.stageScores.values.where((element) => !element.score.dnf).length;
    }

    return GestureDetector(
      onTap: () async {
        if(whatIfMode) {
          var action = await (showDialog<ShooterDialogAction>(context: context, barrierDismissible: false, builder: (context) {
            return EditableShooterCard(sport: match!.sport, matchScore: score, scoreDQ: scoreDQ);
          }));

          if(action != null) {
            if(action.scoreEdit.rescore) {
              // Any edits from here are always going to be whole-match changes
              onScoreEdited(score.shooter, null, true);
            }
            if(action.launchComparison) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => CompareShooterResultsPage(
                  scores: baseScores,
                  initialShooters: [score.shooter],
                )
              ));
            }
          }
        }
        else {
          var action = await showDialog<ShooterDialogAction>(context: context, builder: (context) {
            return ShooterResultCard(matchScore: score, scoreDQ: scoreDQ,);
          });

          if(action != null && action.launchComparison) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => CompareShooterResultsPage(
                  scores: baseScores,
                  initialShooters: [score.shooter],
                )
            ));
          }
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
              Expanded(flex: 1, child: Text("${score.place}")),
              Expanded(flex: 3, child: Text(score.shooter.getName())),
              if(ratings != null) Consumer<ScoreDisplaySettingsModel>(
                builder: (context, model, _) {
                  String text = "n/a";
                  // TODO: restore when ratings are converted
                  // switch(model.value.ratingMode) {
                  //   case RatingDisplayMode.preMatch:
                  //     var rating = ratings!.lookup(score.shooter)?.ratingForEvent(match!, null, beforeMatch: true).round();
                  //     if(rating != null) text = rating.toString();
                  //     break;
                  //   case RatingDisplayMode.postMatch:
                  //     var rating = ratings!.lookup(score.shooter)?.ratingForEvent(match!, null, beforeMatch: false).round();
                  //     if(rating != null) text = rating.toString();
                  //     break;
                  //   case RatingDisplayMode.change:
                  //     var rating = ratings!.lookup(score.shooter)?.changeForEvent(match!, null);
                  //     if(rating != null) text = rating.toStringAsFixed(1);
                  //     break;
                  // }
                  return Expanded(flex: 1, child: Text(text));
                }
              ),
              Expanded(flex: 1, child: Text(score.shooter.classification?.shortName ?? "UNK")),
              Expanded(flex: 2, child: Text(score.shooter.division?.shortName ?? "NO DIVISION")),
              Expanded(flex: 1, child: Text(score.shooter.powerFactor.shortName)),
              Expanded(flex: 2, child: Text("${score.ratio.asPercentage()}%")),
              Expanded(flex: 2, child: Text(score.points.toStringAsFixed(2))),
              if(match?.inProgress ?? false) Expanded(flex: 1, child: Text("$stagesComplete", textAlign: TextAlign.end)),
              if(match?.inProgress ?? false) SizedBox(width: 15),
              Expanded(flex: 2, child: Text(score.total.finalTime.toStringAsFixed(2))),
              Consumer<ScoreDisplaySettingsModel>(
                builder: (context, model, _) {
                  if(model.value.fixedTimeAvailablePointsFromDivisionMax) {
                    Map<MatchStage, int> stageMax = {};
                    for(var s in score.stageScores.keys) {
                      // TODO: 'and this is a USPSA-style fixed time stage' via match.sport.matchScoring
                      if(s.scoring is PointsScoring) {
                        var bestPoints = 0;
                        for(var score in baseScores) {
                          if(score.stageScores[s] != null && score.stageScores[s]!.score.points > bestPoints) {
                            bestPoints = score.stageScores[s]!.score.points;
                          }
                        }
                        stageMax[s] = bestPoints;
                      }
                    }
                    return Expanded(flex: 3, child: Text("${score.total.getTotalPoints(scoreDQ: scoreDQ, countPenalties: model.value.availablePointsCountPenalties)} "
                        "(${score.percentTotalPointsWithSettings(scoreDQ: true, countPenalties: model.value.availablePointsCountPenalties, stageMaxPoints: stageMax).asPercentage()}%)"));
                  }
                  else {
                    return Expanded(flex: 3, child: Text("${score.total.score.getTotalPoints(scoreDQ: scoreDQ, countPenalties: model.value.availablePointsCountPenalties)} "
                        "(${score.percentTotalPointsWithSettings(scoreDQ: true, countPenalties: model.value.availablePointsCountPenalties).asPercentage()}%)"));
                  }
                },
              ),
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
                if(ratings != null) Consumer<ScoreDisplaySettingsModel>(
                  builder: (context, model, _) {
                    var message;
                    switch(model.value.ratingMode) {
                      case RatingDisplayMode.preMatch:
                        message = "The shooter's rating prior to this match.";
                        break;
                      case RatingDisplayMode.postMatch:
                        message = "The shooter's rating after this match.";
                        break;
                      case RatingDisplayMode.change:
                        message = "The shooter's change in rating on this stage.";
                        break;
                    }
                    return Expanded(flex: 1, child: Tooltip(
                      message: message,
                      child: Text("Rating"),
                    ));
                  }
                ),
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
  Widget _buildStageScoreRow(BuildContext context, int i, MatchStage stage) {
    var matchScore = filteredScores[i];
    var stageScore = filteredScores[i].stageScores[stage];

    return GestureDetector(
      onTap: () async {
        if(whatIfMode) {
          var action = await (showDialog<ShooterDialogAction>(context: context, barrierDismissible: false, builder: (context) {
            return EditableShooterCard(sport: match!.sport, stageScore: stageScore, scoreDQ: scoreDQ,);
          }));

          if(action != null) {
            if (action.scoreEdit.rescore) {
              onScoreEdited(matchScore.shooter, stage, action.scoreEdit.wholeMatch);
            }
            if (action.launchComparison) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CompareShooterResultsPage(
                    scores: baseScores,
                    initialShooters: [matchScore.shooter],
                  )
                )
              );
            }
          }
        }
        else {
          var action = await showDialog<ShooterDialogAction>(context: context, builder: (context) {
            return ShooterResultCard(stageScore: stageScore, scoreDQ: scoreDQ,);
          });

          if(action != null && action.launchComparison) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => CompareShooterResultsPage(
                  scores: baseScores,
                  initialShooters: [matchScore.shooter],
                )
            ));
          }
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
              if(ratings != null) Consumer<ScoreDisplaySettingsModel>(
                  builder: (context, model, _) {
                    String text = "n/a";
                    // TODO: restore when ratings are converted
                    // switch(model.value.ratingMode) {
                    //   case RatingDisplayMode.preMatch:
                    //     var rating = ratings!.lookup(matchScore.shooter)?.ratingForEvent(match!, null, beforeMatch: true).round();
                    //     if(rating != null) text = rating.toString();
                    //     break;
                    //   case RatingDisplayMode.postMatch:
                    //     var rating = ratings!.lookup(matchScore.shooter)?.ratingForEvent(match!, null, beforeMatch: false).round();
                    //     if(rating != null) text = rating.toString();
                    //     break;
                    //   case RatingDisplayMode.change:
                    //     var rating = ratings!.lookup(matchScore.shooter)?.changeForEvent(match!, stage);
                    //     if(rating != null) text = rating.toStringAsFixed(1);
                    //     break;
                    // }
                    return Expanded(flex: 1, child: Text(text));
                  }
              ),
              Expanded(flex: 1, child: Text(matchScore.shooter.classification?.shortName ?? "UNK")),
              Expanded(flex: 3, child: Text(matchScore.shooter.division?.shortName ?? "NO DIVISION")),
              Expanded(flex: 1, child: Text(matchScore.shooter.powerFactor.shortName)),
              Consumer<ScoreDisplaySettingsModel>(
                builder: (context, model, _) {
                  if(model.value.fixedTimeAvailablePointsFromDivisionMax) {
                    int maxPoints = 0;
                    // TODO: 'and this is a USPSA-style fixed time stage' via match.sport.matchScoring
                    if(stageScore!.score.scoring is PointsScoring) {
                      for(var score in baseScores) {
                        if(score.stageScores[stage] != null && score.stageScores[stage]!.score.rawPoints > maxPoints) {
                          maxPoints = score.stageScores[stage]!.score.rawPoints;
                        }
                      }
                    }
                    else {
                      maxPoints = stage.maxPoints;
                    }

                    return Expanded(flex: 3, child: Text("${stageScore.score.getTotalPoints(scoreDQ: scoreDQ, countPenalties: model.value.availablePointsCountPenalties)} "
                        "(${((stageScore.score.getPercentTotalPoints(scoreDQ: scoreDQ, countPenalties: model.value.availablePointsCountPenalties, maxPoints: maxPoints)).asPercentage(decimals: 1))}%)"));
                  }
                  else {
                    return Expanded(flex: 3, child: Text("${stageScore?.score.getTotalPoints(scoreDQ: scoreDQ)} "
                        "(${((stageScore?.score.getPercentTotalPoints(scoreDQ: scoreDQ, countPenalties: model.value.availablePointsCountPenalties) ?? 0).asPercentage(decimals: 1))}%)"));
                  }
                },
              ),
              Expanded(flex: 2, child: Text(stageScore?.score.finalTime.toStringAsFixed(2) ?? "0.00")),
              Expanded(flex: 2, child: Text(stageScore?.score.getHitFactor(scoreDQ: scoreDQ).toStringAsFixed(4) ?? "0.0000")),
              Expanded(flex: 2, child: Text("${stageScore?.ratio.asPercentage() ?? "0.00"}%")),
              Expanded(flex: 2, child: Text(stageScore?.points.toStringAsFixed(2) ?? "0.00")),
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

extension LookupShooterRating on Map<RaterGroup, Rater> {
  ShooterRating? lookup(old.Shooter s) {
    // TODO: fix when raters are converted
    // for(var group in this.keys) {
    //   if(group.divisions.contains(s.division)) {
    //     return this[group]!.ratingFor(s);
    //   }
    // }

    return null;
  }

  double? lookupRating({required Shooter shooter, RatingDisplayMode mode = RatingDisplayMode.preMatch, required ShootingMatch match}) {
    // TODO: fix when ratings are converted
    // switch(mode) {
    //   case RatingDisplayMode.preMatch:
    //     var rating = this.lookup(shooter)?.ratingForEvent(match, null, beforeMatch: true);
    //     return rating;
    //   case RatingDisplayMode.postMatch:
    //     var rating = this.lookup(shooter)?.ratingForEvent(match, null, beforeMatch: false);
    //     return rating;
    //   case RatingDisplayMode.change:
    //     var rating = this.lookup(shooter)?.changeForEvent(match, null);
    //     return rating;
    // }
    return null;
  }

  Rater? lookupRater(old.Shooter shooter) {
    // TODO: fix when ratings are converted
    // for(var group in this.keys) {
    //   if(group.divisions.contains(shooter.division)) {
    //     return this[group]!;
    //   }
    // }

    return null;
  }
}

class ShooterDialogAction {
  bool launchComparison;
  ScoreEdit scoreEdit;

  ShooterDialogAction({
    this.launchComparison = false,
    this.scoreEdit = const ScoreEdit.empty(),
  });
}