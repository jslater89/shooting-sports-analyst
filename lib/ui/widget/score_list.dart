/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/route/compare_shooter_results.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/editable_shooter_card.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/shooter_card.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:shooting_sports_analyst/data/model.dart' as old;

class ScoreList extends StatefulWidget {
  final ShootingMatch? match;
  final Map<MatchEntry, FantasyScore>? fantasyScores;
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
  final RatingDataSource? ratings;

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
    this.fantasyScores,
  }) : super(key: key);

  @override
  State<ScoreList> createState() => _ScoreListState();
}

class _ScoreListState extends State<ScoreList> {
  // Will only be used once match is no longer null
  Sport get sport => widget.match!.sport;

  Map<Shooter, FantasyScore>? get fantasyScores => widget.fantasyScores;

  ChangeNotifierRatingDataSource? ratingCache;

  @override
  void initState() {
    super.initState();

    if(widget.ratings != null) {
      ratingCache = ChangeNotifierRatingDataSource(widget.ratings!);
      ratingCache!.addListener(() {
        setState(() {
          // ratings were reloaded
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if(widget.ratings != null && (ratingCache!.getSettings() == null || ratingCache!.getGroups() == null)) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget keyWidget;

    int? displayMaxPoints = widget.maxPoints;
    if(widget.maxPoints == null) displayMaxPoints = widget.match!.maxPoints;

    var screenSize = MediaQuery.of(context).size;
    var maxWidth = screenSize.width;

    if(widget.match == null) {
      keyWidget = Container();
    }
    else {
      keyWidget = widget.stage == null ? _buildMatchScoreKey(screenSize, displayMaxPoints) : _buildStageScoreKey(screenSize);
    }

    return SingleChildScrollView(
      controller: widget.horizontalScrollController,
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          maxWidth: max(maxWidth, widget.minWidth),
        ),
        child: GestureDetector(
          onPanUpdate: (details) {
            if(widget.horizontalScrollController != null) {
              _adjustScroll(widget.horizontalScrollController!, amount: -details.delta.dx);
            }
            if(widget.verticalScrollController != null) {
              _adjustScroll(widget.verticalScrollController!, amount: -details.delta.dy);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              keyWidget,
              Expanded(child: Scrollbar(
                thumbVisibility: true,
                controller: widget.verticalScrollController,
                child: ListView.builder(
                  controller: widget.verticalScrollController,
                  itemCount: (widget.filteredScores.length),
                  itemBuilder: (ctx, i) {
                    if(widget.stage == null) return _buildMatchScoreRow(index: i, context: context);
                    else if(widget.stage != null) return _buildStageScoreRow(context, i, widget.stage!);
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
          minWidth: widget.minWidth,
          maxWidth: max(screenSize.width, widget.minWidth)
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
                if(widget.ratings != null) Consumer<ScoreDisplaySettingsModel>(
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
                if(sport.hasClassifications && sport.displaySettings.showClassification) Expanded(flex: 1, child: Text("Class")),
                if(sport.hasDivisions) Expanded(flex: 2, child: Text("Division")),
                if(sport.hasPowerFactors && sport.displaySettings.showPowerFactor) Expanded(flex: 1, child: Text("PF")),
                Expanded(flex: 2, child: Text("Match %")),
                if(sport.matchScoring is CumulativeScoring && sport.type.isTimePlus) Expanded(flex: 2, child: Text("Final Time"))
                else Expanded(flex: 2, child: Text("Match Pts.")),
                if(widget.match?.inProgress ?? false) Expanded(flex: 1, child: Text("Through", textAlign: TextAlign.end)),
                if(widget.match?.inProgress ?? false) SizedBox(width: 15),
                if(fantasyScores != null) Expanded(flex: 2, child: Text("F. Pts.")),
                if(sport.type.isTimePlus) Expanded(flex: 2, child: Text("Raw Time"))
                else Expanded(flex: 2, child: Text("Time")),
                if(sport.type.isHitFactor) Expanded(flex: 3, child: Tooltip(
                    message: "The number of points out of the maximum possible for this match.",
                    child: Text("Points/$maxPoints"))
                ),
                ..._buildScoreColumnHeaders(),
              ],
            ),
          )
      ),
    );
  }

  List<Widget> _buildScoreColumnHeaders() {
    List<Widget> scoreHeaders = [];
    for(var column in sport.displaySettings.scoreColumns) {
      int flex = 2;
      if(column.eventGroups.length > 2) {
        flex = 5;
      }

      Widget innerWidget = Text(column.headerLabel);
      if(column.headerTooltip != null) {
        innerWidget = Tooltip(
          message: column.headerTooltip,
          child: innerWidget,
        );
      }

      scoreHeaders.add(Expanded(flex: flex, child: innerWidget));
    }

    return scoreHeaders;
  }

  List<Widget> _buildScoreColumns(RawScore? score) {
    List<Widget> columns = [];
    for(var column in sport.displaySettings.scoreColumns) {
      int flex = 2;
      if(column.eventGroups.length > 2) {
        flex = 5;
      }

      String text = "";
      if(score != null) {
        text = column.format(sport, score);
      }
      columns.add(Expanded(flex: flex, child: Text(text)));
    }

    return columns;
  }

  Widget _buildMatchScoreRow({required BuildContext context, required int index}) {
    var score = widget.filteredScores[index];
    var stagesComplete = 0;
    if(widget.match?.inProgress ?? false) {
      stagesComplete = score.stageScores.values.where((element) => !element.score.dnf).length;
    }

    DbShooterRating? dbRating;
    ShooterRating? shooterRating;
    RatingProjectSettings? settings;

    if(widget.ratings != null) {
      dbRating = ratingCache!.lookupRatingByMatchEntry(score.shooter);
      settings = ratingCache!.getSettings();
      if(dbRating != null && settings != null) {
        shooterRating = settings.algorithm.wrapDbRating(dbRating);
      }
    }

    return GestureDetector(
      onTap: () async {
        if(widget.whatIfMode) {
          var action = await (showDialog<ShooterDialogAction>(context: context, barrierDismissible: false, builder: (context) {
            return EditableShooterCard(sport: widget.match!.sport, matchScore: score, scoreDQ: widget.scoreDQ);
          }));

          if(action != null) {
            if(action.scoreEdit.rescore) {
              // Any edits from here are always going to be whole-match changes
              widget.onScoreEdited(score.shooter, null, true);
            }
            if(action.launchComparison) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => CompareShooterResultsPage(
                  scores: widget.baseScores,
                  initialShooters: [score.shooter],
                )
              ));
            }
          }
        }
        else {
          var action = await showDialog<ShooterDialogAction>(context: context, builder: (context) {
            return ShooterResultCard(
              sport: widget.match!.sport,
              match: widget.match,
              shooterRating: shooterRating,
              ratings: widget.ratings,
              matchScore: score,
              scoreDQ: widget.scoreDQ,
            );
          });

          if(action != null && action.launchComparison) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => CompareShooterResultsPage(
                  scores: widget.baseScores,
                  initialShooters: [score.shooter],
                )
            ));
          }
        }
      },
      child: ScoreRow(
        color: index % 2 == 1 ? Colors.grey[200] : Colors.white,
        edited: widget.editedShooters.contains(score.shooter),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text("${widget.baseScores.indexOf(score) + 1}")),
              Expanded(flex: 1, child: Text("${score.place}")),
              Expanded(flex: 3, child: Text(score.shooter.getName(dnf: score.isDnf))),
              if(widget.ratings != null) Consumer<ScoreDisplaySettingsModel>(
                builder: (context, model, _) {
                  String text = "n/a";

                  if(shooterRating != null) {
                    var rating = shooterRating;

                    switch(model.value.ratingMode) {
                      case RatingDisplayMode.preMatch:
                        var r = rating.ratingForEvent(widget.match!, null, beforeMatch: true).round();
                        text = r.toString();
                        break;
                      case RatingDisplayMode.postMatch:
                        var r = rating.ratingForEvent(widget.match!, null, beforeMatch: false).round();
                        text = r.toString();
                        break;
                      case RatingDisplayMode.change:
                        var r = rating.changeForEvent(widget.match!, null);
                        if(r != null) text = r.toStringAsFixed(1);
                        break;
                    }
                  }
                  return Expanded(flex: 1, child: Text(text));
                }
              ),
              if(sport.hasClassifications && sport.displaySettings.showClassification) Expanded(flex: 1, child: Text(score.shooter.classification?.shortName ?? "UNK")),
              if(sport.hasDivisions) Expanded(flex: 2, child: Text(score.shooter.division?.displayName ?? "NO DIVISION")),
              if(sport.hasPowerFactors && sport.displaySettings.showPowerFactor) Expanded(flex: 1, child: Text(score.shooter.powerFactor.shortName)),
              Expanded(flex: 2, child: Text("${score.ratio.asPercentage()}%")),
              Expanded(flex: 2, child: Text(score.points.toStringAsFixed(2))),
              if(widget.match?.inProgress ?? false) Expanded(flex: 1, child: Text("$stagesComplete", textAlign: TextAlign.end)),
              if(widget.match?.inProgress ?? false) SizedBox(width: 15),
              if(fantasyScores != null) Expanded(
                flex: 2,
                child: Tooltip(
                  message: fantasyScores![score.shooter]?.tooltip,
                  child: Text(fantasyScores![score.shooter]?.points.toStringAsFixed(2) ?? "0.0"),
                )
              ),
              if(sport.type.isTimePlus) Expanded(flex: 2, child: Text(score.total.rawTime.toStringAsFixed(2)))
              else Expanded(flex: 2, child: Text(score.total.finalTime.toStringAsFixed(2))),
              if(sport.type.isHitFactor) Consumer<ScoreDisplaySettingsModel>(
                builder: (context, model, _) {
                  if(model.value.fixedTimeAvailablePointsFromDivisionMax) {
                    Map<MatchStage, int> stageMax = {};
                    for(var s in score.stageScores.keys) {
                      if(s.scoring is PointsScoring && widget.match!.sport.type.isHitFactor) {
                        var bestPoints = 0;
                        for(var score in widget.baseScores) {
                          if(score.stageScores[s] != null && score.stageScores[s]!.score.points > bestPoints) {
                            bestPoints = score.stageScores[s]!.score.points;
                          }
                        }
                        stageMax[s] = bestPoints;
                      }
                    }
                    return Expanded(flex: 3, child: Text("${!widget.scoreDQ && score.shooter.dq ? 0 : score.total.getTotalPoints(countPenalties: model.value.availablePointsCountPenalties)} "
                        "(${score.percentTotalPointsWithSettings(scoreDQ: true, countPenalties: model.value.availablePointsCountPenalties, stageMaxPoints: stageMax).asPercentage()}%)"));
                  }
                  else {
                    return Expanded(flex: 3, child: Text("${!widget.scoreDQ && score.shooter.dq ? 0 : score.total.getTotalPoints(countPenalties: model.value.availablePointsCountPenalties)} "
                        "(${score.percentTotalPointsWithSettings(scoreDQ: true, countPenalties: model.value.availablePointsCountPenalties).asPercentage()}%)"));
                  }
                },
              ),
              ..._buildScoreColumns(score.total),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageScoreKey(Size screenSize) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          minWidth: widget.minWidth,
          maxWidth: max(screenSize.width, widget.minWidth)
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
                if(widget.ratings != null) Consumer<ScoreDisplaySettingsModel>(
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
                if(sport.hasClassifications && sport.displaySettings.showClassification) Expanded(flex: 1, child: Text("Class")),
                if(sport.hasDivisions) Expanded(flex: 2, child: Text("Division")),
                if(sport.hasPowerFactors && sport.displaySettings.showPowerFactor) Expanded(flex: 1, child: Text("PF")),
                if(sport.type.isHitFactor) Expanded(flex: 3, child: Tooltip(
                    message: "The number of points out of the maximum possible for this stage.",
                    child: Text("Points/${widget.stage!.maxPoints}"))
                ),
                if(sport.type.isTimePlus) Expanded(flex: 2, child: Text("Final Time")),
                if(sport.type.isTimePlus) Expanded(flex: 2, child: Text("Raw Time"))
                else Expanded(flex: 2, child: Text("Time")),
                if(sport.type.isHitFactor) Expanded(flex: 2, child: Text("Hit Factor")),
                Expanded(flex: 2, child: Text("Stage %")),
                if(sport.matchScoring is RelativeStageFinishScoring) Expanded(flex: 2, child: Text("Match Pts.")),
                ..._buildScoreColumnHeaders(),
              ],
            ),
          )
      ),
    );
  }

  Widget _buildStageScoreRow(BuildContext context, int i, MatchStage stage) {
    var matchScore = widget.filteredScores[i];
    var stageScore = widget.filteredScores[i].stageScores[stage];

    DbShooterRating? dbRating;
    ShooterRating? shooterRating;
    RatingProjectSettings? settings;

    if(widget.ratings != null) {
      dbRating = ratingCache!.lookupRatingByMatchEntry(matchScore.shooter);
      settings = ratingCache!.getSettings();
      if(dbRating != null && settings != null) {
        shooterRating = settings.algorithm.wrapDbRating(dbRating);
      }
    }

    return GestureDetector(
      onTap: () async {
        if(widget.whatIfMode) {
          var action = await (showDialog<ShooterDialogAction>(context: context, barrierDismissible: false, builder: (context) {
            return EditableShooterCard(sport: widget.match!.sport, stageScore: stageScore, scoreDQ: widget.scoreDQ,);
          }));

          if(action != null) {
            if (action.scoreEdit.rescore) {
              widget.onScoreEdited(matchScore.shooter, stage, action.scoreEdit.wholeMatch);
            }
            if (action.launchComparison) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CompareShooterResultsPage(
                    scores: widget.baseScores,
                    initialShooters: [matchScore.shooter],
                  )
                )
              );
            }
          }
        }
        else {
          var action = await showDialog<ShooterDialogAction>(context: context, builder: (context) {
            return ShooterResultCard(sport: widget.match!.sport, stageScore: stageScore, scoreDQ: widget.scoreDQ,);
          });

          if(action != null && action.launchComparison) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => CompareShooterResultsPage(
                  scores: widget.baseScores,
                  initialShooters: [matchScore.shooter],
                )
            ));
          }
        }
      },
      child: ScoreRow(
        color: i % 2 == 1 ? Colors.grey[200] : Colors.white,
        edited: widget.editedShooters.contains(matchScore.shooter),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text("${widget.baseScores.indexOf(matchScore) + 1}")),
              Expanded(flex: 1, child: Text("${stageScore?.place}")),
              Expanded(flex: 3, child: Text(matchScore.shooter.getName())),
              if(widget.ratings != null) Consumer<ScoreDisplaySettingsModel>(
                  builder: (context, model, _) {
                    String text = "n/a";

                    if(shooterRating != null) {
                      var rating = shooterRating;

                      switch(model.value.ratingMode) {
                        case RatingDisplayMode.preMatch:
                          var r = rating.ratingForEvent(widget.match!, null, beforeMatch: true).round();
                          text = r.toString();
                          break;
                        case RatingDisplayMode.postMatch:
                          var r = rating.ratingForEvent(widget.match!, null, beforeMatch: false).round();
                          text = r.toString();
                          break;
                        case RatingDisplayMode.change:
                          var r = rating.changeForEvent(widget.match!, stage);
                          if(r != null) text = r.toStringAsFixed(1);
                          break;
                      }
                    }
                    return Expanded(flex: 1, child: Text(text));
                  }
              ),
              if(sport.hasClassifications && sport.displaySettings.showClassification) Expanded(flex: 1, child: Text(matchScore.shooter.classification?.shortName ?? "?")),
              if(sport.hasDivisions) Expanded(flex: 2, child: Text(matchScore.shooter.division?.displayName ?? "NO DIVISION")),
              if(sport.hasPowerFactors && sport.displaySettings.showPowerFactor) Expanded(flex: 1, child: Text(matchScore.shooter.powerFactor.shortName)),
              if(sport.type.isHitFactor) Consumer<ScoreDisplaySettingsModel>(
                builder: (context, model, _) {
                  var matchScoring = widget.match!.sport.matchScoring;
                  bool hasFixedTime = false;
                  if(matchScoring is RelativeStageFinishScoring) {
                    if(matchScoring.pointsAreUSPSAFixedTime) hasFixedTime = true;
                  }

                  if(model.value.fixedTimeAvailablePointsFromDivisionMax && hasFixedTime) {
                    int maxPoints = 0;

                    if(stageScore == null) {
                      return Expanded(flex: 3, child: Text("n/a"));
                    }

                    if(stageScore!.score.scoring is PointsScoring) {
                      for(var score in widget.baseScores) {
                        if(score.stageScores[stage] != null && score.stageScores[stage]!.score.points > maxPoints) {
                          maxPoints = score.stageScores[stage]!.score.points;
                        }
                      }
                    }
                    else {
                      maxPoints = stage.maxPoints;
                    }

                    return Expanded(flex: 3, child: Text("${!widget.scoreDQ && stageScore.shooter.dq ? 0 : stageScore.score.getTotalPoints(countPenalties: model.value.availablePointsCountPenalties)} "
                        "(${((stageScore.getPercentTotalPoints(scoreDQ: widget.scoreDQ, countPenalties: model.value.availablePointsCountPenalties, maxPoints: maxPoints)).asPercentage(decimals: 1))}%)"));
                  }
                  else {
                    return Expanded(flex: 3, child: Text("${!widget.scoreDQ && (stageScore?.shooter.dq ?? false)? 0 : stageScore?.score.getTotalPoints()} "
                        "(${((stageScore?.getPercentTotalPoints(scoreDQ: widget.scoreDQ, countPenalties: model.value.availablePointsCountPenalties) ?? 0).asPercentage(decimals: 1))}%)"));
                  }
                },
              ),
              Expanded(flex: 2, child: Text(stageScore?.score.finalTime.toStringAsFixed(2) ?? "0.00")),
              if(sport.type.isTimePlus) Expanded(flex: 2, child: Text(stageScore?.score.rawTime.toStringAsFixed(2) ?? "0.00")),
              if(sport.type.isHitFactor) Expanded(flex: 2, child: Text(stageScore?.score.displayString ?? "-")),
              Expanded(flex: 2, child: Text("${stageScore?.ratio.asPercentage() ?? "0.00"}%")),
              if(sport.matchScoring is RelativeStageFinishScoring) Expanded(flex: 2, child: Text(stageScore?.points.toStringAsFixed(2) ?? "0.00")),
              ..._buildScoreColumns(stageScore?.score),
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

extension LookupShooterRating on Map<OldRaterGroup, Rater> {
  ShooterRating? lookupNew(ShootingMatch match, MatchEntry s) {
    Rater? group = lookupRater(match, s);

    if(group != null) {
      // might not be present in the case of rating sets that
      // don't cover the whole sport
      // return group.ratingForNew(s);
    }

    return null;
  }

  double? lookupRating({required MatchEntry shooter, RatingDisplayMode mode = RatingDisplayMode.preMatch, required ShootingMatch match, MatchStage? stage}) {
    switch(mode) {
      case RatingDisplayMode.preMatch:
        var rating = this.lookupNew(match, shooter)?.ratingForEvent(match, null, beforeMatch: true);
        return rating;
      case RatingDisplayMode.postMatch:
        var rating = this.lookupNew(match, shooter)?.ratingForEvent(match, null, beforeMatch: false);
        return rating;
      case RatingDisplayMode.change:
        var rating = this.lookupNew(match, shooter)?.changeForEvent(match, stage);
        return rating;
    }
  }

  Rater? lookupOldRater(old.Shooter shooter) {
    // TODO: fix when ratings are converted
    // for(var group in this.keys) {
    //   if(group.divisions.contains(shooter.division)) {
    //     return this[group]!;
    //   }
    // }

    return null;
  }

  Rater? lookupRater(ShootingMatch match, MatchEntry s) {
    OldRaterGroup? group = null;
    outer:for(var g in this.keys) {
      for(var division in g.divisions) {
        var matchingDivision = match.sport.divisions.lookupByName(division.name, fallback: false);
        if(matchingDivision == s.division) {
          group = g;
          break outer;
        }
      }
    }

    return this[group];
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
