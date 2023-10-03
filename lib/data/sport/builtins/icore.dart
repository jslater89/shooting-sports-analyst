import 'package:uspsa_result_viewer/data/sport/sport.dart';

final icoreSport = Sport(
    "ICORE",
    scoring: SportScoring.timePlus,
    hasStages: true,
    classifications: [
      const SportClassification(name: "Grandmaster", shortName: "GM"),
      const SportClassification(name: "Master", shortName: "M"),
      const SportClassification(name: "A", shortName: "A"),
      const SportClassification(name: "B", shortName: "B"),
      const SportClassification(name: "C", shortName: "C"),
      const SportClassification(name: "D", shortName: "D"),
      const SportClassification(name: "Unclassified", shortName: "U"),
    ],
    divisions: [
      const SportDivision(name: "Open", shortName: "OPEN"),
      const SportDivision(name: "Limited", shortName: "LIM"),
      const SportDivision(name: "Limited 6", shortName: "LIM6"),
      const SportDivision(name: "Classic", shortName: "CLS"),
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