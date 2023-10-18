import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _uspsaPenalties = [
  const ScoringEvent("Procedural", pointChange: -10),
  const ScoringEvent("Overtime shot", pointChange: -5),
];

final sport = Sport(
  "USPSA",
  matchScoring: RelativeStageFinishScoring(),
  stageScoring: StageScoring.hitFactor,
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
    const Division(name: "Pistol Caliber Carbine", shortName: "PCC"),
    const Division(name: "Limited", shortName: "LIM", alternateNames: ["LTD"]),
    const Division(name: "Limited Optics", shortName: "LO"),
    const Division(name: "Carry Optics", shortName: "CO"),
    const Division(name: "Production", shortName: "PROD"),
    const Division(name: "Single Stack", shortName: "SS"),
    const Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    const Division(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10", "LTD10"]),
  ],
  powerFactors: [
    PowerFactor("Major",
      targetEvents: [
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 4),
        const ScoringEvent("D", pointChange: 2),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
      ],
      penaltyEvents: _uspsaPenalties,
    ),
    PowerFactor("Minor",
      targetEvents: [
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 3),
        const ScoringEvent("D", pointChange: 1),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
      ],
      penaltyEvents: _uspsaPenalties,
    ),
  ]
);