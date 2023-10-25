/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final uhrcSport = Sport(
    "UHRC",
    type: SportType.userDefinedHitFactor,
    matchScoring: CumulativeScoring(),
    defaultStageScoring: const HitFactorScoring(),
    hasStages: true,
    powerFactors: [
      PowerFactor("",
          targetEvents: [
            const ScoringEvent("Red 20", pointChange: 20),
            const ScoringEvent("Red 10", pointChange: 10),
            const ScoringEvent("White 40", pointChange: 40),
            const ScoringEvent("White 20", pointChange: 20),
            const ScoringEvent("White 10", pointChange: 10),
            const ScoringEvent("Blue 80", pointChange: 80),
            const ScoringEvent("Blue 40", pointChange: 40),
            const ScoringEvent("Blue 20", pointChange: 20),
            const ScoringEvent("Blue 10", pointChange: 10),
          ],
          penaltyEvents: [
            const ScoringEvent("FTDR", pointChange: -140),
            const ScoringEvent("Illegal Gear", pointChange: -140),
            const ScoringEvent("Procedural", pointChange: -20),
          ]
      ),
    ]
);