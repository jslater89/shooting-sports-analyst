import 'package:flutter_test/flutter_test.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

void main() {
  test("USPSA scoring", () {
    MatchStage stage1 = MatchStage(
      stageId: 1, name: "Stage 1", minRounds: 10, maxPoints: 50, scoring: const HitFactorScoring()
    );
    MatchStage stage2 = MatchStage(
        stageId: 2, name: "Stage 2", minRounds: 5, maxPoints: 25, scoring: const HitFactorScoring()
    );
    var majorPf = uspsaSport.powerFactors.lookupByName("Major")!;
    var minorPf = uspsaSport.powerFactors.lookupByName("Minor")!;
    MatchEntry entry1 = MatchEntry(
        firstName: "Test",
        lastName: "Winner",
        entryId: 1,
        powerFactor: majorPf,
        scores: {
          stage1: RawScore(
            rawTime: 20,
            scoring: const HitFactorScoring(),
            scoringEvents: {
              majorPf.targetEvents.lookupByName("A")!: 8,
              majorPf.targetEvents.lookupByName("C")!: 2,
            }
          ),
          stage2: RawScore(
              rawTime: 10,
              scoring: const HitFactorScoring(),
              scoringEvents: {
                majorPf.targetEvents.lookupByName("A")!: 3,
                majorPf.targetEvents.lookupByName("C")!: 2,
              }
          )
        },
    );

    MatchEntry entry2 = MatchEntry(
      firstName: "Test",
      lastName: "Shooter",
      entryId: 2,
      powerFactor: minorPf,
      scores: {
        stage1: RawScore(
            rawTime: 20,
            scoring: const HitFactorScoring(),
            scoringEvents: {
              minorPf.targetEvents.lookupByName("A")!: 7,
              minorPf.targetEvents.lookupByName("C")!: 3,
            }
        ),
        stage2: RawScore(
            rawTime: 10,
            scoring: const HitFactorScoring(),
            scoringEvents: {
              minorPf.targetEvents.lookupByName("A")!: 5,
            }
        )
      },
    );

    var match = ShootingMatch(
      eventName: "Test match",
      date: DateTime.now(),
      rawDate: "",
      sport: uspsaSport,
      shooters: [entry1, entry2],
      stages: [stage1, stage2],
    );

    var scores = match.getScores();

    print("Success!");
  });
}