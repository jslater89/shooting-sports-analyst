import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _idpaPenalties = [
];

final _claysSport = Sport(
    "Sporting Clays",
    matchScoring: CumulativeScoring(),
    stageScoring: StageScoring.points,
    hasStages: false,
    powerFactors: [
      PowerFactor("",
        targetEvents: [
          const ScoringEvent("Bird", pointChange: 1),
        ],
      ),
    ]
);