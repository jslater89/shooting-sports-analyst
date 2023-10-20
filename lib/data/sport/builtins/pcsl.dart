import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

final _pcslPenalties = [
  const ScoringEvent("Procedural", pointChange: -10),
  const ScoringEvent("Overtime shot", pointChange: -5),
];

final pcslSport = Sport(
  "PCSL",
  matchScoring: RelativeStageFinishScoring(),
  defaultStageScoring: const HitFactorScoring(),
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
    const Division(name: "Limited", shortName: "LIM"),
    const Division(name: "Limited Optics", shortName: "LO"),
    const Division(name: "Carry Optics", shortName: "CO"),
    const Division(name: "Production", shortName: "PROD"),
    const Division(name: "Single Stack", shortName: "SS"),
    const Division(name: "Revolver", shortName: "REV", alternateNames: ["REVO"]),
    const Division(name: "Limited 10", shortName: "L10", alternateNames: ["LIM10"]),
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