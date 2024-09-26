/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/sorts.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const _uspsaPenalties = [
  const ScoringEvent("Procedural", shortName: "P", pointChange: -10),
  const ScoringEvent("Overtime shot", shortName: "OS", pointChange: -5),
];

final _minorPowerFactor = PowerFactor("Minor",
  shortName: "min",
  targetEvents: [
    const ScoringEvent("A", pointChange: 5),
    const ScoringEvent("C", pointChange: 3, alternateNames: ["B"]),
    const ScoringEvent("D", pointChange: 1),
    const ScoringEvent("M", pointChange: -10),
    const ScoringEvent("NS", pointChange: -10),
    const ScoringEvent("NPM", pointChange: 0, displayInOverview: false),
  ],
  penaltyEvents: _uspsaPenalties,
);

final uspsaSport = Sport(
  "USPSA",
  type: SportType.uspsa,
  matchScoring: RelativeStageFinishScoring(pointsAreUSPSAFixedTime: true),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
  displaySettingsPowerFactor: _minorPowerFactor,
  resultSortModes: hitFactorSorts,
  fantasyScoresProvider: const USPSAFantasyScoringCalculator(),
  eventLevels: [
    const MatchLevel(name: "Level I", shortName: "I", alternateNames: ["Local", "L1"], eventLevel: EventLevel.local),
    const MatchLevel(name: "Level II", shortName: "II", alternateNames: ["Regional/State", "L2"], eventLevel: EventLevel.regional),
    const MatchLevel(name: "Level III", shortName: "III", alternateNames: ["Area", "L3"], eventLevel: EventLevel.area),
    const MatchLevel(name: "Nationals", shortName: "IV", alternateNames: ["National", "L4"], eventLevel: EventLevel.national),
  ],
  classifications: [
    const Classification(index: 0, name: "Grandmaster", shortName: "GM", alternateNames: ["G"]),
    const Classification(index: 1, name: "Master", shortName: "M"),
    const Classification(index: 2, name: "A", shortName: "A"),
    const Classification(index: 3, name: "B", shortName: "B"),
    const Classification(index: 4, name: "C", shortName: "C"),
    const Classification(index: 5, name: "D", shortName: "D"),
    const Classification(index: 6, name: "Unclassified", shortName: "U", fallback: true),
  ],
  divisions: [
    const Division(name: "Open", shortName: "OPEN", fallback: true),
    const Division(name: "PCC", shortName: "PCC"),
    const Division(name: "Limited", shortName: "LIM", alternateNames: ["LTD"]),
    const Division(name: "Limited Optics", shortName: "LO", alternateNames: ["limitedoptics"]),
    const Division(name: "Carry Optics", shortName: "CO", alternateNames: ["carryoptics"]),
    const Division(name: "Production", shortName: "PROD"),
    const Division(name: "Single Stack", shortName: "SS", alternateNames: ["singlestack"]),
    const Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    const Division(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10", "LTD10", "limited10"]),
  ],
  ageCategories: [
    const AgeCategory(name: "Junior"),
    const AgeCategory(name: "Senior"),
    const AgeCategory(name: "Super Senior"),
    const AgeCategory(name: "Distinguished Senior")
  ],
  powerFactors: [
    PowerFactor("Major",
      shortName: "Maj",
      targetEvents: [
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 4, alternateNames: ["B"]),
        const ScoringEvent("D", pointChange: 2),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
        const ScoringEvent("NPM", pointChange: 0, displayInOverview: false),
      ],
      penaltyEvents: _uspsaPenalties,
    ),
    _minorPowerFactor,
    PowerFactor("Subminor",
      shortName: "sub",
      targetEvents: [
        const ScoringEvent("A", pointChange: 0),
        const ScoringEvent("C", pointChange: 0, alternateNames: ["B"]),
        const ScoringEvent("D", pointChange: 0),
        const ScoringEvent("M", pointChange: 0),
        const ScoringEvent("NS", pointChange: 0),
        const ScoringEvent("NPM", pointChange: 0, displayInOverview: false),
      ],
      fallback: true,
      penaltyEvents: _uspsaPenalties,
    ),
  ],
);