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
      final result = marginOfVictoryFunction.calculateScore(0.5, 0.25);
      expect(result, almostEquals(1.0));
    });

    test("returns 1.0 for perfect victory above boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.5, 0.2);
      expect(result, almostEquals(1.0));
    });

    test("returns 0.0 for perfect loss at boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.25, 0.5);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.0 for perfect loss below boundary", () {
      final result = marginOfVictoryFunction.calculateScore(0.2, 0.5);
      expect(result, almostEquals(0.0));
    });

    test("returns 0.75 for halfway to victory", () {
      // margin = 0.125 = 0.25/2
      final result = marginOfVictoryFunction.calculateScore(0.4375, 0.3125);
      expect(result, almostEquals(0.75));
    });

    test("returns 0.25 for halfway to loss", () {
      // margin = -0.125 = -0.25/2
      final result = marginOfVictoryFunction.calculateScore(0.3125, 0.4375);
      expect(result, almostEquals(0.25));
    });

    final marginOfVictoryFunctionCustom = LinearMarginOfVictoryScoreFunction(perfectVictoryDifference: 0.1);
    test("works with custom perfectVictoryDifference - perfect victory", () {
      final result = marginOfVictoryFunctionCustom.calculateScore(0.6, 0.4);
      expect(result, almostEquals(1.0));
    });

    test("works with custom perfectVictoryDifference - linear interpolation", () {
      // margin = 0.05, perfectVictoryDifference = 0.1
      // expected = 0.5 + 0.05 / (2 * 0.1) = 0.5 + 0.05 / 0.2 = 0.5 + 0.25 = 0.75
      final result = marginOfVictoryFunctionCustom.calculateScore(0.55, 0.5);
      expect(result, almostEquals(0.75));
    });

    test("handles very small margins correctly", () {
      // margin = 0.0001
      // expected = 0.5 + 0.0001 / (2 * 0.25) = 0.5 + 0.0001 / 0.5 = 0.5 + 0.0002 = 0.5002
      final result = marginOfVictoryFunction.calculateScore(0.5001, 0.5);
      expect(result, almostEquals(0.5002));
    });

    test("handles negative margins in linear range", () {
      // margin = -0.05
      // expected = 0.5 + (-0.05) / (2 * 0.25) = 0.5 - 0.05 / 0.5 = 0.5 - 0.1 = 0.4
      final result = marginOfVictoryFunction.calculateScore(0.45, 0.5);
      expect(result, almostEquals(0.4));
    });

    test("handles quarter margin to victory", () {
      // margin = 0.0625 = 0.25/4
      // expected = 0.5 + 0.0625 / (2 * 0.25) = 0.5 + 0.0625 / 0.5 = 0.5 + 0.125 = 0.625
      final result = marginOfVictoryFunction.calculateScore(0.40625, 0.34375);
      expect(result, almostEquals(0.625));
    });

    test("handles quarter margin to loss", () {
      // margin = -0.0625 = -0.25/4
      // expected = 0.5 + (-0.0625) / (2 * 0.25) = 0.5 - 0.0625 / 0.5 = 0.5 - 0.125 = 0.375
      final result = marginOfVictoryFunction.calculateScore(0.34375, 0.40625);
      expect(result, almostEquals(0.375));
    });
  });
}

