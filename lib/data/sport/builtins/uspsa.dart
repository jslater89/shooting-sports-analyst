/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/connectivity/rating_carriers.dart';
import 'package:shooting_sports_analyst/data/ranking/connectivity/sqrt_total_unique_product.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/sorts.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const _uspsaPenalties = [
  const ScoringEvent("Procedural", shortName: "P", pointChange: -10, alternateNames: ["Proc"], sortOrder: 100),
  const ScoringEvent("Overtime shot", shortName: "OS", pointChange: -5, sortOrder: 101),
];

// Too bad, 'not for score' shooters, you're in Open now
const uspsaOpen = Division(name: "Open", shortName: "OPEN", alternateNames: ["NFS"], fallback: true);
const uspsaPcc = Division(name: "PCC", shortName: "PCC", alternateNames: ["Pistol Caliber Carbine", "pistolcalibercarbine"]);
const uspsaLimited = Division(name: "Limited", shortName: "LIM", alternateNames: ["LTD"]);
const uspsaLimitedOptics = Division(name: "Limited Optics", shortName: "LO", alternateNames: ["limitedoptics"]);
const uspsaCarryOptics = Division(name: "Carry Optics", shortName: "CO", alternateNames: ["carryoptics", "Carry-Optic"]);
const uspsaProduction = Division(name: "Production", shortName: "PROD");
const uspsaSingleStack = Division(name: "Single Stack", shortName: "SS", alternateNames: ["singlestack"]);
const uspsaRevolver = Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]);
const uspsaLimited10 = Division(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10", "LTD10", "limited10"]);

const uspsaGM = Classification(
  index: 0,
  name: "Grandmaster",
  shortName: "GM",
  alternateNames: ["G"],
);
const uspsaM = Classification(index: 1, name: "Master", shortName: "M");
const uspsaA = Classification(index: 2, name: "A", shortName: "A");
const uspsaB = Classification(index: 3, name: "B", shortName: "B");

const uspsaC = Classification(index: 4, name: "C", shortName: "C");
const uspsaD = Classification(index: 5, name: "D", shortName: "D");
const uspsaU = Classification(index: 6, name: "Unclassified", shortName: "U", fallback: true);

const uspsaLevel1 = MatchLevel(name: "Level I", shortName: "I", alternateNames: ["Local", "L1"], eventLevel: EventLevel.local);
const uspsaLevel2 = MatchLevel(name: "Level II", shortName: "II", alternateNames: ["Regional/State", "L2"], eventLevel: EventLevel.regional);
const uspsaLevel3 = MatchLevel(name: "Level III", shortName: "III", alternateNames: ["Area", "L3"], eventLevel: EventLevel.area);
const uspsaLevel4 = MatchLevel(name: "Nationals", shortName: "IV", alternateNames: ["National", "L4"], eventLevel: EventLevel.national);

const _matchLevels = [
  uspsaLevel1,
  uspsaLevel2,
  uspsaLevel3,
  uspsaLevel4,
];

final uspsaMinorPF = PowerFactor("Minor",
  shortName: "min",
  targetEvents: [
    const ScoringEvent("A", pointChange: 5, sortOrder: 0),
    const ScoringEvent("C", pointChange: 3, alternateNames: ["B"], sortOrder: 1),
    const ScoringEvent("D", pointChange: 1, sortOrder: 2),
    const ScoringEvent("M", pointChange: -10, sortOrder: 3),
    const ScoringEvent("NS", pointChange: -10, alternateNames: ["NoShoot"], sortOrder: 4),
    const ScoringEvent("NPM", pointChange: 0, displayInOverview: false, sortOrder: 5),
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
  displaySettingsPowerFactor: uspsaMinorPF,
  resultSortModes: hitFactorSorts,
  shooterDeduplicator: USPSADeduplicator(),
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
        const ScoringEvent("A", pointChange: 5, sortOrder: 0),
        const ScoringEvent("C", pointChange: 4, alternateNames: ["B"], sortOrder: 1),
        const ScoringEvent("D", pointChange: 2, sortOrder: 2),
        const ScoringEvent("M", pointChange: -10, sortOrder: 3),
        const ScoringEvent("NS", pointChange: -10, sortOrder: 4),
        const ScoringEvent("NPM", pointChange: 0, displayInOverview: false, sortOrder: 5),
      ],
      penaltyEvents: _uspsaPenalties,
    ),
    uspsaMinorPF,
    PowerFactor("Subminor",
      shortName: "sub",
      doesNotScore: true,
      targetEvents: [
        const ScoringEvent("A", pointChange: 0, sortOrder: 0),
        const ScoringEvent("C", pointChange: 0, alternateNames: ["B"], sortOrder: 1),
        const ScoringEvent("D", pointChange: 0, sortOrder: 2),
        const ScoringEvent("M", pointChange: 0, sortOrder: 3),
        const ScoringEvent("NS", pointChange: 0, sortOrder: 4),
        const ScoringEvent("NPM", pointChange: 0, displayInOverview: false, sortOrder: 5),
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
    // uspsaGM: [OpenskillSettings.defaultMu + 25, OpenskillSettings.defaultSigma],
    // uspsaM: [OpenskillSettings.defaultMu + 20, OpenskillSettings.defaultSigma],
    // uspsaA: [OpenskillSettings.defaultMu + 15, OpenskillSettings.defaultSigma],
    // uspsaB: [OpenskillSettings.defaultMu + 10, OpenskillSettings.defaultSigma],
    // uspsaC: [OpenskillSettings.defaultMu + 5, OpenskillSettings.defaultSigma],
    // uspsaD: [OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma],
    // uspsaU: [OpenskillSettings.defaultMu + 5, OpenskillSettings.defaultSigma],
  },
  ratingStrengthProvider: _UspsaRatingStrengthProvider(),
  pubstompProvider: _UspsaPubstompProvider(),
  builtinRatingGroupsProvider: UspsaRatingGroupsProvider(),
  connectivityCalculator: RatingCarrierConnectivityCalculator(),
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
      _ => 2,
    };
  }

  @override
  double strengthBonusForMatchLevel(MatchLevel? level) {
    if(level == uspsaLevel1) return 1.0;
    else if(level == uspsaLevel2) return 1.15;
    else if(level == uspsaLevel3) return 1.3;
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

class UspsaRatingGroupsProvider implements RatingGroupsProvider {
  static UspsaRatingGroupsProvider instance = UspsaRatingGroupsProvider._();
  factory UspsaRatingGroupsProvider() => instance;

  UspsaRatingGroupsProvider._();

  @override
  List<RatingGroup> get builtinRatingGroups => _builtinRaterGroups;

  @override
  List<RatingGroup> get defaultRatingGroups => divisionRatingGroups;

  @override
  List<RatingGroup> get divisionRatingGroups => _builtinRaterGroups.where((g) => g.divisionNames.length == 1).toList();

  @override
  RatingGroup? getGroup(String uuid) {
    return _builtinRaterGroups.firstWhereOrNull((g) => g.uuid == uuid);
  }
}

final _builtinRaterGroups = <RatingGroup>[
  RatingGroup.newBuiltIn(
    uuid: "uspsa-open",
    sportName: uspsaName,
    name: "Open",
    displayName: "OPEN",
    sortOrder: 0,
    divisionNames: [
      uspsaOpen.name,
    ]
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-limited",
    sportName: uspsaName,
    name: "Limited",
    displayName: "LIM",
    sortOrder: 1,
    divisionNames: [
      uspsaLimited.name,
    ],
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-pcc",
    sportName: uspsaName,
    name: "PCC",
    divisionNames: [
      uspsaPcc.name,
    ],
    sortOrder: 2,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-limited-optics",
    sportName: uspsaName,
    name: "Limited Optics",
    displayName: "LO",
    divisionNames: [
      uspsaLimitedOptics.name,
    ],
    sortOrder: 3,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-carryoptics",
    sportName: uspsaName,
    name: "Carry Optics",
    displayName: "CO",
    divisionNames: [
      uspsaCarryOptics.name,
    ],
    sortOrder: 4,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-production",
    sportName: uspsaName,
    name: "Production",
    displayName: "PROD",
    divisionNames: [
      uspsaProduction.name,
    ],
    sortOrder: 5,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-singlestack",
    sportName: uspsaName,
    name: "Single Stack",
    displayName: "SS",
    divisionNames: [
      uspsaSingleStack.name,
    ],
    sortOrder: 6,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-revolver",
    sportName: uspsaName,
    name: "Revolver",
    displayName: "REVO",
    divisionNames: [
      uspsaRevolver.name,
    ],
    sortOrder: 7,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-limited10",
    sportName: uspsaName,
    name: "Limited 10",
    displayName: "L10",
    divisionNames: [
      uspsaLimited10.name,
    ],
    sortOrder: 8,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-locap",
    sportName: uspsaName,
    name: "Locap",
    divisionNames: [
      uspsaSingleStack.name,
      uspsaLimited10.name,
      uspsaProduction.name,
      uspsaRevolver.name,
    ],
    sortOrder: 9,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-optic-handguns",
    sportName: uspsaName,
    name: "Optic Handguns",
    displayName: "Optics",
    divisionNames: [
      uspsaOpen.name,
      uspsaCarryOptics.name,
      uspsaLimitedOptics.name,
      uspsaLimited10.name,
    ],
    sortOrder: 10,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-irons-handguns",
    sportName: uspsaName,
    name: "Irons Handguns",
    displayName: "Irons",
    divisionNames: [
      uspsaLimited.name,
      uspsaProduction.name,
      uspsaSingleStack.name,
      uspsaRevolver.name,
    ],
    sortOrder: 11,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-open-pcc",
    sportName: uspsaName,
    name: "Open/PCC",
    divisionNames: [
      uspsaOpen.name,
      uspsaPcc.name,
    ],
    sortOrder: 12,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-limited-co",
    sportName: uspsaName,
    name: "Limited/Carry Optics",
    displayName: "LIM/CO",
    divisionNames: [
      uspsaLimited.name,
      uspsaCarryOptics.name,
    ],
    sortOrder: 13,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-lo-co",
    sportName: uspsaName,
    name: "LO/CO",
    divisionNames: [
      uspsaLimitedOptics.name,
      uspsaCarryOptics.name,
    ],
    sortOrder: 14,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-lim-lo-co",
    sportName: uspsaName,
    name: "Limited/LO/CO",
    displayName: "LIM/LO/CO",
    divisionNames: [
      uspsaLimited.name,
      uspsaLimitedOptics.name,
      uspsaCarryOptics.name,
    ],
    sortOrder: 15,
  ),
  RatingGroup.newBuiltIn(
    uuid: "uspsa-limited-lo",
    sportName: uspsaName,
    name: "Limited/LO",
    displayName: "LIM/LO",
    divisionNames: [
      uspsaLimited.name,
      uspsaLimitedOptics.name,
    ],
    sortOrder: 16,
  ),
  RatingGroup.newBuiltIn(
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
    sortOrder: 17,
  ),
];
