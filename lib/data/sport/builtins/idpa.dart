/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

final _idpaPenalties = [
  const ScoringEvent("Non-Threat", timeChange: 5, alternateNames: ["Hits on Non-Threat"]),
  const ScoringEvent("PE", timeChange: 3, alternateNames: ["Procedural Error", "Finger PE", "Procedural", "Finger"]),
  const ScoringEvent("Flagrant", timeChange: 10, alternateNames: ["Flagrant Penalty"]),
  const ScoringEvent("FTDR", timeChange: 30, alternateNames: ["Failure to Do Right"]),
];

final idpaSportName = "IDPA";
const idpaDivisions = [
  const Division(name: "SSP", longName: "Stock Service Pistol", shortName: "SSP", alternateNames: ["Stock Service Pistol (SSP)"]),
  const Division(name: "PCC", longName: "Pistol Caliber Carbine", shortName: "PCC", alternateNames: ["PCC10", "Pistol Caliber Carbine (PCC)"]),
  const Division(name: "ESP", longName: "Enhanced Service Pistol", shortName: "ESP", alternateNames: ["Enhanced Service Pistol (ESP)"]),
  const Division(name: "CDP", longName: "Custom Defensive Pistol", shortName: "CDP", alternateNames: ["Custom Defensive Pistol (CDP)"]),
  const Division(name: "CO", longName: "Carry Optics", shortName: "CO", alternateNames: ["Carry Optics (CO)"]),
  const Division(name: "CCP", longName: "Compact Carry Pistol", shortName: "CCP", alternateNames: ["Compact Carry Pistol (CCP)"]),
  const Division(name: "BUG", longName: "Backup Gun", shortName: "BUG", alternateNames: ["Backup Gun (BUG)", "Back-Up Gun (BUG)"]),
  const Division(name: "REV", longName: "Revolver", shortName: "REV", alternateNames: ["REVO", "SSR", "ESR", "Revolver (REV)"]),
  const Division(name: "NFC", longName: "Not For Competition", shortName: "NFC", alternateNames: ["SPD", "Not For Competition (NFC)", "N/A"], fallback: true),
];

final idpaSport = Sport(
    idpaSportName,
    type: SportType.idpa,
    matchScoring: CumulativeScoring(highScoreWins: false),
    defaultStageScoring: const TimePlusScoring(),
    hasStages: true,
    resultSortModes: [
      SortMode.time,
      SortMode.rawTime,
      SortMode.idpaAccuracy,
      SortMode.lastName,
      SortMode.classification,
    ],
    classifications: [
      const Classification(index: 0, name: "Distinguished Master", shortName: "DM"),
      const Classification(index: 1, name: "Master", shortName: "MA"),
      const Classification(index: 2, name: "Expert", shortName: "EX"),
      const Classification(index: 3, name: "Sharpshooter", shortName: "SS"),
      const Classification(index: 4, name: "Marksman", shortName: "MM"),
      const Classification(index: 5, name: "Novice", shortName: "NV"),
      const Classification(index: 6, name: "Unclassified", shortName: "UN", fallback: true),
    ],
    divisions: idpaDivisions,
    powerFactors: [
      PowerFactor("",
        targetEvents: [
          const ScoringEvent("-0", timeChange: 0),
          const ScoringEvent("-1", timeChange: 1, alternateNames: ["PD"]),
          const ScoringEvent("-3", timeChange: 3),
          const ScoringEvent("Miss", timeChange: 5, alternateNames: ["Failure to Neutralize"]),
        ],
        penaltyEvents: _idpaPenalties,
      ),
    ],
    builtinRatingGroupsProvider: DivisionRatingGroupProvider(idpaSportName, idpaDivisions),
);
