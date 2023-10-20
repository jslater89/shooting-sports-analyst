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