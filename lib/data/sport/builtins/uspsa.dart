import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _uspsaPenalties = [
  ScoringEvent("Procedural", pointChange: -10),
  ScoringEvent("Overtime shot", pointChange: -5),
];

final uspsaSport = Sport(
  "USPSA",
  scoring: SportScoring.hitFactor,
  hasStages: true,
  classifications: [
    SportClassification(name: "Grandmaster", shortName: "GM"),
    SportClassification(name: "Master", shortName: "M"),
    SportClassification(name: "A", shortName: "A"),
    SportClassification(name: "B", shortName: "B"),
    SportClassification(name: "C", shortName: "C"),
    SportClassification(name: "D", shortName: "D"),
    SportClassification(name: "Unclassified", shortName: "U"),
  ],
  divisions: [
    SportDivision(name: "Open", shortName: "OPEN"),
    SportDivision(name: "Pistol Caliber Carbine", shortName: "PCC"),
    SportDivision(name: "Limited", shortName: "LIM"),
    SportDivision(name: "Limited Optics", shortName: "LO"),
    SportDivision(name: "Carry Optics", shortName: "CO"),
    SportDivision(name: "Production", shortName: "PROD"),
    SportDivision(name: "Single Stack", shortName: "SS"),
    SportDivision(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    SportDivision(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10"]),
  ],
  powerFactors: [
    PowerFactor("Major",
      targetEvents: [
        ScoringEvent("A", pointChange: 5),
        ScoringEvent("C", pointChange: 4),
        ScoringEvent("D", pointChange: 2),
        ScoringEvent("M", pointChange: -10),
        ScoringEvent("NS", pointChange: -10),
      ],
      penaltyEvents: _uspsaPenalties,
    ),
    PowerFactor("Minor",
      targetEvents: [
        ScoringEvent("A", pointChange: 5),
        ScoringEvent("C", pointChange: 3),
        ScoringEvent("D", pointChange: 1),
        ScoringEvent("M", pointChange: -10),
        ScoringEvent("NS", pointChange: -10),
      ],
      penaltyEvents: _uspsaPenalties,
    ),
  ]
);