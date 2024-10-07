/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';

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
  late TextEditingController _updateIntervalController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _updateIntervalController = TextEditingController(text: widget.tickerModel.updateInterval.toString());
  }

  @override
  void dispose() {
    _updateIntervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _updateIntervalController,
          decoration: InputDecoration(
            labelText: "Update interval (seconds)",
            errorText: _errorText,
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            int? interval = int.tryParse(value);
            if (interval != null && interval > 0) {
              widget.tickerModel.updateInterval = interval;
              setState(() {
                _errorText = null;
              });
            } else {
              setState(() {
                _errorText = "Please enter a valid positive integer";
              });
            }
          },
        ),
      ],
    );
  }
}
