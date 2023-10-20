import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final icoreSport = Sport(
    "ICORE",
    matchScoring: CumulativeScoring(),
    defaultStageScoring: const TimePlusScoring(),
    hasStages: true,
    classifications: [
      const Classification(index: 0, name: "Grandmaster", shortName: "GM"),
      const Classification(index: 1, name: "Master", shortName: "M"),
      const Classification(index: 2, name: "A", shortName: "A"),
      const Classification(index: 3, name: "B", shortName: "B"),
      const Classification(index: 4, name: "C", shortName: "C"),
      const Classification(index: 5, name: "D", shortName: "D"),
      const Classification(index: 6, name: "Unclassified", shortName: "U"),
    ],
    divisions: [
      const Division(name: "Open", shortName: "OPEN"),
      const Division(name: "Limited", shortName: "LIM"),
      const Division(name: "Limited 6", shortName: "LIM6"),
      const Division(name: "Classic", shortName: "CLS"),
    ],
    powerFactors: [
      PowerFactor("Standard",
        targetEvents: [
          const ScoringEvent("X", timeChange: -1),
          const ScoringEvent("A", timeChange: 0),
          const ScoringEvent("B", timeChange: 1),
          const ScoringEvent("C", timeChange: 2),
          const ScoringEvent("M", timeChange: 5),
          const ScoringEvent("NS", timeChange: 5),
        ],
      ),
      PowerFactor("Heavy Metal",
        targetEvents: [
          const ScoringEvent("X", timeChange: -1),
          const ScoringEvent("A", timeChange: 0),
          const ScoringEvent("B", timeChange: 0),
          const ScoringEvent("C", timeChange: 2),
          const ScoringEvent("M", timeChange: 5),
          const ScoringEvent("NS", timeChange: 5),
        ],
      ),
    ]
);