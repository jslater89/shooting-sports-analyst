/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_settings.dart';
import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/sorts.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const _uspsaPenalties = [
  const ScoringEvent("Procedural", shortName: "P", pointChange: -10),
  const ScoringEvent("Overtime shot", shortName: "OS", pointChange: -5),
];

const uspsaOpen = Division(name: "Open", shortName: "OPEN", fallback: true);
const uspsaPcc = Division(name: "PCC", shortName: "PCC");
const uspsaLimited = Division(name: "Limited", shortName: "LIM", alternateNames: ["LTD"]);
const uspsaLimitedOptics = Division(name: "Limited Optics", shortName: "LO", alternateNames: ["limitedoptics"]);
const uspsaCarryOptics = Division(name: "Carry Optics", shortName: "CO", alternateNames: ["carryoptics"]);
const uspsaProduction = Division(name: "Production", shortName: "PROD");
const uspsaSingleStack = Division(name: "Single Stack", shortName: "SS", alternateNames: ["singlestack"]);
const uspsaRevolver = Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]);
const uspsaLimited10 = Division(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10", "LTD10", "limited10"]);

const uspsaGM = Classification(index: 0, name: "Grandmaster", shortName: "GM", alternateNames: ["G"]);
const uspsaM = Classification(index: 1, name: "Master", shortName: "M");
const uspsaA = Classification(index: 2, name: "A", shortName: "A");
const uspsaB = Classification(index: 3, name: "B", shortName: "B");
const uspsaC = Classification(index: 4, name: "C", shortName: "C");
const uspsaD = Classification(index: 5, name: "D", shortName: "D");
const uspsaU = Classification(index: 6, name: "Unclassified", shortName: "U", fallback: true);

const _level1 = MatchLevel(name: "Level I", shortName: "I", alternateNames: ["Local", "L1"], eventLevel: EventLevel.local);
const _level2 = MatchLevel(name: "Level II", shortName: "II", alternateNames: ["Regional/State", "L2"], eventLevel: EventLevel.regional);
const _level3 = MatchLevel(name: "Level III", shortName: "III", alternateNames: ["Area", "L3"], eventLevel: EventLevel.area);
const _level4 = MatchLevel(name: "Nationals", shortName: "IV", alternateNames: ["National", "L4"], eventLevel: EventLevel.national);

const _matchLevels = [
  _level1,
  _level2,
  _level3,
  _level4,
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

final String uspsaName = "USPSA";

final uspsaSport = Sport(
  uspsaName,
  type: SportType.uspsa,
  matchScoring: RelativeStageFinishScoring(pointsAreUSPSAFixedTime: true),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
  displaySettingsPowerFactor: _minorPowerFactor,
  resultSortModes: hitFactorSorts,
  shooterDeduplicator: const USPSADeduplicator(),
  eventLevels: _matchLevels,
  fantasyScoresProvider: const USPSAFantasyScoringCalculator(),
  classifications: [
    uspsaGM,
    uspsaM,
    uspsaA,
    uspsaB,
    uspsaC,
    uspsaD,
    uspsaU,
  ],
  divisions: [
    uspsaOpen,
    uspsaPcc,
    uspsaLimited,
    uspsaLimitedOptics,
    uspsaCarryOptics,
    uspsaProduction,
    uspsaSingleStack,
    uspsaRevolver,
    uspsaLimited10,
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
      doesNotScore: true,
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
  initialEloRatings: {
    uspsaGM: 1300,
    uspsaM: 1200,
    uspsaA: 1100,
    uspsaB: 1000,
    uspsaC: 900,
    uspsaD: 800,
    uspsaU: 900,
  },
  initialOpenskillRatings: {
    uspsaGM: [OpenskillSettings.defaultMu + 25, OpenskillSettings.defaultSigma],
    uspsaM: [OpenskillSettings.defaultMu + 20, OpenskillSettings.defaultSigma],
    uspsaA: [OpenskillSettings.defaultMu + 15, OpenskillSettings.defaultSigma],
    uspsaB: [OpenskillSettings.defaultMu + 10, OpenskillSettings.defaultSigma],
    uspsaC: [OpenskillSettings.defaultMu + 5, OpenskillSettings.defaultSigma],
    uspsaD: [OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma],
    uspsaU: [OpenskillSettings.defaultMu + 5, OpenskillSettings.defaultSigma],
  },
  ratingStrengthProvider: _UspsaRatingStrengthProvider(),
  pubstompProvider: _UspsaPubstompProvider(),
  builtinRatingGroupsProvider: _UspsaRatingGroupsProvider(),
);

class _UspsaRatingStrengthProvider implements RatingStrengthProvider {
  @override
  double get centerStrength => 4;

  @override
  double strengthForClass(Classification? c) {
    return switch(c) {
      uspsaGM => 10,
      uspsaM => 6,
      uspsaA => 4,
      uspsaB => 3,
      uspsaC => 2,
      uspsaD => 1,
      uspsaU => 2,
      _ => 2.5,
    };
  }

  @override
  double strengthBonusForMatchLevel(MatchLevel? level) {
    if(level == _level1) return 1.0;
    else if(level == _level2) return 1.15;
    else if(level == _level3) return 1.3;
    else return 1.0;
  }
}

class _UspsaPubstompProvider implements PubstompProvider {
  @override
  bool isPubstomp({
    required RelativeMatchScore firstScore,
    required RelativeMatchScore secondScore,
    Classification? firstClass,
    Classification? secondClass,
    required ShooterRating firstRating,
    required ShooterRating secondRating
  }) {
    if(firstClass == null) return false;
    if(secondClass == null) secondClass = uspsaU;

    // It's only a pubstomp if:
    // 1. The winner wins by more than 25%.
    // 2. The winner is M shooting against no better than B or GM shooting against no better than A.
    // 3. The winner's rating is at least 200 higher than the next shooter's.
    // TODO: it's probably possible to make this generic/rule-based.

    if(firstScore.ratio >= 1.0
        && (firstScore.points / secondScore.points > 1.20)
        && firstClass.index <= uspsaM.index
        && secondClass.index - firstClass.index >= 2
        && firstRating.rating - secondRating.rating > 200) {
      // _log.d("Pubstomp multiplier for $firstRating over $secondRating");
      return true;

    }
    return false;
  }
}

class _UspsaRatingGroupsProvider implements RatingGroupsProvider {
  @override
  List<RatingGroup> get builtinRatingGroups => _builtinRaterGroups;

  @override
  List<RatingGroup> get defaultRatingGroups => divisionRatingGroups;

  @override
  List<RatingGroup> get divisionRatingGroups => _builtinRaterGroups.where((g) => g.divisionNames.length == 1).toList();
}

final _builtinRaterGroups = <RatingGroup>[
  RatingGroup.create(
    uuid: "uspsa-open",
    sportName: uspsaName,
    name: "Open",
    displayName: "OPEN",
    divisionNames: [
      uspsaOpen.name,
    ]
  ),
  RatingGroup.create(
    uuid: "uspsa-limited",
    sportName: uspsaName,
    name: "Limited",
    displayName: "LIM",
    divisionNames: [
      uspsaLimited.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-pcc",
    sportName: uspsaName,
    name: "PCC",
    divisionNames: [
      uspsaPcc.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-carryoptics",
    sportName: uspsaName,
    name: "Carry Optics",
    displayName: "CO",
    divisionNames: [
      uspsaCarryOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-locap",
    sportName: uspsaName,
    name: "Locap",
    divisionNames: [
      uspsaSingleStack.name,
      uspsaLimited10.name,
      uspsaProduction.name,
      uspsaRevolver.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-singlestack",
    sportName: uspsaName,
    name: "Single Stack",
    displayName: "SS",
    divisionNames: [
      uspsaSingleStack.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-production",
    sportName: uspsaName,
    name: "Production",
    displayName: "PROD",
    divisionNames: [
      uspsaProduction.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-limited10",
    sportName: uspsaName,
    name: "Limited 10",
    displayName: "L10",
    divisionNames: [
      uspsaLimited10.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-revolver",
    sportName: uspsaName,
    name: "Revolver",
    displayName: "REVO",
    divisionNames: [
      uspsaRevolver.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-open-pcc",
    sportName: uspsaName,
    name: "OPEN/PCC",
    divisionNames: [
      uspsaOpen.name,
      uspsaPcc.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-limited-co",
    sportName: uspsaName,
    name: "Limited/Carry Optics",
    displayName: "LIM/CO",
    divisionNames: [
      uspsaLimited.name,
      uspsaCarryOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-limited-optics",
    sportName: uspsaName,
    name: "Limited Optics",
    displayName: "LO",
    divisionNames: [
      uspsaLimitedOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-lo-co",
    sportName: uspsaName,
    name: "LO/CO",
    divisionNames: [
      uspsaLimitedOptics.name,
      uspsaCarryOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-lim-lo-co",
    sportName: uspsaName,
    name: "Limited/LO/CO",
    displayName: "LIM/LO/CO",
    divisionNames: [
      uspsaLimited.name,
      uspsaLimitedOptics.name,
      uspsaCarryOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-limited-lo",
    sportName: uspsaName,
    name: "Limited/LO",
    displayName: "LIM/LO",
    divisionNames: [
      uspsaLimited.name,
      uspsaLimitedOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-optic-handguns",
    sportName: uspsaName,
    name: "Optic Handguns",
    displayName: "Optics",
    divisionNames: [
      uspsaOpen.name,
      uspsaCarryOptics.name,
      uspsaLimitedOptics.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-irons-handguns",
    sportName: uspsaName,
    name: "Irons Handguns",
    displayName: "Irons",
    divisionNames: [
      uspsaLimited.name,
      uspsaProduction.name,
      uspsaSingleStack.name,
      uspsaRevolver.name,
      uspsaLimited10.name,
    ],
  ),
  RatingGroup.create(
    uuid: "uspsa-combined",
    sportName: uspsaName,
    name: "Combined",
    divisionNames: [
      uspsaOpen.name,
      uspsaLimited.name,
      uspsaPcc.name,
      uspsaCarryOptics.name,
      uspsaLimitedOptics.name,
      uspsaProduction.name,
      uspsaSingleStack.name,
      uspsaRevolver.name,
      uspsaLimited10.name,
    ],
  ),
];
