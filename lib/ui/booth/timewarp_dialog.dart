/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';

class TimewarpDialog extends StatefulWidget {
  const TimewarpDialog({super.key, required this.match, required this.initialDateTime});

  final ShootingMatch match;
  final DateTime initialDateTime;

  @override
  State<TimewarpDialog> createState() => _TimewarpDialogState();

  static Future<DateTime?> show(BuildContext context, {required ShootingMatch match, DateTime? initialDateTime}) {
    initialDateTime ??= DateTime.now();
    return showDialog<DateTime>(
      context: context,
      builder: (context) => TimewarpDialog(match: match, initialDateTime: initialDateTime!),
      barrierDismissible: false,
    );
  }
}

class _TimewarpDialogState extends State<TimewarpDialog> {
  late DateTime selectedDateTime;
  late DateTime earliestDateTime;
  late DateTime latestDateTime;

  @override
  void initState() {
    super.initState();
    selectedDateTime = widget.initialDateTime;
    earliestDateTime = _findEarliestScoreDate();
    latestDateTime = DateTime.now();
  }

  DateTime _findEarliestScoreDate() {
    DateTime earliest = DateTime.now();
    for (var entry in widget.match.shooters) {
      for (var score in entry.scores.values) {
        if (score.modified != null && score.modified!.isBefore(earliest)) {
          earliest = score.modified!;
        }
      }
    }
    return earliest;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Time warp"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Select a date and time to view scores as of that time."),
          SizedBox(height: 16),
          ElevatedButton(
            child: Text(DateFormat.yMd().format(selectedDateTime)),
            onPressed: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDateTime,
                firstDate: earliestDateTime,
                lastDate: latestDateTime,
              );
              if (picked != null && picked != selectedDateTime) {
                setState(() {
                  selectedDateTime = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    selectedDateTime.hour,
                    selectedDateTime.minute,
                  );
                });
              }
            },
          ),
          SizedBox(height: 8),
          ElevatedButton(
            child: Text(DateFormat.Hm().format(selectedDateTime)),
            onPressed: () async {
              final TimeOfDay? picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(selectedDateTime),
              );
              if (picked != null) {
                setState(() {
                  selectedDateTime = DateTime(
                    selectedDateTime.year,
                    selectedDateTime.month,
                    selectedDateTime.day,
                    picked.hour,
                    picked.minute,
                  );
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CLEAR TIMEWARP")),
        TextButton(onPressed: () => Navigator.of(context).pop(selectedDateTime), child: const Text("APPLY")),
      ],
    );
  }
}
