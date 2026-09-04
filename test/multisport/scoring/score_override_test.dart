/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/data/sport/builtins/uspsa.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";

void main() {
  final major = uspsaSport.powerFactors.lookupByName("Major")!;
  final a = major.targetEvents.lookupByName("A")!;
  final c = major.targetEvents.lookupByName("C")!;
  final procedural = major.penaltyEvents.lookupByName("Procedural")!;

  RawScore eventScore({
    required double time,
    int alphas = 0,
    int charlies = 0,
    int procedurals = 0,
  }) {
    return RawScore(
      scoring: const HitFactorScoring(),
      rawTime: time,
      targetEvents: {
        if(alphas > 0) a: alphas,
        if(charlies > 0) c: charlies,
      },
      penaltyEvents: {
        if(procedurals > 0) procedural: procedurals,
      },
    );
  }

  RawScore overrideScore({
    required double time,
    int? pointsOverride,
    double? finalTimeOverride,
  }) {
    return RawScore(
      scoring: const HitFactorScoring(),
      rawTime: time,
      targetEvents: {},
      pointsOverride: pointsOverride,
      finalTimeOverride: finalTimeOverride,
    );
  }

  group("RawScore overrides", () {
    test("points and finalTime getters use overrides when present", () {
      var withEvents = eventScore(time: 10, alphas: 8);
      expect(withEvents.points, 40);
      expect(withEvents.finalTime, 10);

      var overridden = overrideScore(time: 10, pointsOverride: 95, finalTimeOverride: 11.5);
      expect(overridden.points, 95);
      expect(overridden.getTotalPoints(), 95);
      expect(overridden.finalTime, 11.5);
      expect(overridden.hitFactor, closeTo(95 / 10, 0.0001));
    });

    test("operator+ does not set overrides when neither operand has them", () {
      var aScore = eventScore(time: 10, alphas: 8);
      var bScore = eventScore(time: 12, alphas: 6, charlies: 2);
      var sum = aScore + bScore;

      expect(sum.pointsOverride, isNull);
      expect(sum.finalTimeOverride, isNull);
      expect(sum.points, 40 + 38);
      expect(sum.finalTime, 22);
      expect(sum.rawTime, 22);
      expect(sum.targetEvents[a], 14);
      expect(sum.targetEvents[c], 2);
    });

    test("operator+ points override is contagious with event-count scores", () {
      var events = eventScore(time: 10, alphas: 8);
      var overridden = overrideScore(time: 12, pointsOverride: 100);
      var sum = events + overridden;

      expect(sum.pointsOverride, 140);
      expect(sum.points, 140);
      expect(sum.finalTimeOverride, isNull);
      expect(sum.finalTime, 22);
      expect(sum.rawTime, 22);
      expect(sum.targetEvents[a], 8);
    });

    test("operator+ final time override is contagious with event-count scores", () {
      var events = eventScore(time: 10, alphas: 8);
      var overridden = overrideScore(time: 12, finalTimeOverride: 13.5);
      var sum = events + overridden;

      expect(sum.finalTimeOverride, 23.5);
      expect(sum.finalTime, 23.5);
      expect(sum.pointsOverride, isNull);
      expect(sum.points, 40);
      expect(sum.rawTime, 22);
    });

    test("operator+ both overrides are contagious from a mixed pair", () {
      var events = eventScore(time: 8, alphas: 5, charlies: 2, procedurals: 1);
      var overridden = overrideScore(time: 9, pointsOverride: 90, finalTimeOverride: 9.5);
      var sum = events + overridden;

      // 5A*5 + 2C*4 + 1P*-10 = 25 + 8 - 10 = 23
      expect(sum.pointsOverride, 113);
      expect(sum.points, 113);
      expect(sum.finalTimeOverride, 17.5);
      expect(sum.finalTime, 17.5);
      expect(sum.rawTime, 17);
      expect(sum.targetEvents[a], 5);
      expect(sum.targetEvents[c], 2);
      expect(sum.penaltyEvents[procedural], 1);
    });

    test("operator+ is commutative for mixed override and event scores", () {
      var events = eventScore(time: 10, alphas: 8);
      var overridden = overrideScore(time: 12, pointsOverride: 100, finalTimeOverride: 13.5);

      var left = events + overridden;
      var right = overridden + events;

      expect(left.pointsOverride, right.pointsOverride);
      expect(left.finalTimeOverride, right.finalTimeOverride);
      expect(left.points, right.points);
      expect(left.finalTime, right.finalTime);
      expect(left.rawTime, right.rawTime);
    });
  });

  group("Iterable<RawScore>.sum overrides", () {
    test("sum of event-count scores has no overrides", () {
      var scores = [
        eventScore(time: 10, alphas: 8),
        eventScore(time: 12, alphas: 6, charlies: 2),
      ];
      var sum = scores.sum;

      expect(sum.pointsOverride, isNull);
      expect(sum.finalTimeOverride, isNull);
      expect(sum.points, 78);
      expect(sum.finalTime, 22);
    });

    test("points override is contagious across event-count and override scores", () {
      var scores = [
        eventScore(time: 10, alphas: 8),
        overrideScore(time: 12, pointsOverride: 100),
        eventScore(time: 6, alphas: 3),
      ];
      var sum = scores.sum;

      expect(sum.pointsOverride, 155);
      expect(sum.points, 155);
      expect(sum.finalTimeOverride, isNull);
      expect(sum.finalTime, 28);
      expect(sum.rawTime, 28);
      expect(sum.targetEvents[a], 11);
    });

    test("final time override is contagious across event-count and override scores", () {
      var scores = [
        eventScore(time: 10, alphas: 8),
        overrideScore(time: 12, finalTimeOverride: 13.5),
        eventScore(time: 6, alphas: 3),
      ];
      var sum = scores.sum;

      expect(sum.finalTimeOverride, 29.5);
      expect(sum.finalTime, 29.5);
      expect(sum.pointsOverride, isNull);
      expect(sum.points, 55);
      expect(sum.rawTime, 28);
    });

    test("both overrides are contagious in a three-score mix", () {
      var scores = [
        eventScore(time: 8, alphas: 5),
        overrideScore(time: 9, pointsOverride: 90, finalTimeOverride: 9.5),
        eventScore(time: 6, alphas: 3, charlies: 1),
      ];
      var sum = scores.sum;

      // 25 + 90 + (15 + 4) = 134
      expect(sum.pointsOverride, 134);
      expect(sum.points, 134);
      expect(sum.finalTimeOverride, 23.5);
      expect(sum.finalTime, 23.5);
      expect(sum.rawTime, 23);
      expect(sum.targetEvents[a], 8);
      expect(sum.targetEvents[c], 1);
    });

    test("sum of only override scores keeps combined overrides", () {
      var scores = [
        overrideScore(time: 10, pointsOverride: 80, finalTimeOverride: 10.5),
        overrideScore(time: 12, pointsOverride: 95, finalTimeOverride: 12.25),
      ];
      var sum = scores.sum;

      expect(sum.pointsOverride, 175);
      expect(sum.finalTimeOverride, 22.75);
      expect(sum.points, 175);
      expect(sum.finalTime, 22.75);
      expect(sum.targetEvents, isEmpty);
    });

    test("sum agrees with repeated operator+ for mixed scores", () {
      var scores = [
        eventScore(time: 8, alphas: 5, charlies: 2, procedurals: 1),
        overrideScore(time: 9, pointsOverride: 90, finalTimeOverride: 9.5),
        eventScore(time: 6, alphas: 3),
      ];

      var folded = scores.first;
      for(var i = 1; i < scores.length; i++) {
        folded = folded + scores[i];
      }
      var summed = scores.sum;

      expect(summed.pointsOverride, folded.pointsOverride);
      expect(summed.finalTimeOverride, folded.finalTimeOverride);
      expect(summed.points, folded.points);
      expect(summed.finalTime, folded.finalTime);
      expect(summed.rawTime, folded.rawTime);
    });
  });
}
