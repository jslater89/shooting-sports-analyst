import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _idpaPenalties = [
  ScoringEvent("Procedural", timeChange: 3),
];

final _idpaSport = Sport(
    "IDPA",
    scoring: SportScoring.timePlus,
    hasStages: true,
    classifications: [
      SportClassification(name: "Distinguished Master", shortName: "DM"),
      SportClassification(name: "Master", shortName: "MA"),
      SportClassification(name: "Expert", shortName: "EX"),
      SportClassification(name: "Sharpshooter", shortName: "SS"),
      SportClassification(name: "Novice", shortName: "NV"),
      SportClassification(name: "Unclassified", shortName: "UN"),
    ],
    divisions: [
      SportDivision(name: "Stock Service Pistol", shortName: "SSP"),
      SportDivision(name: "Pistol Caliber Carbine", shortName: "PCC"),
      SportDivision(name: "Enhanced Service Pistol", shortName: "ESP"),
      SportDivision(name: "Custom Defensive Pistol", shortName: "LO"),
      SportDivision(name: "Carry Optics", shortName: "CO"),
      SportDivision(name: "Compact Carry Pistol", shortName: "CCP"),
      SportDivision(name: "Backup Gun", shortName: "BUG"),
      SportDivision(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    ],
    powerFactors: [
      PowerFactor("",
        targetEvents: [
          ScoringEvent("-1", timeChange: 1),
          ScoringEvent("-3", timeChange: 3),
          ScoringEvent("Miss", timeChange: 5),
          ScoringEvent("Non-threat", timeChange: 5),
        ],
        penaltyEvents: _idpaPenalties,
      ),
    ]
);