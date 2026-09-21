/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/booth/shooter_overrides.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

void main() {
  late Sport sport;
  late PowerFactor sub;
  late PowerFactor minor;
  late MatchStage stage;

  setUp(() {
    sport = uspsaSport;
    sub = sport.powerFactors.lookupByName("Subminor", fallback: false)!;
    minor = sport.powerFactors.lookupByName("Minor", fallback: false)!;
    stage = MatchStage(
      stageId: 1,
      name: "Stage 1",
      scoring: sport.defaultStageScoring,
      minRounds: 10,
      maxPoints: 50,
    );
  });

  MatchEntry shooterOnSubminor() {
    var aSub = sub.targetEvents.lookupByName("A")!;
    var cSub = sub.targetEvents.lookupByName("C")!;
    return MatchEntry(
      firstName: "Christian",
      lastName: "Sailer",
      entryId: 1,
      memberNumber: "L4698",
      sourceId: "sailer-1",
      powerFactor: sub,
      division: uspsaCarryOptics,
      scores: {
        stage: RawScore(
          scoring: sport.defaultStageScoring,
          rawTime: 12.34,
          targetEvents: {aSub: 8, cSub: 2},
          penaltyEvents: {},
        ),
      },
    );
  }

  test("subminor override remaps hits onto minor scoring events", () {
    expect(sub.doesNotScore, isTrue);
    var shooter = shooterOnSubminor();
    var store = ShooterOverrideStore.instance;
    var override = ShooterOverride(
      sourceId: "sailer-1",
      powerFactorName: "Minor",
      originalPowerFactorName: "Subminor",
    );
    expect(override.differsFromOriginal, isTrue);
    expect(store.applyOverride(sport, shooter, override), isTrue);
    expect(shooter.powerFactor.name, "Minor");

    var score = shooter.scores.values.single;
    var aMinor = minor.targetEvents.lookupByName("A")!;
    var cMinor = minor.targetEvents.lookupByName("C")!;
    expect(score.targetEvents[aMinor], 8);
    expect(score.targetEvents[cMinor], 2);
    expect(score.points, 8 * 5 + 2 * 3);

    expect(store.applyOverride(sport, shooter, override), isFalse);
    expect(score.targetEvents[aMinor], 8);
    expect(score.targetEvents[cMinor], 2);
    expect(score.points, 8 * 5 + 2 * 3);
  });

  test("revert restores the server power factor and its hit counts", () {
    var shooter = shooterOnSubminor();
    var store = ShooterOverrideStore.instance;
    var override = ShooterOverride(
      sourceId: "sailer-1",
      powerFactorName: "Minor",
      originalPowerFactorName: "Subminor",
      originalDivisionName: "Carry Optics",
    );
    store.applyOverride(sport, shooter, override);
    expect(store.revert(sport, shooter, override), isTrue);
    expect(shooter.powerFactor.name, "Subminor");

    var score = shooter.scores.values.single;
    var aSub = sub.targetEvents.lookupByName("A")!;
    var cSub = sub.targetEvents.lookupByName("C")!;
    expect(score.targetEvents[aSub], 8);
    expect(score.targetEvents[cSub], 2);
    expect(score.points, 0);
  });

  test("an unknown power factor name leaves the shooter unchanged", () {
    var shooter = shooterOnSubminor();
    var store = ShooterOverrideStore.instance;
    expect(
      store.applyOverride(
        sport,
        shooter,
        ShooterOverride(powerFactorName: "nope"),
      ),
      isFalse,
    );
    expect(shooter.powerFactor.name, "Subminor");
    expect(shooter.scores.values.single.points, 0);
  });

  test("a booth edit does not change the downloaded match", () {
    var updated = DateTime.utc(2026, 9, 21, 18);
    var match = ShootingMatch(
      name: "Booth Dummy Match",
      rawDate: "2026-09-21",
      date: DateTime.utc(2026, 9, 21),
      sourceLastUpdated: updated,
      sourceCode: "ssa_server",
      sourceIds: const ["booth-dummy-1"],
      sport: sport,
      stages: [stage],
      shooters: [shooterOnSubminor()],
    );
    var edited = copyMatchForLocalEdit(match);
    expect(edited.sourceLastUpdated, updated);
    expect(
      ShooterOverrideStore.instance.applyOverride(
        sport,
        edited.shooters.single,
        ShooterOverride(
          sourceId: "sailer-1",
          powerFactorName: "Minor",
          originalPowerFactorName: "Subminor",
        ),
      ),
      isTrue,
    );
    expect(match.shooters.single.powerFactor.name, "Subminor");
    expect(match.shooters.single.scores.values.single.points, 0);
    expect(edited.shooters.single.powerFactor.name, "Minor");
    expect(edited.shooters.single.scores.values.single.points, greaterThan(0));
  });

  test("saving the server values is not an override", () {
    var same = ShooterOverride(
      powerFactorName: "Subminor",
      divisionName: "Carry Optics",
      originalPowerFactorName: "Subminor",
      originalDivisionName: "Carry Optics",
    );
    expect(same.differsFromOriginal, isFalse);
  });
}
