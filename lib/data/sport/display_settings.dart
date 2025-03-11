/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Settings for how a sport's match results should be displayed.
///
/// [SportDisplaySettings.defaultForSport] creates a passably sensible
/// default.
class SportDisplaySettings {
  /// Whether to display classification in overviews etc.
  bool showClassification;
  bool showTime;
  bool showPowerFactor;

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
    this.showTime = true,
    this.showPowerFactor = true,
  });

  factory SportDisplaySettings.defaultForSport(Sport sport, {
    PowerFactor? powerFactor,
    bool showPowerFactor = true,
  }) {
    if(powerFactor == null) powerFactor = sport.defaultPowerFactor;

    if(sport.type.uspsaStyleDisplay) {
      List<ScoringEventGroup> positiveGroups = [];
      List<ScoringEvent> neutralEvents = [];
      Map<int, List<ScoringEvent>> negativeEvents = {};
      for(var e in powerFactor.targetEvents.values) {
        if (e.pointChange != 0 || sport.type.isTimePlus) { // display all target events for time plus
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
          negativeGroups.add(ScoringEventGroup.single(eventsByValue.first, displayIfNoEvents: false));
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
        showPowerFactor: showPowerFactor,
      );
    }
  }

  String formatTooltip(Sport sport, RawScore score) {
    List<String> scoreComponents = [];
    for(var column in scoreColumns) {
      scoreComponents.add(column.format(sport, score));
    }

    if(showTime) {
      scoreComponents.add("${score.finalTime.toStringAsFixed(2)}s");
    }

    return scoreComponents.join(" ");
  }
}

/// What a ColumnGroup should display for its ScoringEventGroups.
enum ColumnMode {
  /// Display the count of events in each subordinate group.
  count,
  /// Display the total points for each subordinate group.
  totalPoints,
  /// Display the total time for each subordinate group.
  totalTime,
}

/// What a ColumnGroup should do with dynamic score events, i.e. those
/// that aren't listed in the sport's definition.
enum DynamicEventMode {
  /// Hide all dynamic events.
  hideUnknown,
  /// Include positive events.
  ///
  /// Positive means 'good', not necessarily 'numerically positive'. A time bonus
  /// in a time-plus sport is a positive event with a negative time change.
  includePositive,
  /// Include negative events.
  ///
  /// Negative means 'bad', not necessarily 'numerically negative'. A penalty
  /// in a time-plus sport is a negative event with a positive time change.
  includeNegative,
  /// Include all events.
  includeAll,
  /// Include all events except the given events.
  includeAllExcept,
  /// Include all positive events except the given events.
  includePositiveExcept,
  /// Include all negative events except the given events.
  includeNegativeExcept;

  /// Whether this mode can include dynamic events.
  bool get inclusive => this != hideUnknown;

  bool shouldInclude(Sport sport, ScoringEvent event, {List<ScoringEvent> excluded = const []}) {
    switch(this) {
      case DynamicEventMode.hideUnknown:
        return false;
      case DynamicEventMode.includePositive:
        return event.isPositive(sport);
      case DynamicEventMode.includeNegative:
        return !event.isPositive(sport);
      case DynamicEventMode.includeAll:
        return true;
      case DynamicEventMode.includeAllExcept:
        return !excluded.contains(event);
      case DynamicEventMode.includePositiveExcept:
        return event.isPositive(sport) && !excluded.contains(event);
      case DynamicEventMode.includeNegativeExcept:
        return !event.isPositive(sport) && !excluded.contains(event);
    }
  }
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

  ColumnGroup({
    required this.headerLabel,
    required this.eventGroups,
    this.mode = ColumnMode.count,
    this.labelAsSuffix = true,
    this.headerTooltip,
  });

  String format(Sport sport, RawScore score) {
    var strings = eventGroups.map((e) => e.format(
      sport: sport,
      score: score,
      mode: mode,
      labelAsSuffix: labelAsSuffix,
    )).toList();
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

  DynamicEventMode dynamicEventMode;
  List<ScoringEvent> excludeEvents;

  ScoringEventGroup({
    required this.events,
    this.displayIfNoEvents = true,
    String? label,
    this.dynamicEventMode = DynamicEventMode.hideUnknown,
      this.excludeEvents = const [],
  }) : this._label = label;

  /// Construct a ScoringEventGroup for a single event.
  ScoringEventGroup.single(
    ScoringEvent event,
    {
      this.displayIfNoEvents = true,
      String? label,
      this.dynamicEventMode = DynamicEventMode.hideUnknown,
      this.excludeEvents = const [],
    }
  ) :
      this.events = [event],
      this._label = label;

  String format({
    required Sport sport,
    required RawScore score,
    required ColumnMode mode,
    required bool labelAsSuffix,
  }) {
    int count = 0;
    double timeValue = 0.0;
    int pointValue = 0;

    Set<ScoringEvent> usedEvents = events.toSet();
    if(dynamicEventMode.inclusive) {
      for(var e in score.targetEvents.keys) {
        if(!sport.defaultPowerFactor.targetEvents.containsValue(e)) {
          if(dynamicEventMode.shouldInclude(sport, e, excluded: excludeEvents)) {
            usedEvents.add(e);
          }
        }
      }

      for(var e in score.penaltyEvents.keys) {
        if(!sport.defaultPowerFactor.penaltyEvents.containsValue(e)) {
          if(dynamicEventMode.shouldInclude(sport, e, excluded: excludeEvents)) {
            usedEvents.add(e);
          }
        }
      }
    }

    Set<String> processedVariableValueEvents = {};

    for(var eventPrototype in usedEvents) {
      List<ScoringEvent> foundEvents = [];
      var variableEvent = eventPrototype.variableValue;
      if(variableEvent) {
        // Variable events are processed by name rathern than specifically
        // event, so to avoid double-counting, track which names have been
        // processed.
        if(processedVariableValueEvents.contains(eventPrototype.name)) {
          continue;
        }
        processedVariableValueEvents.add(eventPrototype.name);

        var targetEvents = score.targetEvents.keys.lookupAllByName(eventPrototype.name);
        var penaltyEvents = score.penaltyEvents.keys.lookupAllByName(eventPrototype.name);
        if(targetEvents.isNotEmpty) {
          foundEvents.addAll(targetEvents);
        }
        else {
          foundEvents.addAll(penaltyEvents);
        }
      }
      else {
        var tEvent = score.targetEvents.keys.lookupByName(eventPrototype.name);
        var pEvent = score.penaltyEvents.keys.lookupByName(eventPrototype.name);
        if(tEvent != null) {
          foundEvents.add(tEvent);
        }
        else if(pEvent != null) {
          foundEvents.add(pEvent);
        }
      }

      if(eventPrototype.name == "X") {
        print("break");
      }

      for(var event in foundEvents) {
        int innerCount = 0;
        innerCount += score.targetEvents[event] ?? 0;
        innerCount += score.penaltyEvents[event] ?? 0;

        var timeChange = event.timeChange;
        var pointChange = event.pointChange;
        if(score.scoringOverrides.containsKey(event.name)) {
          var override = score.scoringOverrides[event.name]!;
          timeChange = override.timeChangeOverride ?? timeChange;
          pointChange = override.pointChangeOverride ?? pointChange;
        }

        timeValue += timeChange * innerCount;
        pointValue += pointChange * innerCount;
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
