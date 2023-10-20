import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _idpaPenalties = [
  const ScoringEvent("PE", timeChange: 3),
  const ScoringEvent("Flagrant", timeChange: 10),
  const ScoringEvent("FTDR", timeChange: 30),
];

final idpaSport = Sport(
    "IDPA",
    matchScoring: CumulativeScoring(highScoreWins: false),
    defaultStageScoring: const TimePlusScoring(),
    hasStages: true,
    classifications: [
      const Classification(index: 0, name: "Distinguished Master", shortName: "DM"),
      const Classification(index: 1, name: "Master", shortName: "MA"),
      const Classification(index: 2, name: "Expert", shortName: "EX"),
      const Classification(index: 3, name: "Sharpshooter", shortName: "SS"),
      const Classification(index: 4, name: "Novice", shortName: "NV"),
      const Classification(index: 5, name: "Unclassified", shortName: "UN"),
    ],
    divisions: [
      const Division(name: "Stock Service Pistol", shortName: "SSP"),
      const Division(name: "Pistol Caliber Carbine", shortName: "PCC"),
      const Division(name: "Enhanced Service Pistol", shortName: "ESP"),
      const Division(name: "Custom Defensive Pistol", shortName: "LO"),
      const Division(name: "Carry Optics", shortName: "CO"),
      const Division(name: "Compact Carry Pistol", shortName: "CCP"),
      const Division(name: "Backup Gun", shortName: "BUG"),
      const Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
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