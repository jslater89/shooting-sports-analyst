/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_grid.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_move.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_settings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

SSALogger _log = SSALogger("BoothScorecard");

class BoothScorecard extends StatefulWidget {
  const BoothScorecard({super.key, required this.scorecard});

  final ScorecardModel scorecard;

  @override
  State<BoothScorecard> createState() => _BoothScorecardState();
}

class _BoothScorecardState extends State<BoothScorecard> {
  DateTime lastScoresCalculated = DateTime(0);
  int lastScorecardCount = 0;

  Map<MatchEntry, RelativeMatchScore> scores = {};
  List<MatchEntry> displayedShooters = [];

  VoidCallback? listener;

  bool disposed = false;
  late BroadcastBoothModel cachedModel;

  @override
  void initState() {
    super.initState();
    // _log.v("${widget.scorecard.name} (${widget.hashCode} ${hashCode} ${widget.scorecard.hashCode}) initState");
   
    var model = context.read<BroadcastBoothModel>();
    cachedModel = model;
    _calculateScores();
  
    listener = () {
      if(!mounted) {
        _log.e("${widget.scorecard.name} ${hashCode} was notified, but not mounted");
        if(!disposed) {
          var model = context.read<BroadcastBoothModel>();
          model.removeListener(listener!);
          _log.i("Removed listener for ${widget.scorecard.name}");
        }
        return;
      }
      
      var model = context.read<BroadcastBoothModel>();
      if(model.tickerModel.lastUpdateTime.isAfter(lastScoresCalculated) || lastScorecardCount != model.scorecardCount) {
        _calculateScores();
      }
      else {
        _log.w("${widget.scorecard.name} (${widget.hashCode} ${hashCode} ${widget.scorecard.hashCode}) was notified, but last update time ${model.tickerModel.lastUpdateTime} is before $lastScoresCalculated");
      }
    };
    model.addListener(listener!);
  }

  void dispose() {
    disposed = true;
    cachedModel.removeListener(listener!);
    super.dispose();
  }

  Future<void> _calculateScores() async {
    var model = context.read<BroadcastBoothModel>();
    await model.readyFuture;

    var match = model.latestMatch;
    scores = match.getScoresFromFilters(widget.scorecard.scoreFilters);
    displayedShooters = widget.scorecard.displayFilters.apply(match);
    displayedShooters.sort((a, b) {
      if(scores[a] == null && scores[b] == null) {
        return 0;
      }
      else if(scores[a] == null) {
        return 1;
      }
      else if(scores[b] == null) {
        return -1;
      }
      return scores[b]!.points.compareTo(scores[a]!.points);
    });

    setState(() {
      lastScoresCalculated = model.tickerModel.lastUpdateTime;
      lastScorecardCount = model.scorecardCount;
    });
    _log.i("Score filters for ${widget.scorecard.name} match ${scores.length}, display filters match ${displayedShooters.length}");
  }

  @override
  Widget build(BuildContext context) {
    // print("${widget.scorecard.name} (${widget.hashCode} ${hashCode} ${widget.scorecard.hashCode}) build");
    var match = context.read<BroadcastBoothModel>().latestMatch;
    var sizeModel = context.read<ScorecardGridSizeModel>();
    var controller = context.read<BroadcastBoothController>();
  
    return Container(
      padding: EdgeInsets.all(2),
      width: sizeModel.cardWidth.toDouble(),
      height: sizeModel.cardHeight.toDouble(),
      alignment: Alignment.center,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text("${widget.scorecard.name} (showing ${displayedShooters.length} competitors of ${scores.length} scored)"),
                  ),
                  SizedBox(
                    height: 40,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          child: Icon(Icons.open_with),
                          onPressed: () async {
                            var direction = await ScorecardMoveDialog.show(context, scorecard: widget.scorecard, validMoves: controller.validMoves(widget.scorecard));
                            if(direction != null) {
                              controller.moveScorecard(widget.scorecard, direction);
                            }
                          },
                        ),
                        TextButton(
                          child: Icon(Icons.settings),
                          onPressed: () async {
                            var editedScorecard = await ScorecardSettingsDialog.show(context, scorecard: widget.scorecard.copy(), match: match);
                            if(editedScorecard != null) {
                              controller.scorecardEdited(widget.scorecard, editedScorecard);
                              _calculateScores();
                            }
                          },
                        ),
                        TextButton(
                          child: Icon(Icons.close),
                          onPressed: () async {
                            var confirm = await ConfirmDialog.show(context, title: "Remove scorecard?", positiveButtonLabel: "REMOVE");
                            if(confirm ?? false) {
                              var model = context.read<BroadcastBoothModel>();
                              if(listener != null) {
                                model.removeListener(listener!);
                                _log.i("Removed listener for ${widget.scorecard.name}");
                              }
                              else {
                                _log.w("${widget.scorecard.name} has null listener!");
                              }
                              _log.i("Removing scorecard ${widget.scorecard.name}");
                              // _log.v("${widget.scorecard.name} (${widget.hashCode} ${hashCode} ${widget.scorecard.hashCode}) removed");
                              controller.removeScorecard(widget.scorecard);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _buildTable(),
              )
            ]
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    var match = context.read<BroadcastBoothModel>().latestMatch;
    List<Widget> scoreRows = [];
    for(int i = 0; i < displayedShooters.length; i++) {
      scoreRows.add(_buildScoreRow(match, displayedShooters[i], i));
    }

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                _buildHeaderRow(match),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Column(children: [
                      ...scoreRows,
                    ])
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _shooterColumnWidth = 200.0;
  static const _stageColumnWidth = 75.0;

  Widget _buildHeaderRow(ShootingMatch match) {
    var stages = match.stages.where((s) => !(s.scoring is IgnoredScoring)).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide()
        ),
        color: Colors.white,
      ),
      child: Row(
        children: [
          SizedBox(width: _shooterColumnWidth, child: Text("Competitor", textAlign: TextAlign.right)),
          SizedBox(width: _stageColumnWidth, child: Text("Total", textAlign: TextAlign.center)),
          ...stages.map((stage) => SizedBox(width: _stageColumnWidth, child: Text("Stage ${stage.stageId}", textAlign: TextAlign.center))),
          SizedBox(width: _shooterColumnWidth, child: Text("Competitor", textAlign: TextAlign.left)),
        ],
      ),
    );
  }

  Widget _buildScoreRow(ShootingMatch match, MatchEntry entry, int index) {
    var score = scores[entry];
    var stages = match.stages.where((s) => !(s.scoring is IgnoredScoring)).toList();
    if(score == null) {
      return ScoreRow(
        hoverEnabled: true,
        bold: false,
        child: Row(
          children: [
            SizedBox(width: _shooterColumnWidth, child: Text(entry.getName(), textAlign: TextAlign.right)),
            SizedBox(width: _stageColumnWidth, child: Text("-", textAlign: TextAlign.center)),
            ...stages.map((stage) => SizedBox(width: _stageColumnWidth, child: Text("-", textAlign: TextAlign.center))),
            SizedBox(width: _shooterColumnWidth, child: Text(entry.getName(), textAlign: TextAlign.left)),
          ],
        ),
      );
    }
    return ScoreRow(
      hoverEnabled: true,
      bold: false,
      color: index % 2 == 0 ? Colors.white : Colors.grey[200],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.0),
        child: Row(
          children: [
            SizedBox(width: _shooterColumnWidth, child: Text(entry.getName(), textAlign: TextAlign.right)),
            SizedBox(
              width: _stageColumnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  OrdinalPlaceText(place: score.place, textAlign: TextAlign.center),
                  Text("${score.percentage.toStringAsFixed(2)}%", textAlign: TextAlign.center),
                ],
              ),
            ),
            ...stages.map((stage) {
                var stageScore = score.stageScores[stage];
                if(stageScore == null) {
                  return SizedBox(width: _stageColumnWidth, child: Text("-", textAlign: TextAlign.center));
                }
                return SizedBox(
                  width: _stageColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      OrdinalPlaceText(place: stageScore.place, textAlign: TextAlign.center),
                      Text("${stageScore.percentage.toStringAsFixed(2)}%", textAlign: TextAlign.center),
                      Text(stageScore.score.displayString, textAlign: TextAlign.center),
                    ],
                  ),
                );
              }
            ),
            SizedBox(width: _shooterColumnWidth, child: Text(entry.getName(), textAlign: TextAlign.left)),
          ],
        ),
      ),
    );
  }
}

class OrdinalPlaceText extends StatelessWidget {
  const OrdinalPlaceText({super.key, required this.place, this.textAlign = TextAlign.left});

  final int place;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    var prefix = "";
    var prefixColor = Colors.black;
    if(place == 1) {
      prefix = "🥇";
      prefixColor = Colors.yellow[800]!;
    }
    else if(place == 2) {
      prefix = "🥈";
      prefixColor = Colors.grey[400]!;
    }
    else if(place == 3) {
      prefix = "🥉";
      prefixColor = const Color.fromARGB(255, 211, 141, 116);
    }
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: _textAlignToMainAxisAlign(textAlign),
      children: [
        if(prefix.isNotEmpty) Text(prefix, style: TextStyle(color: prefixColor)),
        Text(place.ordinalPlace),
      ]
    );
  }

  MainAxisAlignment _textAlignToMainAxisAlign(TextAlign textAlign) {
    switch(textAlign) {
      case TextAlign.left: return MainAxisAlignment.start;
      case TextAlign.right: return MainAxisAlignment.end;
      default: return MainAxisAlignment.center;
    }
  }
}

extension PlaceSuffix on int {
  String get ordinalPlace {
    var string = this.toString();
    if(string.endsWith("11") || string.endsWith("12") || string.endsWith("13")) {
      return "${string}th";
    }
    switch(string.characters.last) {
      case "1": return "${string}st";
      case "2": return "${string}nd";
      case "3": return "${string}rd";
    }
    return "${string}th";
  }
}