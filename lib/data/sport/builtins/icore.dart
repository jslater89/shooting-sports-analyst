/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/connectivity/sqrt_total_unique_product.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore_utils/icore_display_settings.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const _icoreProceduralName = "Procedural";
const _icorePrematureStartName = "Premature Start";
const _icoreFootFaultName = "Foot Fault";
const _icoreFailureToEngageName = "Failure to Engage";
const _icoreExtraShotName = "Extra Shot";
const _icoreExtraHitName = "Extra Hit";
const _icoreOvertimeShotName = "Overtime Shot";
const _icoreStopPlateFailureName = "Missed Stop Plate";
const _icoreChronoFailureName = "Failing to Make Chrono";

const icoreProcedural = ScoringEvent(_icoreProceduralName, shortName: "P", timeChange: 5, sortOrder: 100);
const icorePrematureStart = ScoringEvent(_icorePrematureStartName, shortName: "PS", timeChange: 5, sortOrder: 101);
const icoreFootFault = ScoringEvent(_icoreFootFaultName, shortName: "FF", timeChange: 5, sortOrder: 102);
const icoreFailureToEngage = ScoringEvent(_icoreFailureToEngageName, shortName: "FTE", timeChange: 5, sortOrder: 103);
const icoreExtraShot = ScoringEvent(_icoreExtraShotName, shortName: "ES", timeChange: 5, sortOrder: 104);
const icoreExtraHit = ScoringEvent(_icoreExtraHitName, shortName: "EH", timeChange: 5, sortOrder: 105);
const icoreOvertimeShot = ScoringEvent(_icoreOvertimeShotName, shortName: "OT", timeChange: 10, sortOrder: 106);
const icoreStopPlateFailure = ScoringEvent(_icoreStopPlateFailureName, shortName: "SP", timeChange: 30, sortOrder: 107);
const icoreChronoFailure = ScoringEvent(_icoreChronoFailureName, shortName: "FMC", timeChange: 360, sortOrder: 108);

const icorePenalties = [
  icoreProcedural,
  icorePrematureStart,
  icoreFootFault,
  icoreFailureToEngage,
  icoreExtraShot,
  icoreExtraHit,
  icoreOvertimeShot,
  icoreStopPlateFailure,
  icoreChronoFailure,
];

const _icoreXName = "X";
const _icoreAName = "A";
const _icoreBName = "B";
const _icoreBig6BName = "B";
const _icoreCName = "C";
const _icoreMName = "M";
const _icoreNSName = "NS";
const _icoreNPMName = "NPM";
const _icoreBig6Name = "Big 6";

const icoreBig6PowerFactor = PowerFactor.constant(_icoreBig6Name,
  targetEvents: {
    _icoreXName: icoreX,
    _icoreAName: icoreA,
    _icoreBig6BName: icoreBig6B,
    _icoreCName: icoreC,
    _icoreMName: icoreM,
    _icoreNSName: icoreNS,
    _icoreNPMName: icoreNPM,
  },
  penaltyEvents: {
    _icoreProceduralName: icoreProcedural,
    _icorePrematureStartName: icorePrematureStart,
    _icoreFootFaultName: icoreFootFault,
    _icoreFailureToEngageName: icoreFailureToEngage,
    _icoreExtraShotName: icoreExtraShot,
    _icoreExtraHitName: icoreExtraHit,
    _icoreOvertimeShotName: icoreOvertimeShot,
    _icoreStopPlateFailureName: icoreStopPlateFailure,
    _icoreChronoFailureName: icoreChronoFailure,
  }
);

const icoreDivisions = [
  const Division(name: "Open", shortName: "OPEN", alternateNames: ["O"]),
  const Division(name: "Limited", shortName: "LIM", alternateNames: ["L"]),
  const Division(name: "Limited 6", shortName: "LIM6", alternateNames: ["L6"]),
  const Division(name: "Classic", shortName: "CLS", alternateNames: ["CLC", "C"]),
  const Division(
    name: "Big 6",
    shortName: "BIG6",
    alternateNames: ["B6", "Heavy Metal", "HM"],
    powerFactorOverride: icoreBig6PowerFactor,
  )
];

/// An X-ring bonus hit. Defaults to -1 second, but may be overridden
/// on certain stages/scores.
const icoreX = ScoringEvent(_icoreXName, timeChange: -1, sortOrder: 1, variableValue: true);
const icoreA = ScoringEvent(_icoreAName, timeChange: 0, sortOrder: 2);
const icoreB = ScoringEvent(_icoreBName, timeChange: 1, sortOrder: 3);
const icoreBig6B = ScoringEvent(_icoreBig6BName, timeChange: 0, sortOrder: 3);
const icoreC = ScoringEvent(_icoreCName, timeChange: 2, sortOrder: 4);
const icoreM = ScoringEvent(_icoreMName, timeChange: 5, sortOrder: 5);
const icoreNS = ScoringEvent(_icoreNSName, timeChange: 5, sortOrder: 6);
const icoreNPM = ScoringEvent(_icoreNPMName, timeChange: 0, sortOrder: 7);

const icoreGrandmaster = Classification(index: 0, name: "Grandmaster", shortName: "GM");
const icoreMaster = Classification(index: 1, name: "Master", shortName: "M");
const icoreAClass = Classification(index: 2, name: "A", shortName: "A");
const icoreBClass = Classification(index: 3, name: "B", shortName: "B");
const icoreCClass = Classification(index: 4, name: "C", shortName: "C");
const icoreDClass = Classification(index: 5, name: "D", shortName: "D");
const icoreUnclassified = Classification(index: 6, name: "Unclassified", shortName: "U", fallback: true);

// TODO: this may be better in penalty events, since it's only kind of a target event
/// A bonus hit on steel. Defaults to -3 seconds, but may be overridden
/// on certain stages/scores.

/// TODO: there is no standard for this, so we need to handle dynamic creation of bonuses per match.
// const icoreBonusSteel = ScoringEvent(_icoreBonusSteelName, shortName: "SB", alternateNames: ["BS", "Steel Bonus", "Bonus Plate"], timeChange: -3, sortOrder: 7);
const icoreSportName = "ICORE";

final icoreSport = Sport(
    icoreSportName,
    type: SportType.icore,
    displaySettingsBuilder: (sport) => IcoreDisplaySettings.create(sport),
    matchScoring: CumulativeScoring(highScoreWins: false),
    defaultStageScoring: const TimePlusScoring(rawZeroWithEventsIsNonDnf: true),
    hasStages: true,
    resultSortModes: [
      SortMode.time,
      SortMode.rawTime,
      SortMode.alphas,
      SortMode.lastName,
      SortMode.classification,
    ],
    classifications: [
      icoreGrandmaster,
      icoreMaster,
      icoreAClass,
      icoreBClass,
      icoreCClass,
      icoreDClass,
      icoreUnclassified,
    ],
    divisions: icoreDivisions,
    powerFactors: [
      PowerFactor("Standard",
        targetEvents: [
          icoreX,
          icoreA,
          icoreB,
          icoreC,
          icoreM,
          icoreNS,
          icoreNPM,
        ],
        fallback: true,
        penaltyEvents: icorePenalties,
      ),
      icoreBig6PowerFactor,
    ],
    ageCategories: [
      const AgeCategory(name: "Junior"),
      const AgeCategory(name: "Senior"),
      const AgeCategory(name: "Super Senior"),
      const AgeCategory(name: "Grand Senior"),
    ],
    connectivityCalculator: SqrtTotalUniqueProductCalculator(),
    initialEloRatings: {
      icoreGrandmaster: 1400.0,
      icoreMaster: 1200.0,
      icoreAClass: 1000.0,
      icoreBClass: 900.0,
      icoreCClass: 800.0,
      icoreDClass: 700.0,
      icoreUnclassified: 850.0,
    },
    builtinRatingGroupsProvider: DivisionRatingGroupProvider(icoreSportName, icoreDivisions)
);