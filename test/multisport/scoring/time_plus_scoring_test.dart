import 'package:flutter_test/flutter_test.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/idpa.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

void main() {
  test("Time plus scoring", () {
    MatchStage stage1 = MatchStage(
        stageId: 1, name: "Stage 1", minRounds: 10, maxPoints: 50, scoring: const TimePlusScoring()
    );
    MatchStage stage2 = MatchStage(
        stageId: 2, name: "Stage 2", minRounds: 5, maxPoints: 25, scoring: const TimePlusScoring()
    );
    var pf = idpaSport.powerFactors.values.first;
    MatchEntry entry1 = MatchEntry(
      firstName: "Test",
      lastName: "Winner",
      entryId: 1,
      powerFactor: pf,
      scores: {
        stage1: RawScore(
            rawTime: 20,
            scoring: const TimePlusScoring(),
            scoringEvents: {
              pf.targetEvents.lookupByName("-0")!: 8,
              pf.targetEvents.lookupByName("-1")!: 1,
              pf.targetEvents.lookupByName("-3")!: 1,
            }
        ),
        stage2: RawScore(
            rawTime: 10,
            scoring: const TimePlusScoring(),
            scoringEvents: {
              pf.targetEvents.lookupByName("-0")!: 5,
            }
        )
      },
    );

    MatchEntry entry2 = MatchEntry(
      firstName: "Test",
      lastName: "Shooter",
      entryId: 2,
      powerFactor: pf,
      scores: {
        stage1: RawScore(
            rawTime: 20,
            scoring: const TimePlusScoring(),
            scoringEvents: {
              pf.targetEvents.lookupByName("-0")!: 7,
              pf.targetEvents.lookupByName("-1")!: 3,
            }
        ),
        stage2: RawScore(
          rawTime: 10,
          scoring: const TimePlusScoring(),
          scoringEvents: {
            pf.targetEvents.lookupByName("-0")!: 5,
          },
          penaltyEvents: {
            pf.penaltyEvents.lookupByName("PE")!: 1,
          }
        )
      },
    );

    var match = ShootingMatch(
      eventName: "Test match",
      date: DateTime.now(),
      rawDate: "",
      sport: idpaSport,
      shooters: [entry1, entry2],
      stages: [stage1, stage2],
    );

    var scores = match.getScores();

    assert(scores[entry1]!.place == 1);
    assert(scores[entry1]!.points == 34.0);
    assert(scores[entry2]!.place == 2);
    assert(scores[entry2]!.points == 36.0);
    print("Success!");
  });
}