/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("TimewarpDialog");

class TimewarpDialog extends StatefulWidget {
  const TimewarpDialog({super.key, required this.match, this.initialDateTime});

  final ShootingMatch match;
  final DateTime? initialDateTime;

  @override
  State<TimewarpDialog> createState() => _TimewarpDialogState();

  static Future<DateTime?> show(BuildContext context, {required ShootingMatch match, DateTime? initialDateTime}) {
    return showDialog<DateTime>(
      context: context,
      builder: (context) => TimewarpDialog(match: match, initialDateTime: initialDateTime),
      barrierDismissible: false,
    );
  }
}

class _TimewarpDialogState extends State<TimewarpDialog> {
  // All DateTimes are stored in UTC.
  // They are converted to the viewer's local time for display, both in this dialog and in the
  // timewarp button in the booth UI.

  late DateTime selectedDateTime;
  late DateTime earliestDateTime;
  late DateTime latestDateTime;

  @override
  void initState() {
    super.initState();
    earliestDateTime = _findEarliestScoreDate();
    latestDateTime = _findLatestScoreDate(earliestDateTime);
    if(widget.initialDateTime != null && widget.initialDateTime!.isAfter(earliestDateTime) && widget.initialDateTime!.isBefore(latestDateTime)) {
      selectedDateTime = widget.initialDateTime!;
    }
    else {
      selectedDateTime = earliestDateTime;
    }
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
    return earliest.toUtc();
  }

  DateTime _findLatestScoreDate(DateTime earliest) {
    DateTime latest = earliest;
    for (var entry in widget.match.shooters) {
      for (var score in entry.scores.values) {
        if (score.modified != null && score.modified!.isAfter(latest)) {
          latest = score.modified!;
        }
      }
    }
    return latest.toUtc();
  }

  List<Widget> _dayButtons() {
    Map<int, DateTime> daysToFirstScoreTimes = {};

    // Estimate the match start time by looking for the largest
    // contiguous block of hours with no scores, and then
    // choosing the last hour of that block.
    var histogram = _scoreTimeHistogram();
    var matchStartTime = _estimatedMatchStartTime(histogram);

    // This time is guaranteed to be before any score on the first day.
    // Therefore, given that scores are generally recorded in a block of at
    // most about 16-18 hours, any score on the first day will have a difference
    // in days of less than 1, any score on the second day will have a difference
    // of greater than 1 and less than 2, and so on.
    var matchStartDateTime = earliestDateTime.copyWith(hour: matchStartTime, minute: 0, second: 0).toLocal();

    for(var entry in widget.match.shooters) {
      for(var score in entry.scores.values) {
        var t = score.modified;
        if(t != null) {
          var dayDifference = t.difference(matchStartDateTime).inSeconds;
          var dayFraction = dayDifference / 86400;
          var dayOfMatch = dayFraction.floor();

          if(daysToFirstScoreTimes[dayOfMatch] == null || t.isBefore(daysToFirstScoreTimes[dayOfMatch]!)) {
            daysToFirstScoreTimes[dayOfMatch] = t;
          }
        }
      }
    }

    List<Widget> buttons = [];
    for(var day in daysToFirstScoreTimes.keys.sorted((a, b) => a.compareTo(b))) {
      if(day < 0) continue;
      buttons.add(
        Tooltip(
          message: yMdHm(daysToFirstScoreTimes[day]!.toLocal()),
          child: TextButton(
            child: Text("Day ${day + 1}"),
            onPressed: () {
              Navigator.of(context).pop(daysToFirstScoreTimes[day]);
            },
          ),
        )
      );
    }
    return buttons;
  }

  /// Get a histogram of the number of scores during each hour of the day.
  /// 
  /// All DateTimes will have YMD 0, 0, 0, and the time will be truncated to the hour.
  Map<int, int> _scoreTimeHistogram() {
    Map<int, int> histogram = {};
    for(int i = 0; i < 24; i++) {
      histogram[i] = 0;
    }

    for(var entry in widget.match.shooters) {
      for(var score in entry.scores.values) {
        if(score.modified != null) {
          histogram.increment(score.modified!.hour);
        }
      }
    }

    for(var hour in histogram.keys) {
      _log.vv("$hour: ${histogram[hour]}");
    }

    return histogram;
  }

  /// Estimate the match start time by finding the last hour in the largest
  /// contiguous block of hours with no scores.
  /// 
  /// To find contiguous blocks that may cross the midnight hour, we run
  /// the algorithm twice, once starting at the first hour and once starting
  /// at the middle hour.
  int _estimatedMatchStartTime(Map<int, int> histogram) {
    var sortedHours = histogram.keys.toList();
    sortedHours.sort((a, b) => a.compareTo(b));

    var largestContiguousBlockStart = sortedHours.first;
    var largestContiguousBlockLength = 0;
    var currentContiguousBlockStart = sortedHours.first;
    var currentContiguousBlockLength = 0;

    for(var hour in sortedHours) {
      if(histogram[hour] == 0) {
        currentContiguousBlockLength++;
      }
      else {
        _log.vv("Block from $currentContiguousBlockStart to $hour has $currentContiguousBlockLength hours");
        if(currentContiguousBlockLength > largestContiguousBlockLength) {
          largestContiguousBlockLength = currentContiguousBlockLength;
          largestContiguousBlockStart = currentContiguousBlockStart;
        }
        currentContiguousBlockStart = hour;
        currentContiguousBlockLength = 0;
      }
    }

    _log.vv("Restarting from center");

    var centerStartHours = [
      ...sortedHours.sublist(sortedHours.length ~/ 2),
      ...sortedHours.sublist(0, sortedHours.length ~/ 2),
    ];
    currentContiguousBlockStart = centerStartHours.first;
    currentContiguousBlockLength = 0;

    for(var hour in centerStartHours) {
      if(histogram[hour] == 0) {
        currentContiguousBlockLength++;
      }
      else {
        _log.vv("Block from $currentContiguousBlockStart to $hour has $currentContiguousBlockLength hours");
        if(currentContiguousBlockLength > largestContiguousBlockLength) {
          largestContiguousBlockLength = currentContiguousBlockLength;
          largestContiguousBlockStart = currentContiguousBlockStart;
        }
        currentContiguousBlockStart = hour;
        currentContiguousBlockLength = 0;
      }
    }

    var result = (largestContiguousBlockStart + largestContiguousBlockLength) % 24;
    if(result < 0) result = 24 + result;

    _log.v("Returning $result");

    return result;
  }

  @override
  Widget build(BuildContext context) {
    var dayButtons = _dayButtons();

    var localSelectedDateTime = selectedDateTime.toLocal();

    return AlertDialog(
      title: const Text("Time warp"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Select a date and time to view scores as of that time."),
          SizedBox(height: 8),
          Text("The first and last score times in your time zone are:"),
          Text("${yMdHm(earliestDateTime.toLocal())} and ${yMdHm(latestDateTime.toLocal())}."),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                child: Text(DateFormat.yMd().format(localSelectedDateTime)),
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: localSelectedDateTime,
                    firstDate: earliestDateTime.toLocal(),
                    lastDate: latestDateTime.toLocal(),
                    initialEntryMode: DatePickerEntryMode.input,
                  );
                  if (picked != null && picked != localSelectedDateTime) {
                    setState(() {
                      selectedDateTime = DateTime.utc(
                        picked.year,
                        picked.month,
                        picked.day,
                        localSelectedDateTime.toUtc().hour,
                        localSelectedDateTime.toUtc().minute,
                      );
                    });
                  }
                },
              ),
              SizedBox(width: 8),
              ElevatedButton(
                child: Text(DateFormat.Hm().format(localSelectedDateTime)),
                onPressed: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(localSelectedDateTime),
                    initialEntryMode: TimePickerEntryMode.input,
                  );
                  if (picked != null) {
                    setState(() {
                      selectedDateTime = DateTime(
                        localSelectedDateTime.year,
                        localSelectedDateTime.month,
                        localSelectedDateTime.day,
                        picked.hour,
                        picked.minute,
                      ).toUtc();
                    });
                  }
                },
              )
            ],
          ),
          if(dayButtons.isNotEmpty) SizedBox(height: 16),
          if(dayButtons.isNotEmpty) Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...dayButtons,
            ],
          )
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("CLEAR TIME WARP")),
        TextButton(onPressed: () => Navigator.of(context).pop(selectedDateTime), child: const Text("APPLY")),
      ],
    );
  }
}
