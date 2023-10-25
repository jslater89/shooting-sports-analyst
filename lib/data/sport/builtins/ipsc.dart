/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _ipscPenalties = [
  const ScoringEvent("Procedural", pointChange: -10),
  const ScoringEvent("Overtime shot", pointChange: -5),
];

final ipscSport = Sport(
  "IPSC",
  type: SportType.ipsc,
  matchScoring: RelativeStageFinishScoring(pointsAreUSPSAFixedTime: true),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
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
    const Classification(index: 6, name: "Unclassified", shortName: "U"),
  ],
  divisions: [
    const Division(name: "Open", shortName: "OPEN"),
    const Division(name: "Pistol Caliber Carbine", shortName: "PCC"),
    const Division(name: "Standard", shortName: "STD", alternateNames: ["STA"]),
    const Division(name: "Production Optics", shortName: "PO"),
    const Division(name: "Production", shortName: "PROD"),
    const Division(name: "Classic", shortName: "CLS", alternateNames: ["CLS"]),
    const Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
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
        const ScoringEvent("NPM", pointChange: 0),
      ],
      penaltyEvents: _ipscPenalties,
    ),
    PowerFactor("Minor",
      shortName: "min",
      targetEvents: [
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 3),
        const ScoringEvent("D", pointChange: 1),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
        const ScoringEvent("NPM", pointChange: 0),
      ],
      penaltyEvents: _ipscPenalties,
    ),
    PowerFactor("Subminor",
      shortName: "sub",
      targetEvents: [
        const ScoringEvent("A", pointChange: 0),
        const ScoringEvent("C", pointChange: 0),
        const ScoringEvent("D", pointChange: 0),
        const ScoringEvent("M", pointChange: 0),
        const ScoringEvent("NS", pointChange: 0),
        const ScoringEvent("NPM", pointChange: 0),
      ],
      penaltyEvents: _ipscPenalties,
    ),
  ]
);