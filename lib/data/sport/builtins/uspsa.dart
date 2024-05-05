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
import 'package:shooting_sports_analyst/data/sport/builtins/sorts.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

const _uspsaPenalties = [
  const ScoringEvent("Procedural", shortName: "P", pointChange: -10),
  const ScoringEvent("Overtime shot", shortName: "OS", pointChange: -5),
];

const uspsaOpen = Division(name: "Open", shortName: "OPEN", fallback: true);
const uspsaPcc = Division(name: "PCC", shortName: "PCC");
const uspsaLimited = Division(name: "Limited", shortName: "LIM", alternateNames: ["LTD"]);
const uspsaLimitedOptics = Division(name: "Limited Optics", shortName: "LO");
const uspsaCarryOptics = Division(name: "Carry Optics", shortName: "CO");
const uspsaProduction = Division(name: "Production", shortName: "PROD");
const uspsaSingleStack = Division(name: "Single Stack", shortName: "SS");
const uspsaRevolver = Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]);
const uspsaLimited10 = Division(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10", "LTD10"]);

const uspsaGM = Classification(index: 0, name: "Grandmaster", shortName: "GM", alternateNames: ["G"]);
const uspsaM = Classification(index: 1, name: "Master", shortName: "M");
const uspsaA = Classification(index: 2, name: "A", shortName: "A");
const uspsaB = Classification(index: 3, name: "B", shortName: "B");
const uspsaC = Classification(index: 4, name: "C", shortName: "C");
const uspsaD = Classification(index: 5, name: "D", shortName: "D");
const uspsaU = Classification(index: 6, name: "Unclassified", shortName: "U", fallback: true);

const _level1 = MatchLevel(name: "Level I", shortName: "I", alternateNames: ["Local"], eventLevel: EventLevel.local);
const _level2 = MatchLevel(name: "Level II", shortName: "II", alternateNames: ["Regional/State"], eventLevel: EventLevel.regional);
const _level3 = MatchLevel(name: "Level III", shortName: "III", alternateNames: ["Area/National"], eventLevel: EventLevel.national);

const _matchLevels = [
  _level1,
  _level2,
  _level3,
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

final String _uspsaName = "USPSA";

final uspsaSport = Sport(
  _uspsaName,
  type: SportType.uspsa,
  matchScoring: RelativeStageFinishScoring(pointsAreUSPSAFixedTime: true),
  defaultStageScoring: const HitFactorScoring(),
  hasStages: true,
  displaySettingsPowerFactor: _minorPowerFactor,
  resultSortModes: hitFactorSorts,
  shooterDeduplicator: const USPSADeduplicator(),
  eventLevels: _matchLevels,
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
  List<DbRatingGroup> get builtinRatingGroups => _builtinRaterGroups;

  @override
  List<DbRatingGroup> get defaultRatingGroups => divisionRatingGroups;

  @override
  List<DbRatingGroup> get divisionRatingGroups => _builtinRaterGroups.where((g) => g.divisionNames.length == 1).toList();
}

final _builtinRaterGroups = <DbRatingGroup>[
  DbRatingGroup.create(
    uuid: "uspsa-open",
    sportName: _uspsaName,
    name: "Open",
    divisionNames: [
      uspsaOpen.name,
    ]
  ),
  DbRatingGroup.create(
    uuid: "uspsa-limited",
    sportName: _uspsaName,
    name: "Limited",
    displayName: "LIM",
    divisionNames: [
      uspsaLimited.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-pcc",
    sportName: _uspsaName,
    name: "PCC",
    divisionNames: [
      uspsaPcc.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-carryoptics",
    sportName: _uspsaName,
    name: "Carry Optics",
    displayName: "CO",
    divisionNames: [
      uspsaCarryOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-locap",
    sportName: _uspsaName,
    name: "Locap",
    divisionNames: [
      uspsaSingleStack.name,
      uspsaLimited10.name,
      uspsaProduction.name,
      uspsaRevolver.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-singlestack",
    sportName: _uspsaName,
    name: "Single Stack",
    displayName: "SS",
    divisionNames: [
      uspsaSingleStack.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-production",
    sportName: _uspsaName,
    name: "Production",
    displayName: "PROD",
    divisionNames: [
      uspsaProduction.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-limited10",
    sportName: _uspsaName,
    name: "Limited 10",
    displayName: "L10",
    divisionNames: [
      uspsaLimited10.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-revolver",
    sportName: _uspsaName,
    name: "Revolver",
    displayName: "REVO",
    divisionNames: [
      uspsaRevolver.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-open-pcc",
    sportName: _uspsaName,
    name: "Open/PCC",
    divisionNames: [
      uspsaOpen.name,
      uspsaPcc.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-limited-co",
    sportName: _uspsaName,
    name: "Limited/Carry Optics",
    displayName: "LIM/CO",
    divisionNames: [
      uspsaLimited.name,
      uspsaCarryOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-limited-optics",
    sportName: _uspsaName,
    name: "Limited Optics",
    displayName: "LO",
    divisionNames: [
      uspsaLimitedOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-lo-co",
    sportName: _uspsaName,
    name: "LO/CO",
    divisionNames: [
      uspsaLimitedOptics.name,
      uspsaCarryOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-lim-lo-co",
    sportName: _uspsaName,
    name: "Limited/LO/CO",
    displayName: "Lim/LO/CO",
    divisionNames: [
      uspsaLimited.name,
      uspsaLimitedOptics.name,
      uspsaCarryOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-limited-lo",
    sportName: _uspsaName,
    name: "Limited/LO",
    divisionNames: [
      uspsaLimited.name,
      uspsaLimitedOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-optic-handguns",
    sportName: _uspsaName,
    name: "Optic Handguns",
    displayName: "Optics",
    divisionNames: [
      uspsaOpen.name,
      uspsaCarryOptics.name,
      uspsaLimitedOptics.name,
    ],
  ),
  DbRatingGroup.create(
    uuid: "uspsa-irons-handguns",
    sportName: _uspsaName,
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
  DbRatingGroup.create(
    uuid: "uspsa-combined",
    sportName: _uspsaName,
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