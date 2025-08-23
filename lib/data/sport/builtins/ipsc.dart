/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/sorts.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/stage_scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const ipscSportName = "IPSC";
const ipscOpen = Division(name: "Open", shortName: "OPEN", fallback: true);
const ipscPccOptics = Division(name: "PCC Optic", shortName: "PCCO", alternateNames: ["PCC", "PCC Optics"]);
const ipscPccIrons = Division(name: "PCC Iron", shortName: "PCCI", alternateNames: ["PCC Irons"]);
const ipscStandard = Division(name: "Standard", shortName: "STD", alternateNames: ["STA"], fallback: true);
const ipscProductionOptics = Division(name: "Production Optics", longName: "Production Optics", shortName: "PO");
const ipscProduction = Division(name: "Production", shortName: "PROD", fallback: true);
const ipscClassic = Division(name: "Classic", shortName: "CLS", alternateNames: ["CLS"]);
const ipscRevolver = Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]);
const ipscDivisions = [
  ipscOpen,
  ipscPccOptics,
  ipscPccIrons,
  ipscStandard,
  ipscProductionOptics,
  ipscProduction,
  ipscClassic,
  ipscRevolver,
];

final _ipscPenalties = [
  const ScoringEvent("Procedural", shortName: "P", pointChange: -10),
  const ScoringEvent("Overtime shot", shortName: "P", pointChange: -5),
];

final _minorPowerFactor = PowerFactor("Minor",
  shortName: "min",
  targetEvents: [
    const ScoringEvent("A", pointChange: 5),
    const ScoringEvent("C", pointChange: 3),
    const ScoringEvent("D", pointChange: 1),
    const ScoringEvent("M", pointChange: -10),
    const ScoringEvent("NS", pointChange: -10),
    const ScoringEvent("NPM", pointChange: 0, displayInOverview: false),
  ],
  penaltyEvents: _ipscPenalties,
);

final ipscSport = Sport(
  ipscSportName,
  type: SportType.ipsc,
  matchScoring: RelativeStageFinishScoring(pointsAreUSPSAFixedTime: true),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
  displaySettingsPowerFactor: _minorPowerFactor,
  resultSortModes: hitFactorSorts,
  fantasyScoresProvider: const USPSAFantasyScoringCalculator(),
  eventLevels: [
    const MatchLevel(name: "Level I", shortName: "I", alternateNames: ["Local"], eventLevel: EventLevel.local),
    const MatchLevel(name: "Level II", shortName: "II", alternateNames: ["Regional"], eventLevel: EventLevel.regional),
    const MatchLevel(name: "Level III", shortName: "III", alternateNames: ["Regional/National"], eventLevel: EventLevel.area),
    const MatchLevel(name: "Level IV", shortName: "IV", alternateNames: ["National/Continental"], eventLevel: EventLevel.national),
    const MatchLevel(name: "Level V", shortName: "V", alternateNames: ["World Shoot"], eventLevel: EventLevel.international),
  ],
  classifications: [
    const Classification(index: 0, name: "Grandmaster", shortName: "GM", alternateNames: ["G"]),
    const Classification(index: 1, name: "Master", shortName: "M"),
    const Classification(index: 2, name: "A", shortName: "A"),
    const Classification(index: 3, name: "B", shortName: "B"),
    const Classification(index: 4, name: "C", shortName: "C"),
    const Classification(index: 5, name: "D", shortName: "D"),
    const Classification(index: 6, name: "Expired", shortName: "X"),
    const Classification(index: 7, name: "Unclassified", shortName: "U", alternateNames: [""], fallback: true),
  ],
  divisions: ipscDivisions,
  ageCategories: [
    const AgeCategory(name: "Junior"),
    const AgeCategory(name: "Senior"),
    const AgeCategory(name: "Super Senior"),
  ],
  powerFactors: [
    PowerFactor("Major",
      shortName: "Maj",
      targetEvents: [
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 4),
        const ScoringEvent("D", pointChange: 2),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
        const ScoringEvent("NPM", pointChange: 0, displayInOverview: false),
      ],
      penaltyEvents: _ipscPenalties,
    ),
    _minorPowerFactor,
    PowerFactor("Subminor",
      shortName: "sub",
      targetEvents: [
        const ScoringEvent("A", pointChange: 0),
        const ScoringEvent("C", pointChange: 0),
        const ScoringEvent("D", pointChange: 0),
        const ScoringEvent("M", pointChange: 0),
        const ScoringEvent("NS", pointChange: 0),
        const ScoringEvent("NPM", pointChange: 0, displayInOverview: false),
      ],
      fallback: true,
      penaltyEvents: _ipscPenalties,
    ),
  ],
  builtinRatingGroupsProvider: DivisionRatingGroupProvider(ipscSportName, ipscDivisions)
);
