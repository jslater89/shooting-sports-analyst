/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final claysSport = Sport(
    "Sporting Clays",
    matchScoring: CumulativeScoring(),
    defaultStageScoring: const PointsScoring(),
    hasStages: false,
    powerFactors: [
      PowerFactor("",
        targetEvents: [
          const ScoringEvent("Bird", pointChange: 1),
        ],
      ),
    ]
);