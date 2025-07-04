/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

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
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 8,
              pf.targetEvents.lookupByName("-1")!: 1,
              pf.targetEvents.lookupByName("-3")!: 1,
            }
        ),
        stage2: RawScore(
            rawTime: 10,
            scoring: const TimePlusScoring(),
            targetEvents: {
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
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 7,
              pf.targetEvents.lookupByName("-1")!: 3,
            }
        ),
        stage2: RawScore(
          rawTime: 10,
          scoring: const TimePlusScoring(),
          targetEvents: {
            pf.targetEvents.lookupByName("-0")!: 5,
          },
          penaltyEvents: {
            pf.penaltyEvents.lookupByName("PE")!: 1,
          }
        )
      },
    );

    var match = ShootingMatch(
      name: "Test match",
      date: DateTime.now(),
      rawDate: "",
      sport: idpaSport,
      shooters: [entry1, entry2],
      stages: [stage1, stage2],
    );

    var scores = match.getScores();

    expect(scores[entry1]!.place, 1);
    expect(scores[entry1]!.points, 34.0);
    expect(scores[entry2]!.place, 2);
    expect(scores[entry2]!.points, 36.0);
    print("Success!");
  });

  test("Score-DQ time-plus scoring", () {
    MatchStage stage1 = MatchStage(
        stageId: 1, name: "Stage 1", minRounds: 10, maxPoints: 50, scoring: const TimePlusScoring()
    );
    MatchStage stage2 = MatchStage(
        stageId: 2, name: "Stage 2", minRounds: 5, maxPoints: 25, scoring: const TimePlusScoring()
    );
    MatchStage stage3 = MatchStage(
        stageId: 3, name: "Stage 3", minRounds: 15, maxPoints: 75, scoring: const TimePlusScoring()
    );
    var pf = idpaSport.powerFactors.values.first;
    MatchEntry entry1 = MatchEntry(
      firstName: "Test",
      lastName: "DQer",
      entryId: 1,
      powerFactor: pf,
      dq: true,
      scores: {
        stage1: RawScore(
            rawTime: 20,
            scoring: const TimePlusScoring(),
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 8,
              pf.targetEvents.lookupByName("-1")!: 1,
              pf.targetEvents.lookupByName("-3")!: 1,
            }
        ),
        stage2: RawScore(
            rawTime: 10,
            scoring: const TimePlusScoring(),
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 5,
            }
        ),
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
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 7,
              pf.targetEvents.lookupByName("-1")!: 3,
            }
        ),
        stage2: RawScore(
            rawTime: 10,
            scoring: const TimePlusScoring(),
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 5,
            },
            penaltyEvents: {
              pf.penaltyEvents.lookupByName("PE")!: 1,
            }
        ),
        stage3: RawScore(
            rawTime: 14,
            scoring: const TimePlusScoring(),
            targetEvents: {
              pf.targetEvents.lookupByName("-0")!: 13,
              pf.targetEvents.lookupByName("-1")!: 2,
            },
        )
      },
    );

    var match = ShootingMatch(
      name: "Test match",
      date: DateTime.now(),
      rawDate: "",
      sport: idpaSport,
      shooters: [entry1, entry2],
      stages: [stage1, stage2, stage3],
    );

    // In DQ mode, entry2 should win with ratio 1.0, and have ratio
    // 1.0 on stage3. entry1 should have the win on stage 2 despite
    // being DQed/DNFed.
    var scores = match.getScores(scoreDQ: true);
    expect(scores[entry1]!.place, 2);
    expect(scores[entry1]!.stageScores[stage3]!.points, 0.0);
    expect(scores[entry1]!.stageScores[stage3]!.ratio, 0.0);
    expect(scores[entry1]!.stageScores[stage2]!.ratio, 1.0);
    expect(scores[entry2]!.place, 1);
    expect(scores[entry2]!.ratio, 1.0);
    expect(scores[entry2]!.stageScores[stage3]!.ratio, 1.0);

    // On the match comprising stage 1 and 2 only,
    scores = match.getScores(scoreDQ: true, stages: [stage1, stage2]);
    expect(scores[entry1]!.place, 1);
    expect(scores[entry1]!.points, 34.0);
    expect(scores[entry2]!.place, 2);
    expect(scores[entry2]!.points, 36.0);

    // In non-DQ mode,
    scores = match.getScores(scoreDQ: false);
    expect(scores[entry1]!.place, 2);
    expect(scores[entry1]!.ratio, 0.0);
    expect(scores[entry1]!.stageScores[stage3]!.points, 0.0);
    expect(scores[entry1]!.stageScores[stage3]!.ratio, 0.0);
    expect(scores[entry1]!.stageScores[stage2]!.ratio, 0.0);
    expect(scores[entry1]!.stageScores[stage1]!.ratio, 0.0);
    expect(scores[entry2]!.place, 1);
    expect(scores[entry2]!.ratio, 1.0);
    expect(scores[entry2]!.stageScores[stage3]!.ratio, 1.0);

    print("Success!");
  });
}
