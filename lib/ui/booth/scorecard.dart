/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/score_utils.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_grid.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_move.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_settings.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
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
  DateTime? lastScoresBefore;
  DateTime? lastScoresAfter;
  MatchPredictionMode lastPredictionMode = MatchPredictionMode.none;

  Map<MatchEntry, RelativeMatchScore> scores = {};
  Map<MatchEntry, MatchScoreChange> scoreChanges = {};
  List<MatchEntry> displayedShooters = [];

  VoidCallback? listener;

  bool disposed = false;
  late BroadcastBoothModel cachedModel;

  bool showingTimewarp = false;

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
      if(_hasChanges(model)) {
        _calculateScores();
      }
      else {
        _log.w("${widget.scorecard.name} (${widget.hashCode} ${hashCode} ${widget.scorecard.hashCode}) was notified, but no changes detected");
      }
    };
    model.addListener(listener!);
    _controlListener = (event) {
      if(event.logicalKey == LogicalKeyboardKey.controlLeft || event.logicalKey == LogicalKeyboardKey.controlRight) {
        if(event is KeyDownEvent) {
          setState(() {
            innerScrollPhysics = const NeverScrollableScrollPhysics();
          });
        }
        else {
          setState(() {
            innerScrollPhysics = const ClampingScrollPhysics();
          });
        }
      }
      return false;
    };
    HardwareKeyboard.instance.addHandler(_controlListener);
  }

  bool _hasChanges(BroadcastBoothModel model) {
    if(lastScoresBefore != widget.scorecard.scoresBefore) {
      return true;
    }
    if(lastScoresAfter != widget.scorecard.scoresAfter) {
      return true;
    }
    if(lastPredictionMode != widget.scorecard.predictionMode) {
      return true;
    }
    if(lastScorecardCount != model.scorecardCount) {
      return true;
    }
    if(lastScoresCalculated.isBefore(model.tickerModel.lastUpdateTime)) {
      return true;
    }
    return false;
  }

  late KeyEventCallback _controlListener;

  void _updateChangeFlags(BroadcastBoothModel model) {
    lastScoresBefore = widget.scorecard.scoresBefore;
    lastScoresAfter = widget.scorecard.scoresAfter;
    lastPredictionMode = widget.scorecard.predictionMode;
    lastScorecardCount = model.scorecardCount;
    lastScoresCalculated = model.tickerModel.lastUpdateTime;
  }

  void dispose() {
    disposed = true;
    cachedModel.removeListener(listener!);
    HardwareKeyboard.instance.removeHandler(_controlListener);
    super.dispose();
  }

  Future<void> _calculateScores() async {
    var model = context.read<BroadcastBoothModel>();
    await model.readyFuture;

    var match = model.latestMatch;
    Map<MatchEntry, RelativeMatchScore> oldScores = {};

    if(model.inTimewarp) {
      showingTimewarp = true;
      oldScores = match.getScoresFromFilters(
        widget.scorecard.scoreFilters,
        scoresAfter: widget.scorecard.scoresAfter,
        scoresBefore: widget.scorecard.scoresBefore?.add(Duration(seconds: -model.tickerModel.updateInterval)),
        predictionMode: widget.scorecard.predictionMode,
      );
    }
    else if(!showingTimewarp) {
      // skip the first ticker update after leaving timewarp, since 
      oldScores = scores;
    }
    else {
      showingTimewarp = false;
    }

    scores = match.getScoresFromFilters(
      widget.scorecard.scoreFilters,
      scoresAfter: widget.scorecard.scoresAfter,
      scoresBefore: widget.scorecard.scoresBefore,
      predictionMode: widget.scorecard.predictionMode,
    );

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

    if(widget.scorecard.displayFilters.topN != null) {
      displayedShooters = displayedShooters.take(widget.scorecard.displayFilters.topN!).toList();
    }

    if(oldScores.isNotEmpty) {
      _calculateTickerUpdates(model, oldScores, scores);
    }

    setState(() {
      _updateChangeFlags(model);
    });
    _log.i("Score filters for ${widget.scorecard.name} match ${scores.length}, display filters match ${displayedShooters.length}");
  }

  void _calculateTickerUpdates(BroadcastBoothModel model, Map<MatchEntry, RelativeMatchScore> oldScores, Map<MatchEntry, RelativeMatchScore> newScores) {
    var changes = calculateScoreChanges(oldScores, newScores);
    _log.v("${widget.scorecard.name} (id:${widget.scorecard.id}) has ${changes.length} changes");

    // It's possible for the match lead to change without either shooter involved entering a new score,
    // because of hit factor magic. If that happens, manually add a change entry, so that the ticker
    // can report it.
    var newFirstPlace = newScores.keys.first;
    var previousEntry = oldScores.keys.firstWhereOrNull((e) => e.entryId == newFirstPlace.entryId);
    if(previousEntry != null) {
      var previousPosition = oldScores[previousEntry]?.place;
      if(previousPosition != null && previousPosition != 1) {
        if(!changes.containsKey(newFirstPlace)) {
          changes[newFirstPlace] = MatchScoreChange(oldScore: oldScores[previousEntry]!, newScore: newScores[newFirstPlace]!);
        }
      }
    }

    if(changes.isNotEmpty) {
      var controller = context.read<BroadcastBoothController>();
      changes.removeWhere((e, c) => !displayedShooters.contains(e));
      for(var criterion in model.tickerModel.globalTickerCriteria) {
        var events = criterion.checkEvents(
          scorecard: widget.scorecard,
          changes: changes,
          newScores: newScores,
          updateTime: model.tickerModel.lastUpdateTime,
        );
        controller.addTickerEvents(events);
      }
    }

    setState(() {
      scoreChanges = changes;
    });
  }

  ScrollPhysics innerScrollPhysics = const ClampingScrollPhysics();

  @override
  Widget build(BuildContext context) {
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
            physics: innerScrollPhysics,
            child: Column(
              children: [
                _buildHeaderRow(match),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    physics: innerScrollPhysics,
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
  static const _scoreRowHeight = 55.0;

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
    var change = scoreChanges[entry];

    Map<int, bool> changedStages = {};
    for(StageScoreChange change in change?.stageScoreChanges.values.toList() ?? <StageScoreChange>[]) {
      changedStages[change.newScore.stage.stageId] = true;
    }
    var stages = match.stages.where((s) => !(s.scoring is IgnoredScoring)).toList();
    if(score == null) {
      return ScoreRow(
        hoverEnabled: true,
        bold: false,
        child: SizedBox(
          height: _scoreRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: _shooterColumnWidth, child: Text(entry.getName(), textAlign: TextAlign.right)),
              SizedBox(width: _stageColumnWidth, child: Text("-", textAlign: TextAlign.center)),
              ...stages.map((stage) => SizedBox(width: _stageColumnWidth, child: Text("-", textAlign: TextAlign.center))),
              SizedBox(width: _shooterColumnWidth, child: Text(entry.getName(), textAlign: TextAlign.left)),
            ],
          ),
        ),
      );
    }
    var matchScoreColor = changedStages.isNotEmpty ? Colors.green[500] : null;
    return ScoreRow(
      hoverEnabled: true,
      bold: false,
      color: index % 2 == 0 ? Colors.white : Colors.grey[200],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _shooterColumnWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(entry.getName(), textAlign: TextAlign.right),
                if(score.isComplete) Tooltip(message: "All stages complete.", child: Icon(Icons.lock, size: 16, color: Colors.grey[500])),
              ],
            ),
          ),
          Container(
            height: _scoreRowHeight,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide()
              ),
            ),
            child: SizedBox(
              width: _stageColumnWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _wrapWithPlaceChange(change, OrdinalPlaceText(place: score.place, textAlign: TextAlign.center, color: matchScoreColor)),
                  Text("${score.percentage.toStringAsFixed(2)}%", textAlign: TextAlign.center, style: TextStyle(color: matchScoreColor)),
                  _wrapWithPointsChange(change, Text("${score.points.toStringAsFixed(1)}pt", textAlign: TextAlign.center, style: TextStyle(color: matchScoreColor))),
                ],
              ),
            ),
          ),
          ...stages.map((stage) {
              var stageScore = score.stageScores[stage];
              var stageScoreColor = changedStages.containsKey(stage.stageId) ? Colors.green[500] : null;
              if(stageScore == null || stageScore.score.dnf) {
                return SizedBox(width: _stageColumnWidth, child: Text("-", textAlign: TextAlign.center));
              }
              return SizedBox(
                width: _stageColumnWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    OrdinalPlaceText(place: stageScore.place, textAlign: TextAlign.center, color: stageScoreColor),
                    Tooltip(
                      message: "${stageScore.points.toStringAsFixed(1)}pt",
                      child: Text("${stageScore.percentage.toStringAsFixed(2)}%", textAlign: TextAlign.center, style: TextStyle(color: stageScoreColor))
                    ),
                    Tooltip(
                      message: match.sport.displaySettings.formatTooltip(stageScore.score),
                      child: Text(stageScore.score.displayString, textAlign: TextAlign.center, style: TextStyle(color: stageScoreColor))
                    ),
                  ],
                ),
              );
            }
          ),
          SizedBox(
            width: _shooterColumnWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if(score.isComplete) Tooltip(message: "All stages complete.", child: Icon(Icons.lock, size: 16, color: Colors.grey[500])),
                Text(entry.getName(), textAlign: TextAlign.right),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapWithPlaceChange(MatchScoreChange? change, Widget child) {
    if(change == null) {
      return child;
    }
    var delta = change.oldScore.place - change.newScore.place;
    var message = "${delta > 0 ? "+" : ""}${delta}";
    if(delta == 0) {
      message = "-";
    }
    return Tooltip(
      message: message,
      child: child
    );
  }

  Widget _wrapWithPointsChange(MatchScoreChange? change, Widget child) {
    if(change == null) {
      return child;
    }
    var delta = change.newScore.points - change.oldScore.points;
    return Tooltip(
      message: "${delta > 0 ? "+" : ""}${delta.toStringAsFixed(1)}pt",
      child: child
    );
  }
}

class OrdinalPlaceText extends StatelessWidget {
  const OrdinalPlaceText({super.key, required this.place, this.textAlign = TextAlign.left, this.color});

  final int place;
  final TextAlign textAlign;
  final Color? color;
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
      prefixColor = Colors.grey[600]!;
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
        Text(place.ordinalPlace, style: TextStyle(color: color)),
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