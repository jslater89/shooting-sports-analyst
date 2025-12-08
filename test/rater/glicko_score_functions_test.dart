/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter_test/flutter_test.dart";
import "package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_score_functions.dart";

import "../matchers/almost_equals.dart";

void main() {

  group("linearMarginOfVictoryScoreFunction", () {
    final marginOfVictoryFunction = LinearMarginOfVictoryScoreFunction(perfectVictoryDifference: 0.25);

    test("returns 0.5 for a tie", () {
      final result = marginOfVictoryFunction.calculateScore(0.5, 0.5);
      expect(result, almostEquals(0.5));
    });

    test("returns 1.0 for perfect victory at boundary", () {
      final result = marginOfVictoryFunction.calculateScore(1.0, 0.75);
      expect(result, almostEquals(1.0));
    });

    test("returns 1.0 for perfect victory above boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.75, 0.5);
      expect(result, almostEquals(1.0));
    });

    test("returns 0.0 for perfect loss at boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.75, 1.0);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.0 for perfect loss below boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.75, 1.0);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.75 for halfway to victory", () {
      // margin = 0.125 = 0.25/2
      final result = marginOfVictoryFunction.calculateScore(1.0, 0.875);
      expect(result, almostEquals(0.75));
    });

    test("returns 0.25 for halfway to loss", () {
      // margin = -0.125 = -0.25/2
      final result = marginOfVictoryFunction.calculateScore(0.875, 1.0);
      expect(result, almostEquals(0.25));
    });

    test("returns 1.0 for victory at boundary with non-100% winner", () {
      final result = marginOfVictoryFunction.calculateScore(0.75, 0.5625);
      expect(result, almostEquals(1.0));
    });

    test("returns 0.0 for loss at boundary with non-100% loser", () {
      final result = marginOfVictoryFunction.calculateScore(0.5625, 0.75);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.75 for halfway to victory with non-100% winner", () {
      final result = marginOfVictoryFunction.calculateScore(0.75, 0.65625);
      expect(result, almostEquals(0.75));
    });

    test("returns 0.25 for halfway to loss with non-100% loser", () {
      final result = marginOfVictoryFunction.calculateScore(0.65625, 0.75);
      expect(result, almostEquals(0.25));
    });
  });

  group("linearMarginOfVictoryScoreFunction with 0.1 perfectVictoryDifference", () {
    final marginOfVictoryFunction = LinearMarginOfVictoryScoreFunction(perfectVictoryDifference: 0.1);

    test("returns 0.5 for a tie", () {
      final result = marginOfVictoryFunction.calculateScore(0.5, 0.5);
      expect(result, almostEquals(0.5));
    });

    test("returns 1.0 for perfect victory at boundary", () {
      final result = marginOfVictoryFunction.calculateScore(1.0, 0.9);
      expect(result, almostEquals(1.0));
    });

    test("returns 1.0 for perfect victory above boundary", () {
      final result = marginOfVictoryFunction.calculateScore(1.0, 0.85);
      expect(result, almostEquals(1.0));
    });

    test("returns 0.0 for perfect loss at boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.9, 1.0);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.0 for perfect loss below boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.85, 1.0);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.75 for halfway to victory", () {
      // margin = 0.05 = 0.1/2
      final result = marginOfVictoryFunction.calculateScore(1.0, 0.95);
      expect(result, almostEquals(0.75));
    });

    test("returns 0.25 for halfway to loss", () {
      // margin = -0.05 = -0.1/2
      final result = marginOfVictoryFunction.calculateScore(0.95, 1.0);
      expect(result, almostEquals(0.25));
    });

    test("returns 1.0 for victory at boundary with non-100% winner", () {
      final result = marginOfVictoryFunction.calculateScore(0.75, 0.675);
      expect(result, almostEquals(1.0));
    });

    test("returns 0.0 for loss at boundary with non-100% loser", () {
      final result = marginOfVictoryFunction.calculateScore(0.675, 0.75);
      expect(result, almostEquals(0.0));
    });
  });
}

