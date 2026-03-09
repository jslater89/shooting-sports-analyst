/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/place_evaluation.dart';

void main() {
  BayesianOddsWager placeWager(int bestPlace, int worstPlace) {
    final prediction = DbPrediction()
      ..type = DbPredictionType.place
      ..bestPlace = bestPlace
      ..worstPlace = worstPlace;
    return BayesianOddsWager(
      wagerId: 1,
      amount: 10,
      maxWager: 100,
      sharpness: 1.0,
      resolvedPlayerWagers: 10,
      daysUntilMatch: 0,
      prediction: prediction,
    );
  }

  /// Build a Monte Carlo result from a list of place finishes (percentages filled with dummy values).
  MonteCarloSimulationResult mcFromPlaces(List<int> places) {
    return MonteCarloSimulationResult(
      places: places,
      percentages: List.filled(places.length, 0.5),
    );
  }

  group("Smooth place evaluation — overwhelmingly 2nd", () {
    /// Distribution from the reported case: heavily favored to finish 2nd.
    /// At delta=0, only 1st-place trials count for "1st". At delta=0.5, 1st and 2nd both count.
    test("P(1st) at delta=0 is model 1st proportion; at delta=0.5 includes 2nd-place mass", () {
      final places = [
        ...List.filled(1558, 1),
        ...List.filled(10671, 2),
        ...List.filled(188, 3),
        ...List.filled(62, 4),
        ...List.filled(12, 5),
      ];
      final n = places.length;
      final monteCarlo = mcFromPlaces(places);
      final wager1st = placeWager(1, 1);

      final p0 = wager1st.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      final p05 = wager1st.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo);

      // At delta=0: only place-1 trials contribute 1; place-2 have s=2, contribution 0.
      expect(p0, closeTo(1558 / n, 1e-6));
      // At delta=0.5: place-1 and place-2 both in plateau for "1st" (s=0.5..1.5 and s=1.5).
      expect(p05, closeTo((1558 + 10671) / n, 1e-6));
    });

    test("P(1st) increases smoothly between delta=0 and delta=0.5", () {
      final places = [
        ...List.filled(1558, 1),
        ...List.filled(10671, 2),
        ...List.filled(188, 3),
        ...List.filled(62, 4),
        ...List.filled(12, 5),
      ];
      final n = places.length;
      final monteCarlo = mcFromPlaces(places);
      final wager1st = placeWager(1, 1);

      final p0 = wager1st.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      final p025 = wager1st.evaluatePlaceAgainstSimulation(delta: 0.25, monteCarlo: monteCarlo);
      final p05 = wager1st.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo);

      // At delta=0.25, place-2 trials have s=1.75; upper ramp (2 - 1.75)/0.5 = 0.5 each.
      final expectedP025 = (1558 + 10671 * 0.5) / n;
      expect(p025, closeTo(expectedP025, 1e-6));
      expect(p0, lessThan(p025));
      expect(p025, lessThan(p05));
    });

    test("P(2nd) at delta=0 is model 2nd proportion; at delta=0.5 includes 2nd and 3rd (plateau [1.5, 2.5])", () {
      final places = [
        ...List.filled(1558, 1),
        ...List.filled(10671, 2),
        ...List.filled(188, 3),
        ...List.filled(62, 4),
        ...List.filled(12, 5),
      ];
      final n = places.length;
      final monteCarlo = mcFromPlaces(places);
      final wager2nd = placeWager(2, 2);

      final p0 = wager2nd.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      final p05 = wager2nd.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo);

      // At delta=0: place-2 trials in plateau [1.5, 2.5] for "2nd".
      expect(p0, closeTo(10671 / n, 1e-6));
      // At delta=0.5: place-2 have s=1.5, place-3 have s=2.5; both in plateau [1.5, 2.5] for [2,2].
      expect(p05, closeTo((10671 + 188) / n, 1e-6));
    });
  });

  group("Smooth place evaluation — boundaries", () {
    test("single trial at place 2: P(1st) is 0 at delta=0, 1 at delta=0.5, 0.5 at delta=0.25", () {
      final monteCarlo = mcFromPlaces([2]);
      final wager1st = placeWager(1, 1);

      expect(wager1st.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo), equals(0.0));
      expect(wager1st.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo), equals(1.0));
      expect(wager1st.evaluatePlaceAgainstSimulation(delta: 0.25, monteCarlo: monteCarlo), closeTo(0.5, 1e-10));
    });

    test("single trial at place 1: P(1st) is 1 for delta 0 and 0.5", () {
      final monteCarlo = mcFromPlaces([1]);
      final wager1st = placeWager(1, 1);

      expect(wager1st.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo), equals(1.0));
      expect(wager1st.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo), equals(1.0));
    });

    test("range 1st-2nd: at delta=0.5 both place-1 and place-2 contribute fully", () {
      final monteCarlo = mcFromPlaces([1, 2, 2, 2]); // 1 first, 3 second
      final wager1st2nd = placeWager(1, 2);

      final p0 = wager1st2nd.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      final p05 = wager1st2nd.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo);

      // Plateau [0.5, 2.5]: all four trials in range. Raw 1.0 clamped to (N-1)/N = 0.75.
      expect(p0, equals(0.75));
      expect(p05, equals(0.75));
    });

    test("range 1st-3rd: at delta=0 mass in 1,2,3; at delta=0.5 all six in plateau [0.5, 3.5]", () {
      final places = [1, 2, 2, 3, 3, 3]; // 1 + 2 + 3
      final monteCarlo = mcFromPlaces(places);
      final wager1st3rd = placeWager(1, 3);

      final p0 = wager1st3rd.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      final p05 = wager1st3rd.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo);

      // Raw 1.0 clamped to (N-1)/N = 5/6.
      expect(p0, closeTo(5 / 6, 1e-10));
      expect(p05, closeTo(5 / 6, 1e-10));
    });
  });

  group("place_evaluation module — placeShifted", () {
    test("place - delta, clamped to min 0.5", () {
      expect(placeShifted(1, 0.0), equals(1.0));
      expect(placeShifted(1, 0.5), equals(0.5));
      expect(placeShifted(1, 1.0), equals(0.5));
      expect(placeShifted(2, 0.5), equals(1.5));
      expect(placeShifted(2, 1.2), closeTo(0.8, 1e-10));
    });
  });

  group("place_evaluation module — placeRangeContribution", () {
    test("1st: plateau [0.5, 1.5], upper ramp only", () {
      expect(placeRangeContribution(0.5, 1, 1), equals(1.0));
      expect(placeRangeContribution(1.0, 1, 1), equals(1.0));
      expect(placeRangeContribution(1.5, 1, 1), equals(1.0));
      expect(placeRangeContribution(1.8, 1, 1), closeTo(0.4, 1e-10)); // (2 - 1.8)/0.5
      expect(placeRangeContribution(2.0, 1, 1), equals(0.0));
      expect(placeRangeContribution(2.5, 1, 1), equals(0.0));
    });

    test("2nd: lower ramp [1, 1.5], plateau [1.5, 2.5], upper ramp [2.5, 3]", () {
      expect(placeRangeContribution(0.9, 2, 2), equals(0.0)); // below L-1
      expect(placeRangeContribution(1.0, 2, 2), equals(0.0)); // (1 - 1)/0.5
      expect(placeRangeContribution(1.25, 2, 2), closeTo(0.5, 1e-10)); // (1.25 - 1)/0.5
      expect(placeRangeContribution(1.5, 2, 2), equals(1.0)); // plateau
      expect(placeRangeContribution(2.0, 2, 2), equals(1.0));
      expect(placeRangeContribution(2.5, 2, 2), equals(1.0));
      expect(placeRangeContribution(2.75, 2, 2), closeTo(0.5, 1e-10)); // (3 - 2.75)/0.5
      expect(placeRangeContribution(3.0, 2, 2), equals(0.0));
    });

    test("lower edge ramp: trial at place 2 as delta increases past 0.5", () {
      // s = 2 - delta. Delta 0.5 -> s=1.5 (plateau). Delta 0.6 -> s=1.4 (ramp). Delta 1.0 -> s=1.0 (ramp start).
      expect(placeRangeContribution(placeShifted(2, 0.5), 2, 2), equals(1.0));
      expect(placeRangeContribution(placeShifted(2, 0.6), 2, 2), closeTo(0.8, 1e-10)); // s=1.4, (1.4-1)/0.5
      expect(placeRangeContribution(placeShifted(2, 0.75), 2, 2), closeTo(0.5, 1e-10)); // s=1.25
      expect(placeRangeContribution(placeShifted(2, 1.0), 2, 2), equals(0.0)); // s=1.0
    });
  });

  group("Smooth place evaluation — lower edge (2nd place)", () {
    test("P(2nd) decreases smoothly as delta increases past 0.5 (one trial at place 2)", () {
      final monteCarlo = mcFromPlaces([2]);
      final wager2nd = placeWager(2, 2);

      final p05 = wager2nd.evaluatePlaceAgainstSimulation(delta: 0.5, monteCarlo: monteCarlo);
      final p06 = wager2nd.evaluatePlaceAgainstSimulation(delta: 0.6, monteCarlo: monteCarlo);
      final p10 = wager2nd.evaluatePlaceAgainstSimulation(delta: 1.0, monteCarlo: monteCarlo);

      expect(p05, equals(1.0));
      expect(p06, closeTo(0.8, 1e-10));
      expect(p10, equals(0.0));
    });
  });

  group("Smooth place evaluation — clamp", () {
    test("single trial: no clamp to [1/N,(N-1)/N], raw is clamped to [0, 1]", () {
      final monteCarlo = mcFromPlaces([1]);
      final wager1st = placeWager(1, 1);
      final p = wager1st.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      expect(p, equals(1.0));
    });

    test("many trials: raw sum/trials is clamped to [1/N, (N-1)/N] when applicable", () {
      final n = 100;
      final monteCarlo = mcFromPlaces(List.filled(n, 1));
      final wager1st = placeWager(1, 1);
      final p = wager1st.evaluatePlaceAgainstSimulation(delta: 0.0, monteCarlo: monteCarlo);
      expect(p, closeTo((n - 1) / n, 1e-10));
    });
  });
}
