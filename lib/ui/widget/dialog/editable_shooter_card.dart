/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/ui/widget/captioned_text.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/shooter_card.dart';
import 'package:shooting_sports_analyst/ui/widget/score_list.dart';
import 'package:shooting_sports_analyst/util.dart';

/// EditableShooterCard should _not_ be barrier-dismissable.
class EditableShooterCard extends StatefulWidget {
  final Sport sport;
  final RelativeMatchScore? matchScore;
  final RelativeStageScore? stageScore;
  final bool scoreDQ;

  const EditableShooterCard({required this.sport, Key? key, this.matchScore, this.stageScore, this.scoreDQ = true}) : super(key: key);

  @override
  _EditableShooterCardState createState() => _EditableShooterCardState();
}

class _EditableShooterCardState extends State<EditableShooterCard> {
  TextEditingController _timeController = TextEditingController();

  Map<ScoringEvent, TextEditingController> _targetControllers = {};
  Map<ScoringEvent, TextEditingController> _penaltyControllers = {};

  bool _edited = false;
  bool _wholeMatchChange = false;

  String _scoreError = "";

  @override
  void initState() {
    super.initState();

    _timeController.text = _score.rawTime.toStringAsFixed(2);
    var pf = _shooter.powerFactor;
    for(var event in pf.targetEvents.values) {
      _targetControllers[event] = TextEditingController(text: "${_score.targetEvents[event] ?? 0}");
    }
    for(var event in pf.penaltyEvents.values) {
      _penaltyControllers[event] = TextEditingController(text: "${_score.penaltyEvents[event] ?? 0}");
    }
  }

  RelativeScore get _relativeScore {
    if(widget.stageScore != null) return widget.stageScore!;
    else return widget.matchScore!;
  }

  MatchEntry get _shooter {
    if(widget.stageScore != null) return widget.stageScore!.shooter;
    else return widget.matchScore!.shooter;
  }

  RawScore get _score {
    if(widget.stageScore != null) return widget.stageScore!.score;
    else return widget.matchScore!.total;
  }

  @override
  Widget build(BuildContext context) {
    if(widget.matchScore == null && widget.stageScore == null) {
      throw FlutterError("Match score and stage score both null");
    }
    if(widget.matchScore != null && widget.stageScore != null) {
      throw FlutterError("Match score and stage score both provided");
    }

    if(widget.stageScore != null) {
      return _buildStageCard(context);
    }
    else {
      return _buildMatchCard(context);
    }
  }

  Widget _buildMatchCard(BuildContext context) {
    MatchEntry shooter = widget.matchScore!.shooter;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildShooterLink(context, shooter),
            SizedBox(height: 10),
            _buildMatchDropdowns(context, shooter),
            SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CaptionedText(
                    captionText: "Match Score",
                    text: "${widget.matchScore!.points!.toStringAsFixed(2)} (${widget.matchScore!.ratio.asPercentage()}%)"
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Time",
                  text: "${widget.matchScore!.total.finalTime.toStringAsFixed(2)}s",
                )
              ],
            ),
            SizedBox(height: 10),
            MatchScoreBody(result: widget.matchScore!.total, powerFactor: widget.matchScore!.shooter.powerFactor),
            SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: _buildButtons(),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMatchDropdowns(BuildContext context, MatchEntry shooter) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDivisionDropdown(context, shooter),
        SizedBox(width: 5),
        _buildPowerFactorDropdown(context, shooter),
      ],
    );
  }

  Widget _buildDivisionDropdown(BuildContext context, MatchEntry shooter) {
    // TODO: if sport has divisions
    return DropdownButton<Division>(
      value: shooter.division,
      items: widget.sport.divisions.values.map((division) {
        return DropdownMenuItem<Division>(
          child: Text(division.name),
          value: division,
        );
      }).toList(),
      onChanged: (division) {
        if(division != null) {
          setState(() {
            shooter.division = division;
            _wholeMatchChange = true;
          });
        }
      },
    );
  }

  Widget _buildPowerFactorDropdown(BuildContext context, MatchEntry shooter) {
    // TODO: if sport has power factors
    return DropdownButton<PowerFactor>(
      value: shooter.powerFactor,
      items: widget.sport.powerFactors.values.map((powerFactor) {
        return DropdownMenuItem<PowerFactor>(
          child: Text(powerFactor.displayName),
          value: powerFactor,
        );
      }).toList(),
      onChanged: (powerFactor) {
        if(powerFactor != null) {
          setState(() {
            shooter.powerFactor = powerFactor;
            _wholeMatchChange = true;
          });
        }
      },
    );
  }

  Widget _buildStageCard(BuildContext context) {
    MatchEntry shooter = widget.stageScore!.shooter;
    MatchStage stage = widget.stageScore!.stage;
    RawScore score = widget.stageScore!.score;

    List<Widget> timeHolder = [];
    var stringTimes = widget.stageScore!.score.stringTimes;

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

    var scoringWidgets = <Widget>[];
    for(var event in _targetControllers.keys) {
      scoringWidgets.add(SizedBox(
        width: 50,
        child: TextField(
          controller: _targetControllers[event]!,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
          ],
          decoration: InputDecoration(
              labelText: event.shortDisplayName,
              floatingLabelBehavior: FloatingLabelBehavior.always
          ),
        ),
      ));
      scoringWidgets.add(SizedBox(width: 12));
    }
    if(scoringWidgets.isNotEmpty) scoringWidgets.removeLast();

    var penaltyWidgets = <Widget>[];
    for(var event in _penaltyControllers.keys) {
      penaltyWidgets.add(SizedBox(
        width: 50,
        child: TextField(
          controller: _penaltyControllers[event]!,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
          ],
          decoration: InputDecoration(
              labelText: event.shortDisplayName,
              floatingLabelBehavior: FloatingLabelBehavior.always
          ),
        ),
      ));
      penaltyWidgets.add(SizedBox(width: 12));
    }
    if(penaltyWidgets.isNotEmpty) penaltyWidgets.removeLast();

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildShooterLink(context, shooter),
            SizedBox(height: 10),
            _buildMatchDropdowns(context, shooter),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CaptionedText(
                  captionText: score.displayLabel,
                  text: score.displayString,
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _timeController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[0-9]+\.?([0-9]+)?")),
                    ],
                    decoration: InputDecoration(
                        labelText: "Time",
                        floatingLabelBehavior: FloatingLabelBehavior.always
                    ),
                  ),
                ),
                SizedBox(width: 12),
                CaptionedText(
                  captionText: "Stage Score",
                  text: _getPercentScoreText(),
                )
              ],
            ),
            SizedBox(height: 10)
          ]..addAll(
              timeHolder
          )..addAll(
              [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Round count: ${stage.minRounds}"),
                    SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ...scoringWidgets
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ...penaltyWidgets
                        // CaptionedText(
                        //   captionText: "Late Shot",
                        //   text: "${_score!.lateShot}",
                        // ),
                        // SizedBox(width: 12),
                        // CaptionedText(
                        //   captionText: "Extra Shot",
                        //   text: "${_score!.extraShot}",
                        // ),
                        // SizedBox(width: 12),
                        // CaptionedText(
                        //   captionText: "Extra Hit",
                        //   text: "${_score!.extraHit}",
                        // ),
                        // SizedBox(width: 12),
                        // CaptionedText(
                        //   captionText: "Other",
                        //   text: "${_score!.otherPenalty}",
                        // )
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 5),
                Text(_scoreError),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildButtons(),
                )
              ]
          ),
        ),
      ),
    );
  }

  String _getPercentScoreText() {
    if(_edited) return "n/a (rescore)";
    else return "${widget.stageScore!.points.toStringAsFixed(2)} (${widget.stageScore!.ratio.asPercentage()}%)";
  }

  List<Widget> _buildButtons() {
    if(_edited) {
      return [
        TextButton(
          child: Text("APPLY"),
          onPressed: () {
            if(widget.stageScore != null) {
              _validateScore();
              _updateScore();
            }
            else {
              setState(() {
                _edited = true;
              });
            }
          },
        ),
        Tooltip(
          message: "Close this dialog and rescore the match.",
          child: TextButton(
            child: Text("RESCORE"),
            onPressed: () {
              Navigator.of(context).pop(ShooterDialogAction(scoreEdit: ScoreEdit(wholeMatch: _wholeMatchChange, rescore: true)));
            },
          ),
        )
      ];
    }
    else {
      return [
        TextButton(
          child: Text("APPLY"),
          onPressed: () {
            if(widget.stageScore != null) {
              _validateScore();
              _updateScore();
            }
            else {
              setState(() {
                _edited = true;
              });
            }
          },
        ),
        TextButton(
          child: Text("CLOSE"),
          onPressed: () {
            Navigator.of(context).pop(ShooterDialogAction());
          },
        )
      ];
    }
  }

  void _updateFromUI(RawScore score) {
    String timeText = _timeController.text.isEmpty ? "1.0" : _timeController.text;
    if(timeText.endsWith(".")) timeText += "0";

    score.rawTime = double.parse(timeText);

    for(var event in _targetControllers.keys) {
      var text = _targetControllers[event]!.text;
      if(text.isEmpty) text = "0";
      score.targetEvents[event] = int.parse(text);
    }

    for(var event in _penaltyControllers.keys) {
      var text = _penaltyControllers[event]!.text;
      if(text.isEmpty) text = "0";
      score.penaltyEvents[event] = int.parse(text);
    }
  }

  bool _validateScore() {
    RawScore s = _score.copy();
    _updateFromUI(s);

    var sum = 0;
    for(var event in s.targetEvents.keys) {
      if(event.pointChange > 0) {
        sum += s.targetEvents[event]!;
      }
    }
    var minRounds = widget.stageScore!.stage.minRounds;
    if(sum > minRounds) {
      setState(() {
        _scoreError = "Too many scoring hits! $sum vs. $minRounds.";
      });
      return false;
    }
    else if(sum < minRounds) {
      setState(() {
        _scoreError = "Too few hits, assuming ${minRounds - sum} NPM";
      });
    }
    else {
      setState(() {
        _scoreError = "";
      });
    }

    return true;
  }

  void _updateScore() {
    _updateFromUI(_score);

    setState(() {
      widget.stageScore!.score = widget.stageScore!.score;
      _edited = true;
    });
  }

  Widget _buildShooterLink(BuildContext context, MatchEntry shooter) {
    var children = <Widget>[];
    if(shooter.originalMemberNumber != "") {
      children.add(ClickableLink(
        url: Uri.parse("https://uspsa.org/classification/${shooter.originalMemberNumber}"),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${shooter.getName()} - ${shooter.division?.displayName ?? "NO DIVISION"} ${shooter.classification?.displayName}",
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
      ));
    }
    else {
      children.add(Text(
        "${shooter.getName()} - ${shooter.division?.displayName ?? "NO DIVISION"} ${shooter.classification?.displayName ?? "NO CLASSIFICATION"}",
        style: Theme.of(context).textTheme.headline6,
      ));
    }

    var editButton = IconButton(icon: Icon(Icons.edit), onPressed: () async {
      var newName = await showDialog<List<String>>(context: context, builder: (context) {
        var firstNameController = TextEditingController(text: shooter.firstName);
        var lastNameController = TextEditingController(text: shooter.lastName);
        return AlertDialog(
          title: Text("Change Shooter Name"),
          content: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: firstNameController,
                  decoration: InputDecoration(
                    labelText: "First Name",
                  ),
                )
              ),
              Expanded(
                child: TextFormField(
                  controller: lastNameController,
                  decoration: InputDecoration(
                    labelText: "Last Name",
                  ),
                )
              )
            ],
          ),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop([firstNameController.text, lastNameController.text]);
              },
            )
          ],
        );
      });

      if(newName != null) {
        setState(() {
          shooter.firstName = newName[0];
          shooter.lastName = newName[1];
        });
      }
    });

    children.add(editButton);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class ScoreEdit {
  final bool wholeMatch;
  final bool rescore;

  ScoreEdit({required this.wholeMatch, required this.rescore});
  const ScoreEdit.empty() : wholeMatch = false, rescore = false;
}