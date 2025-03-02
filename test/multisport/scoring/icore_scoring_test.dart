/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

void main() {
  test("ICORE scoring", () {
    MatchStage stage1 = MatchStage(
        stageId: 1, name: "Stage 1", minRounds: 10, maxPoints: 50, scoring: const TimePlusScoring()
    );
    MatchStage stage2 = MatchStage(
        stageId: 2, name: "Stage 2", minRounds: 5, maxPoints: 25, scoring: const TimePlusScoring(),
        scoringOverrides: {
          icoreX.name: ScoringEventOverride.time(icoreX.name, -0.5),
        }
    );

    // Total time: 20.5
    var jimBig6 = MatchEntry(
      firstName: "Jim",
      lastName: "Big 6",
      entryId: 1,
      division: icoreSport.divisions.lookupByName("Big 6"),
      powerFactor: icoreSport.powerFactors.values.firstWhere((p) => p.name == "Big 6"),
      scores: {
        // expected score: raw time of 10 plus 0 for big 6 Bs, -1 for X: 9
        stage1: RawScore(
          rawTime: 10,
          scoring: const TimePlusScoring(),
          targetEvents: {icoreA: 10, icoreBig6B: 2, icoreX: 1},
        ),
        // expected score: raw time of 10 plus 0 for big 6 Bs, +2 for C, -0.5 for overriden X: 11.5
        stage2: RawScore(
          rawTime: 10,
          scoring: const TimePlusScoring(),
          targetEvents: {icoreA: 10, icoreBig6B: 1, icoreC: 1, icoreX: 1},
          scoringOverrides: {icoreX.name: ScoringEventOverride.time(icoreX.name, -0.5)},
        ),
      }
    );
    
    // Total time: 23.5
    var openGuy = MatchEntry(
      firstName: "Open",
      lastName: "Guy",
      entryId: 2,
      division: icoreSport.divisions.lookupByName("Open"),
      powerFactor: icoreSport.powerFactors.values.firstWhere((p) => p.name == "Standard"),
      scores: {
        // expected score: raw time of 10 plus 0 for A, +1 per B (+2), -1 for X: 11
        stage1: RawScore(
          rawTime: 10,
          scoring: const TimePlusScoring(),
          targetEvents: {icoreA: 10, icoreB: 2, icoreX: 1},
        ),
        // expected score: raw time of 10 plus 0 for A, +1 per B (+1), +2 per C (+2), -0.5 for X: 12.5
        stage2: RawScore(
          rawTime: 10,
          scoring: const TimePlusScoring(),
          targetEvents: {icoreA: 10, icoreB: 1, icoreC: 1, icoreX: 1},
          scoringOverrides: {icoreX.name: ScoringEventOverride.time(icoreX.name, -0.5)},
        ),
      },
    );

    var match = ShootingMatch(
      name: "Test Match",
      rawDate: "10/20/2024",
      date: DateTime(2024, 10, 20),
      sport: icoreSport,
      stages: [stage1, stage2],
      shooters: [jimBig6, openGuy],
    );
    
    var scores = match.getScores(
      shooters: [jimBig6, openGuy],
      stages: [stage1, stage2],
    );

    expect(scores.length, 2);
    var firstPlace = scores.entries.first;
    var lastPlace = scores.entries.last;

    expect(firstPlace.key.entryId, 1);
    expect(lastPlace.key.entryId, 2);
    expect(firstPlace.value.points, 20.5);
    expect(lastPlace.value.points, 23.5);
  });
}