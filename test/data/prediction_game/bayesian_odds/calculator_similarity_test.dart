/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/calculator.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/config.dart';
import 'package:shooting_sports_analyst/data/prediction_game/bayesian_odds/wager_data.dart';

void main() {
  late BayesianOddsConfig config;

  setUp(() {
    config = BayesianOddsConfig();
  });

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

  BayesianOddsWager percentageWager(double percentage, bool above) {
    final prediction = DbPrediction()
      ..type = DbPredictionType.percentage
      ..percentage = percentage
      ..abovePercentage = above;
    return BayesianOddsWager(
      wagerId: 2,
      amount: 10,
      maxWager: 100,
      sharpness: 1.0,
      resolvedPlayerWagers: 10,
      daysUntilMatch: 0,
      prediction: prediction,
    );
  }

  group("Place similarity (asymmetric)", () {
    test("1st-1st to 1st-3rd is 1.0 (narrow contributor fully supports wider receiver)", () {
      final to = placeWager(1, 3);
      final from = placeWager(1, 1);
      expect(similarityForTesting(to, from, config), equals(1.0));
    });

    test("1st-3rd to 1st-1st is 1/3 (wide contributor partly supports narrow receiver)", () {
      final to = placeWager(1, 1);
      final from = placeWager(1, 3);
      expect(similarityForTesting(to, from, config), closeTo(1 / 3, 1e-10));
    });

    test("1st-10th from 1st-5th is 1.0", () {
      final to = placeWager(1, 10);
      final from = placeWager(1, 5);
      expect(similarityForTesting(to, from, config), equals(1.0));
    });

    test("1st-5th from 1st-10th is 0.5", () {
      final to = placeWager(1, 5);
      final from = placeWager(1, 10);
      expect(similarityForTesting(to, from, config), equals(0.5));
    });

    test("disjoint ranges have similarity 0", () {
      final to = placeWager(1, 10);
      final from = placeWager(12, 16);
      expect(similarityForTesting(to, from, config), equals(0.0));
      expect(similarityForTesting(from, to, config), equals(0.0));
    });

    test("identical range is 1.0 in both directions", () {
      final a = placeWager(1, 5);
      final b = placeWager(1, 5);
      expect(similarityForTesting(a, b, config), equals(1.0));
      expect(similarityForTesting(b, a, config), equals(1.0));
    });

    test("overlapping but not contained: fraction of contributor in receiver", () {
      // 5th-10th from 1st-10th: intersection 6, sizeFrom 10 → 0.6
      final to = placeWager(5, 10);
      final from = placeWager(1, 10);
      expect(similarityForTesting(to, from, config), equals(0.6));
    });
  });

  group("Percentage similarity", () {
    test("same direction, within maxDistance: positive similarity", () {
      final a = percentageWager(0.90, true);
      final b = percentageWager(0.92, true);
      final s = similarityForTesting(a, b, config);
      expect(s, greaterThan(0));
      expect(s, lessThanOrEqualTo(1));
    });

    test("opposite direction: 0", () {
      final a = percentageWager(0.90, true);
      final b = percentageWager(0.90, false);
      expect(similarityForTesting(a, b, config), equals(0.0));
      expect(similarityForTesting(b, a, config), equals(0.0));
    });

    test("same direction, beyond maxDistance: 0", () {
      final configNarrow = BayesianOddsConfig(percentageSimilarityMaxDistance: 0.02);
      final a = percentageWager(0.80, true);
      final b = percentageWager(0.90, true);
      expect(similarityForTesting(a, b, configNarrow), equals(0.0));
    });
  });

  group("Cross-type similarity", () {
    test("place vs percentage is 0", () {
      final place = placeWager(1, 5);
      final pct = percentageWager(0.85, true);
      expect(similarityForTesting(place, pct, config), equals(0.0));
      expect(similarityForTesting(pct, place, config), equals(0.0));
    });
  });
}
