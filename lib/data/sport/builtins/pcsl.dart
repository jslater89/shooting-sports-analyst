import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _pcslPenalties = [
  const ScoringEvent("Procedural", pointChange: -10),
  const ScoringEvent("Overtime shot", pointChange: -5),
];

final uspsaSport = Sport(
  "PCSL",
  scoring: SportScoring.hitFactor,
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
    const SportDivision(name: "Pistol Caliber Carbine", shortName: "PCC"),
    const SportDivision(name: "Limited", shortName: "LIM"),
    const SportDivision(name: "Limited Optics", shortName: "LO"),
    const SportDivision(name: "Carry Optics", shortName: "CO"),
    const SportDivision(name: "Production", shortName: "PROD"),
    const SportDivision(name: "Single Stack", shortName: "SS"),
    const SportDivision(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    const SportDivision(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10"]),
  ],
  powerFactors: [
    PowerFactor("",
      targetEvents: [
        const ScoringEvent("K", pointChange: 10),
        const ScoringEvent("A", pointChange: 5),
        const ScoringEvent("C", pointChange: 3),
        const ScoringEvent("D", pointChange: 1),
        const ScoringEvent("M", pointChange: -10),
        const ScoringEvent("NS", pointChange: -10),
      ],
      penaltyEvents: _pcslPenalties,
    ),
  ]
);