/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/sorts.dart';
import 'package:shooting_sports_analyst/data/sport/display_settings.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/stage_scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const _pcslProcedural = ScoringEvent("Procedural", shortName: "P", pointChange: -10);
const _pcslOvertimeShot = ScoringEvent("Overtime Shot", shortName: "OS", pointChange: -5);

final _pcslPenalties = [
  _pcslProcedural,
  _pcslOvertimeShot,
];

const _pcslK = ScoringEvent("K", pointChange: 10);
const _pcslA = ScoringEvent("A", pointChange: 5);
const _pcslC = ScoringEvent("C", pointChange: 3);
const _pcslD = ScoringEvent("D", pointChange: 1);
const _pcslM = ScoringEvent("M", pointChange: -10);
const _pcslNS = ScoringEvent("NS", pointChange: -10);
const _pcslPseudoK = ScoringEvent("NPM", pointChange: 0);

const pcslSportName = "PCSL";
const pcslDivisions = [
  const Division(
    name: "Open",
    longName: "Open",
    shortName: "OPEN",
  ),
  const Division(
    name: "Practical",
    longName: "2-Gun Practical",
    shortName: "2GP",
    alternateNames: ["Practical (2-Gun)"],
  ),
  const Division(
    name: "2-Gun Comp.",
    longName: "2-Gun Competition",
    shortName: "2GC",
    alternateNames: ["Competition (2-Gun)"],
  ),
  const Division(
    name: "Competition",
    shortName: "COMP",
    alternateNames: ["Competition (COMP)", "1-Gun Competition"],
    fallback: true,
  ),
  const Division(
    name: "Practical Optics",
    shortName: "PO",
    alternateNames: [
      "Practical Optics (PO)",
      "1-Gun Practical Optics",
      "Practical Optics (Pistol)",
    ],
  ),
  const Division(
    name: "Practical Irons",
    shortName: "PI",
    alternateNames: [
      "Practical Irons (PI)",
      "1-Gun Practical Irons",
      "Practical Irons (Pistol)",
    ],
  ),
  const Division(
    name: "Actual Carry Pistol",
    shortName: "ACP",
    alternateNames: [
      "Actual Carry Pistol (ACP)",
      "1-Gun Actual Carry Pistol",
      "1-Gun ACP (Actual Carry Pistol)",
    ],
  ),
  const Division(
    name: "PCC",
    shortName: "PCC",
    alternateNames: [
      "Pistol Caliber Carbine (PCC)",
      "1-Gun PCC",
      "1-Gun Pistol Caliber Carbine",
    ],
  ),
];

final _pcslDisplaySettings = SportDisplaySettings(
  showClassification: false,
  scoreColumns: [
    ColumnGroup(
      headerLabel: "Hits",
      eventGroups: [
        ScoringEventGroup.single(_pcslK, displayIfNoEvents: false),
        ScoringEventGroup.single(_pcslA),
        ScoringEventGroup.single(_pcslC),
        ScoringEventGroup.single(_pcslD),
        ScoringEventGroup.single(_pcslM),
        ScoringEventGroup.single(_pcslNS),
        ScoringEventGroup.single(_pcslProcedural, label: _pcslProcedural.shortDisplayName),
      ]
    ),
    ColumnGroup(
      headerLabel: "K Hits",
      headerTooltip: "Probable K hits (recorded as NPM in PractiScore)",
      eventGroups: [
        ScoringEventGroup.single(_pcslPseudoK, label: "K"),
      ]
    )
  ]
);

final pcslSport = Sport(
  pcslSportName,
  type: SportType.pcsl,
  matchScoring: RelativeStageFinishScoring(),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
  displaySettings: _pcslDisplaySettings,
  resultSortModes: hitFactorSorts,
  classifications: [
    const Classification(index: 0, name: "Standard Competitor", shortName: "STD", fallback: true),
    const Classification(index: 1, name: "Coachable Shooter", shortName: "CS"),
  ],
  divisions: pcslDivisions,
  powerFactors: [
    PowerFactor("",
      targetEvents: [
        _pcslK,
        _pcslA,
        _pcslC,
        _pcslD,
        _pcslM,
        _pcslNS,
        _pcslPseudoK,
      ],
      penaltyEvents: _pcslPenalties,
    ),
  ],
  builtinRatingGroupsProvider: DivisionRatingGroupProvider(pcslSportName, pcslDivisions)
);
