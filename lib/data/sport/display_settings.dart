/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

class SportDisplaySettings {
  /// Whether to display classification in overviews etc.
  bool showClassification;

  /// The columns to display
  List<ColumnGroup> scoreColumns;

  /// Whether scoring events default to suffix display, like USPSA.
  ///
  /// If true: "12A"
  /// If false: "-1: 4"
  bool eventNamesAsSuffix;

  SportDisplaySettings({
    required this.scoreColumns,
    this.showClassification = true,
    this.eventNamesAsSuffix = true,
  });

  factory SportDisplaySettings.defaultForSport(Sport sport, {PowerFactor? powerFactor}) {
    if(powerFactor == null) powerFactor = sport.defaultPowerFactor;

    if(sport.type.uspsaStyleDisplay) {
      List<ScoringEventGroup> positiveGroups = [];
      List<ScoringEvent> neutralEvents = [];
      Map<int, List<ScoringEvent>> negativeEvents = {};
      for(var e in powerFactor.targetEvents.values) {
        if (e.pointChange != 0) {
          positiveGroups.add(ScoringEventGroup.single(e));
        }
        else {
          neutralEvents.add(e);
        }
      }
      for(var e in powerFactor.penaltyEvents.values) {
        negativeEvents.addToList(e.pointChange, e);
      }

      ScoringEventGroup? neutralGroup;
      if(neutralEvents.isNotEmpty) {
        neutralGroup = ScoringEventGroup(events: neutralEvents, displayIfNoEvents: false);
      }

      List<ScoringEventGroup> negativeGroups = [];
      for(var eventsByValue in negativeEvents.values) {
        if(eventsByValue.length > 1) {
          negativeGroups.add(ScoringEventGroup(
            events: eventsByValue,
            displayIfNoEvents: true,
          ));
        }
        else {
          negativeGroups.add(ScoringEventGroup.single(eventsByValue.first, displayIfNoEvents: true));
        }
      }

      return SportDisplaySettings(scoreColumns: [
        ColumnGroup(
          headerLabel: "Hits",
          eventGroups: [
            ...positiveGroups,
            ...negativeGroups,
            if(neutralGroup != null) neutralGroup,
          ]
        )
      ]);
    }
    else {
      List<ColumnGroup> groups = [];
      // Events that get displayed in a single hits/score column.
      List<ScoringEvent> groupedEvents = [];

      if(sport.type.isPoints) {
        // For points, display USPSA-style, with prefix instead.
        for(var e in powerFactor.targetEvents.values) {
          groupedEvents.add(e);
        }

        var eventGroups = groupedEvents.map((e) =>
          ScoringEventGroup.single(e, displayIfNoEvents: false),
        ).toList();

        groups.add(ColumnGroup(
          headerLabel: "Hits",
          labelAsSuffix: false,
          eventGroups: eventGroups,
        ));
      }
      else {
        // For time plus, display IDPA-style, with one column coalescing
        // all target events

        for(var e in powerFactor.targetEvents.values) {
          groupedEvents.add(e);
        }
        
        var eventGroup = ScoringEventGroup(
          events: groupedEvents,
          displayIfNoEvents: true,
          label: "",
        );

        groups.add(ColumnGroup(
          eventGroups: [eventGroup],
          headerLabel: "Points Down",
          labelAsSuffix: true,
          mode: ColumnMode.totalTime,
        ));
      }

      // Time plus and points display penalties pretty similarly.
      var mode = sport.type.isPoints ? ColumnMode.totalPoints : ColumnMode.totalTime;
      for(var e in powerFactor.penaltyEvents.values) {
        groups.add(ColumnGroup(
          headerLabel: e.displayName,
          eventGroups: [ScoringEventGroup.single(e, displayIfNoEvents: true, label: "")],
          labelAsSuffix: false,
          mode: mode,
        ));
      }
      
      return SportDisplaySettings(
        scoreColumns: groups,
      );
    }
  }
}

enum ColumnMode {
  count,
  totalPoints,
  totalTime,
}

/// A ColumnGroup combines multiple scoring events into one column in the
/// score display UI.
///
/// For instance, USPSA-style score display has one column:
/// 123A 35C 2D 1M
///
/// IDPA-style score display may have several columns:
/// PE | Non-Threat | Points Down
/// 9s   15s          28s
class ColumnGroup {
  String headerLabel;
  String? headerTooltip;

  ColumnMode mode;

  /// If true, events will be displayed in standard USPSA style: "3A"
  /// If false, event names will prefix the display output: "-3: 15s"
  /// labelAsSuffix makes sense mainly with [ColumnMode.count] and very
  /// short [shortDisplayName] on ScoringEvent.
  bool labelAsSuffix;

  /// The scoring event groups to display in this column.
  List<ScoringEventGroup> eventGroups;

  ColumnGroup({required this.headerLabel, required this.eventGroups, this.mode = ColumnMode.count, this.labelAsSuffix = true, this.headerTooltip});

  String format(RawScore score) {
    var strings = eventGroups.map((e) => e.format(score, mode, labelAsSuffix)).toList();
    strings.removeWhere((element) => element.isEmpty);
    return strings.join(" ");
  }
}

/// A ScoringEventGroup combines multiple scoring events into one entry in a column
/// group.
///
/// For instance, IDPA-style score display coalesces -1, -3, and Miss events into a single
/// 'accuracy' column.
class ScoringEventGroup {
  List<ScoringEvent> events;

  String? _label;
  String get label => _label ?? events.firstOrNull?.shortDisplayName ?? "!!";

  bool displayIfNoEvents;

  ScoringEventGroup({required this.events, this.displayIfNoEvents = true, String? label}) : this._label = label;

  /// Construct a ScoringEventGroup for a single event.
  ScoringEventGroup.single(ScoringEvent event, {this.displayIfNoEvents = true, String? label}) :
      this.events = [event],
      this._label = label;

  String format(RawScore score, ColumnMode mode, bool labelAsSuffix) {
    int count = 0;
    double timeValue = 0.0;
    int pointValue = 0;

    for(var eventPrototype in events) {
      var tEvent = score.targetEvents.keys.lookupByName(eventPrototype.name);
      var pEvent = score.penaltyEvents.keys.lookupByName(eventPrototype.name);
      ScoringEvent? foundEvent;

      int innerCount = 0;
      if(tEvent != null) {
        innerCount += score.targetEvents[tEvent] ?? 0;
        foundEvent = tEvent;
      }
      else if(pEvent != null) {
        innerCount += score.penaltyEvents[pEvent] ?? 0;
        foundEvent = pEvent;
      }

      if(foundEvent != null) {
        timeValue += foundEvent.timeChange * innerCount;
        pointValue += foundEvent.pointChange * innerCount;
        count += innerCount;
      }
    }

    if(count == 0 && !displayIfNoEvents) return "";

    String out = "";
    if(!labelAsSuffix && !label.isEmpty) {
      out += "$label: ";
    }

    out += switch(mode) {
      ColumnMode.count => "$count",
      ColumnMode.totalPoints => "$pointValue",
      ColumnMode.totalTime => "${timeValue.toStringAsFixed(2)}",
    };

    if(labelAsSuffix && !label.isEmpty) {
      out += "$label";
    }

    return out;
  }
}