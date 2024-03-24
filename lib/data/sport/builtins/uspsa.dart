/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
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
  shooterDeduplicator: const USPSADeduplicator(),
  eventLevels: [
    const MatchLevel(name: "Level I", shortName: "I", alternateNames: ["Local"], eventLevel: EventLevel.local),
    const MatchLevel(name: "Level II", shortName: "II", alternateNames: ["Regional/State"], eventLevel: EventLevel.regional),
    const MatchLevel(name: "Level III", shortName: "III", alternateNames: ["Area/National"], eventLevel: EventLevel.national),
  ],
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
        const ScoringEvent("C", pointChange: 4),
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
        const ScoringEvent("C", pointChange: 0),
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
  ratingStrengthProvider: UspsaRatingStrengthProvider(),
  pubstompProvider: UspsaPubstompProvider(),
);

class UspsaRatingStrengthProvider implements RatingStrengthProvider {
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
}

class UspsaPubstompProvider implements PubstompProvider {
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