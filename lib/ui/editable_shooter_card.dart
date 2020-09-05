// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/ui/captioned_text.dart';

/// EditableShooterCard should _not_ be barrier-dismissable.
class EditableShooterCard extends StatefulWidget {
  final RelativeMatchScore matchScore;
  final RelativeScore stageScore;
  final bool scoreDQ;

  const EditableShooterCard({Key key, this.matchScore, this.stageScore, this.scoreDQ = true}) : super(key: key);

  @override
  _EditableShooterCardState createState() => _EditableShooterCardState();
}

class _EditableShooterCardState extends State<EditableShooterCard> {
  TextEditingController _timeController = TextEditingController();
  TextEditingController _aController = TextEditingController();
  TextEditingController _cController = TextEditingController();
  TextEditingController _dController = TextEditingController();
  TextEditingController _mController = TextEditingController();
  TextEditingController _nsController = TextEditingController();
  TextEditingController _procController = TextEditingController();

  bool _edited = false;

  String _scoreError = "";

  @override
  void initState() {
    super.initState();
    if(widget.matchScore != null) throw ArgumentError("Cannot edit match score; edit stage scores.");
    if(widget.stageScore == null) throw ArgumentError("Missing stage score.");

    _timeController.text = _score.time.toStringAsFixed(2);
    _aController.text = "${_score.a}";
    _cController.text = "${_score.c}";
    _dController.text = "${_score.d}";
    _mController.text = "${_score.m}";
    _nsController.text = "${_score.ns}";
    _procController.text = "${_score.procedural}";
  }

  Score get _score => widget.stageScore.score;

  @override
  Widget build(BuildContext context) {
    Shooter shooter = widget.stageScore.score.shooter;
    List<Widget> timeHolder = [];
    var stringTimes = widget.stageScore.score.stringTimes;

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
                  text: "${_score.getHitFactor(scoreDQ: widget.scoreDQ).toStringAsFixed(4)}",
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
                  Text("Round count: ${_score.stage.minRounds}"),
                  SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _aController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
                          ],
                          decoration: InputDecoration(
                              labelText: "A",
                              floatingLabelBehavior: FloatingLabelBehavior.always
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _cController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
                          ],
                          decoration: InputDecoration(
                              labelText: "C",
                              floatingLabelBehavior: FloatingLabelBehavior.always
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _dController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
                          ],
                          decoration: InputDecoration(
                              labelText: "D",
                              floatingLabelBehavior: FloatingLabelBehavior.always
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _mController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
                          ],
                          decoration: InputDecoration(
                              labelText: "M",
                              floatingLabelBehavior: FloatingLabelBehavior.always
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _nsController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
                          ],
                          decoration: InputDecoration(
                            labelText: "NS",
                            floatingLabelBehavior: FloatingLabelBehavior.always
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        width: 65,
                        child: TextField(
                          controller: _procController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r"[0-9]+")),
                          ],
                          decoration: InputDecoration(
                              labelText: "Procedural",
                              floatingLabelBehavior: FloatingLabelBehavior.always
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      CaptionedText(
                        captionText: "Late Shot",
                        text: "${_score.lateShot}",
                      ),
                      SizedBox(width: 12),
                      CaptionedText(
                        captionText: "Extra Shot",
                        text: "${_score.extraShot}",
                      ),
                      SizedBox(width: 12),
                      CaptionedText(
                        captionText: "Extra Hit",
                        text: "${_score.extraHit}",
                      ),
                      SizedBox(width: 12),
                      CaptionedText(
                        captionText: "Other",
                        text: "${_score.otherPenalty}",
                      )
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
    else return "${widget.stageScore.relativePoints.toStringAsFixed(2)} (${widget.stageScore.percent.asPercentage()}%)";
  }

  List<Widget> _buildButtons() {
    if(_edited) {
      return [
        FlatButton(
          child: Text("APPLY"),
          onPressed: () {
            _validateScore();
            _updateScore();
          },
        ),
        Tooltip(
          message: "Close this dialog and rescore the match.",
          child: FlatButton(
            child: Text("RESCORE"),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
        )
      ];
    }
    else {
      return [
        FlatButton(
          child: Text("APPLY"),
          onPressed: () {
            _validateScore();
            _updateScore();
          },
        ),
        FlatButton(
          child: Text("CLOSE"),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        )
      ];
    }
  }
  
  void _updateFromUI(Score score) {
    String timeText = _timeController.text.isEmpty ? "1.0" : _timeController.text;
    if(timeText.endsWith(".")) timeText += "0";

    String aText = _aController.text.isEmpty ? "0" : _aController.text;
    String cText = _cController.text.isEmpty ? "0" : _cController.text;
    String dText = _dController.text.isEmpty ? "0" : _dController.text;
    String mText = _mController.text.isEmpty ? "0" : _mController.text;
    String nsText = _nsController.text.isEmpty ? "0" : _nsController.text;
    String procText = _procController.text.isEmpty ? "0" : _procController.text;

    score.time = double.parse(timeText);
    score.a = int.parse(aText);
    score.c = int.parse(cText);
    score.d = int.parse(dText);
    score.m = int.parse(mText);
    score.ns = int.parse(nsText);
    score.procedural = int.parse(procText);
  }
  
  bool _validateScore() {
    Score s = _score.copy(_score.shooter, _score.stage);
    _updateFromUI(s);

    var sum = s.a + s.c + s.d + s.m;
    if(sum > _score.stage.minRounds) {
      setState(() {
        _scoreError = "Too many scoring hits! $sum vs. ${s.stage.minRounds}.";
      });
      return false;
    }
    else if(sum < _score.stage.minRounds) {
      setState(() {
        _scoreError = "Too few hits, assuming ${s.stage.minRounds - sum} NPM";
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
      widget.stageScore.score = widget.stageScore.score;
      _edited = true;
    });
  }

  Widget _buildShooterLink(BuildContext context, Shooter shooter) {
    if(shooter.memberNumber != null && shooter.memberNumber != "") {
      return GestureDetector(
        onTap: () {
          window.open("https://uspsa.org/classification/${shooter.memberNumber}", '_blank');
        },
        child: Text(
          "${shooter.getName()} - ${shooter.division.displayString()} ${shooter.classification.displayString()}",
          style: Theme.of(context).textTheme.headline6.copyWith(
            color: Theme.of(context).primaryColor,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    }
    return Text(
      "${shooter.getName()} - ${shooter.division.displayString()} ${shooter.classification.displayString()}",
      style: Theme.of(context).textTheme.headline6,
    );
  }
}