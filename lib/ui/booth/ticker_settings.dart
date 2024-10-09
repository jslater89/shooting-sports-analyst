/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/ui/booth/ticker_criteria.dart';

/// TickerSettingsDialog is a modal host for [TickerSettingsWidget].
class TickerSettingsDialog extends StatelessWidget {
  const TickerSettingsDialog({super.key, required this.tickerModel});

  final BoothTickerModel tickerModel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Ticker Settings"),
      content: TickerSettingsWidget(tickerModel: tickerModel),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CANCEL")),
        TextButton(onPressed: () => Navigator.of(context).pop(tickerModel), child: const Text("SAVE")),
      ],
    );
  }

  static Future<BoothTickerModel?> show(BuildContext context, {required BoothTickerModel tickerModel}) {
    return showDialog<BoothTickerModel>(
      context: context,
      builder: (context) => TickerSettingsDialog(tickerModel: tickerModel),
      barrierDismissible: false,
    );
  }
}

/// TickerSettingsWidget edits the provided BoothTickerModel.
/// Edits happen in place, so use BoothTickerModel.copyFrom to get a copy if confirm/discard is needed.
class TickerSettingsWidget extends StatefulWidget {
  const TickerSettingsWidget({super.key, required this.tickerModel});

  final BoothTickerModel tickerModel;

  @override
  State<TickerSettingsWidget> createState() => _TickerSettingsWidgetState();
}

class _TickerSettingsWidgetState extends State<TickerSettingsWidget> {
  String? _updateIntervalErrorText;
  String? _tickerSpeedErrorText;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          initialValue: widget.tickerModel.updateInterval.toString(),
          decoration: InputDecoration(
            labelText: "Update interval (seconds)",
            errorText: _updateIntervalErrorText,
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            int? interval = int.tryParse(value);
            if (interval != null && interval > 0) {
              widget.tickerModel.updateInterval = interval;
              setState(() {
                _updateIntervalErrorText = null;
              });
            } else {
              setState(() {
                _updateIntervalErrorText = "Please enter a valid positive integer";
              });
            }
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: widget.tickerModel.tickerSpeed.toString(),
          decoration: InputDecoration(
            labelText: "Ticker speed (pixels per second)",
            errorText: _tickerSpeedErrorText,
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            int? speed = int.tryParse(value);
            if (speed != null && speed > 0 && speed < 200) {
              setState(() {
                widget.tickerModel.tickerSpeed = speed;
                _tickerSpeedErrorText = null;
              });
            } else {
              setState(() {
                _tickerSpeedErrorText = "Please enter a number between 1 and 199";
              });
            }
          },
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Text("Global ticker alerts", style: Theme.of(context).textTheme.labelMedium!.copyWith(color: Colors.grey[600]), textAlign: TextAlign.left),
          ],
        ),
        SizedBox(height: 8),
        ..._buildTickerAlerts(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add),
                  Text("Add")
                ],
              ),
              onPressed: () async {
                TickerEventCriterion? newAlert = TickerEventCriterion(
                  type: MatchLeadChange(),
                  priority: TickerPriority.high,
                );
                newAlert = await TickerCriterionEditDialog.show(context, criterion: newAlert);
                if(newAlert != null) {
                  widget.tickerModel.globalTickerCriteria.add(newAlert);
                  setState(() {});
                }
              },
            ),
            TextButton(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restore),
                  Text("Restore defaults")
                ],
              ),
              onPressed: () async {
                widget.tickerModel.globalTickerCriteria = [
                  ...BoothTickerModel.defaultTickerCriteria,
                ];
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildTickerAlerts() {
    List<Widget> widgets = [];
    for(var c in widget.tickerModel.globalTickerCriteria) {
      widgets.add(SizedBox(
        width: 350,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: Text(c.type.uiLabel, style: c.priority.textStyle)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  child: Icon(Icons.settings),
                  onPressed: () async {
                    var updatedCriterion = await TickerCriterionEditDialog.show(context, criterion: c);
                    setState(() {});
                  }
                ),
                TextButton(
                  child: Icon(Icons.remove),
                  onPressed: () {
                    widget.tickerModel.globalTickerCriteria.remove(c);
                    setState(() {});
                  },
                ),
              ],
            )
          ]
        ),
      ));
    }
    return widgets;
  }
}

class TickerCriterionEditDialog extends StatefulWidget {
  final TickerEventCriterion criterion;

  const TickerCriterionEditDialog({Key? key, required this.criterion}) : super(key: key);

  @override
  _TickerCriterionEditDialogState createState() => _TickerCriterionEditDialogState();

  static Future<TickerEventCriterion?> show(BuildContext context, {required TickerEventCriterion criterion}) {
    return showDialog<TickerEventCriterion>(
      context: context,
      builder: (context) => TickerCriterionEditDialog(criterion: criterion),
    );
  }
}

class _TickerCriterionEditDialogState extends State<TickerCriterionEditDialog> {
  late TickerEventCriterion _editedCriterion;

  @override
  void initState() {
    super.initState();
    _editedCriterion = TickerEventCriterion(
      type: widget.criterion.type,
      priority: widget.criterion.priority,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit ticker alert"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _editedCriterion.type.typeName,
              items: [
                DropdownMenuItem(value: ExtremeScore.extremeScoreName, child: Text("Extreme score")),
                DropdownMenuItem(value: MatchLeadChange.matchLeadChangeName, child: Text("Match lead change")),
                DropdownMenuItem(value: StageLeadChange.stageLeadChangeName, child: Text("Stage lead change")),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _editedCriterion.type = switch(newValue) {
                      ExtremeScore.extremeScoreName => ExtremeScore.above(changeThreshold: 90),
                      MatchLeadChange.matchLeadChangeName => MatchLeadChange(),
                      StageLeadChange.stageLeadChangeName => StageLeadChange(),
                      _ => throw Exception("Invalid event type"),
                    };
                  });
                }
              },
              decoration: InputDecoration(labelText: "Event Type"),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<TickerPriority>(
              value: _editedCriterion.priority,
              items: TickerPriority.values.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Text(priority.uiLabel),
                );
              }).toList(),
              onChanged: (TickerPriority? newValue) {
                if (newValue != null) {
                  setState(() {
                    _editedCriterion.priority = newValue;
                  });
                }
              },
              decoration: InputDecoration(labelText: "Priority"),
            ),
            SizedBox(height: 16),
            if (_editedCriterion.type.hasSettingsUI)
              _editedCriterion.type.buildSettingsUI(context)!,
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("CANCEL"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_editedCriterion),
          child: Text("SAVE"),
        ),
      ],
    );
  }
}

