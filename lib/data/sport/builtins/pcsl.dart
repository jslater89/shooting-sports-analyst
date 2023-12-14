/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _pcslPenalties = [
  const ScoringEvent("Procedural", shortName: "P", pointChange: -10),
  const ScoringEvent("Overtime shot", shortName: "OS", pointChange: -5),
];

final pcslSport = Sport(
  "PCSL",
  type: SportType.pcsl,
  matchScoring: RelativeStageFinishScoring(),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
  classifications: [
    const Classification(index: 0, name: "Standard Competitor", shortName: "STD", fallback: true),
    const Classification(index: 1, name: "Coachable Shooter", shortName: "CS"),
  ],
  divisions: [
    const Division(name: "2-Gun Practical", shortName: "2GP", alternateNames: ["Practical"]),
    const Division(name: "2-Gun Competition", shortName: "2GC"),
    const Division(name: "Competition", shortName: "COMP", alternateNames: ["Competition (COMP)", "1-Gun Competition"], fallback: true),
    const Division(name: "Practical Optics", shortName: "PO", alternateNames: ["Practical Optics (PO)", "1-Gun Practical Optics"]),
    const Division(name: "Practical Irons", shortName: "PI", alternateNames: ["Practical Irons (PI)", "1-Gun Practical Irons"]),
    const Division(name: "Actual Carry Pistol", shortName: "ACP", alternateNames: ["Actual Carry Pistol (ACP)", "1-Gun Actual Carry Pistol"]),
    const Division(name: "PCC", shortName: "PCC", alternateNames: ["Pistol Caliber Carbine (PCC)", "Pistol Caliber Carbine (PCC)", "1-Gun PCC", "1-Gun Pistol Caliber Carbine"]),
  ],
  powerFactors: [
    PowerFactor("",
      targetEvents: [
        const ScoringEvent("K", pointChange: 10),
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 3),
        const ScoringEvent("D", pointChange: 1),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
        const ScoringEvent("NPM", pointChange: 0),
      ],
      penaltyEvents: _pcslPenalties,
    ),
  ]
);