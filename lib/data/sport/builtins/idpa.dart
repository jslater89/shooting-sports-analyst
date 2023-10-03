import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _idpaPenalties = [
  const ScoringEvent("PE", timeChange: 3),
  const ScoringEvent("Flagrant", timeChange: 10),
  const ScoringEvent("FTDR", timeChange: 30),
];

final _idpaSport = Sport(
    "IDPA",
    scoring: SportScoring.timePlus,
    hasStages: true,
    classifications: [
      const SportClassification(name: "Distinguished Master", shortName: "DM"),
      const SportClassification(name: "Master", shortName: "MA"),
      const SportClassification(name: "Expert", shortName: "EX"),
      const SportClassification(name: "Sharpshooter", shortName: "SS"),
      const SportClassification(name: "Novice", shortName: "NV"),
      const SportClassification(name: "Unclassified", shortName: "UN"),
    ],
    divisions: [
      const SportDivision(name: "Stock Service Pistol", shortName: "SSP"),
      const SportDivision(name: "Pistol Caliber Carbine", shortName: "PCC"),
      const SportDivision(name: "Enhanced Service Pistol", shortName: "ESP"),
      const SportDivision(name: "Custom Defensive Pistol", shortName: "LO"),
      const SportDivision(name: "Carry Optics", shortName: "CO"),
      const SportDivision(name: "Compact Carry Pistol", shortName: "CCP"),
      const SportDivision(name: "Backup Gun", shortName: "BUG"),
      const SportDivision(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    ],
    powerFactors: [
      PowerFactor("",
        targetEvents: [
          const ScoringEvent("-0", timeChange: 0),
          const ScoringEvent("-1", timeChange: 1),
          const ScoringEvent("-3", timeChange: 3),
          const ScoringEvent("Miss", timeChange: 5),
          const ScoringEvent("Non-threat", timeChange: 5),
        ],
        penaltyEvents: _idpaPenalties,
      ),
    ]
);