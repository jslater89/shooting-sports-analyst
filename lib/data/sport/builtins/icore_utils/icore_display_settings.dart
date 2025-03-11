/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/display_settings.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class IcoreDisplaySettings {
  static SportDisplaySettings create(Sport sport, {
    PowerFactor? powerFactor,
  }) {

    var pf = powerFactor ?? sport.defaultPowerFactor;

    var timeBonusEvents = pf.allEvents.values.where((e) => e.timeChange < 0).toList();
    var accuracyPenaltyEvents = pf.targetEvents.values.where((e) => e.timeChange > 0).toList();
    var otherPenaltyEvents = pf.penaltyEvents.values.where((e) => e.timeChange > 0).toList();

    ColumnGroup timeBonusColumn = ColumnGroup(
      headerLabel: "Bonus",
      mode: ColumnMode.totalTime,
      eventGroups: [
        ScoringEventGroup(
          events: timeBonusEvents,
          label: "",
          dynamicEventMode: DynamicEventMode.includePositive,
        ),
      ],
    );

    ColumnGroup accuracyPenaltyColumn = ColumnGroup(
      headerLabel: "B/C/M/NS",
      mode: ColumnMode.totalTime,
      eventGroups: [
        ScoringEventGroup(events: accuracyPenaltyEvents, label: ""),
      ],
    );

    ColumnGroup otherPenaltyColumn = ColumnGroup(
      headerLabel: "Penalty",
      mode: ColumnMode.totalTime,
      eventGroups: [
        ScoringEventGroup(
          events: otherPenaltyEvents,
          label: "",
          dynamicEventMode: DynamicEventMode.includeNegativeExcept,
          excludeEvents: accuracyPenaltyEvents,
        ),
      ],
    );

    List<ScoringEventGroup> hitGroups = [];
    // always show A/B/C/M/NS. Show X only if they have events.
    if(pf.targetEvents.lookupByName("X") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("X")!, displayIfNoEvents: false));
    }
    if(pf.targetEvents.lookupByName("A") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("A")!));
    }
    if(pf.targetEvents.lookupByName("B") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("B")!));
    }
    if(pf.targetEvents.lookupByName("C") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("C")!));
    }
    if(pf.targetEvents.lookupByName("M") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("M")!));
    }
    if(pf.targetEvents.lookupByName("NS") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("NS")!));
    }
    if(pf.targetEvents.lookupByName("NPM") != null) {
      hitGroups.add(ScoringEventGroup.single(pf.targetEvents.lookupByName("NPM")!, displayIfNoEvents: false));
    }
    ColumnGroup hitsColumn = ColumnGroup(
      headerLabel: "Hits",
      eventGroups: [
        ...hitGroups,
      ],
    );

    // Show a total penalties column, and also show a total
    // bonuses column (including both stage-level bonuses and 
    // bonuses from X-ring hits).

    return SportDisplaySettings(
      scoreColumns: [timeBonusColumn, accuracyPenaltyColumn, otherPenaltyColumn, hitsColumn],
      showPowerFactor: false,
    );
  }
}