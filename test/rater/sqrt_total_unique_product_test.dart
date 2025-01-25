/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/data/ranking/connectivity/sqrt_total_unique_product.dart';

import '../matchers/almost_equals.dart';

void main() {
  test("SqrtTotalUniqueProductCalculator getScaleFactor", () {
    var calc = SqrtTotalUniqueProductCalculator();
    expect(calc.getScaleFactor(connectivity: 100.0, baseline: 100.0), almostEquals(1.0));
    expect(calc.getScaleFactor(connectivity: 200.0, baseline: 100.0), almostEquals(1.2));
    expect(calc.getScaleFactor(connectivity: 50.0, baseline: 100.0), almostEquals(0.8));
    expect(calc.getScaleFactor(connectivity: 150.0, baseline: 100.0), almostEquals(1.1));
    expect(calc.getScaleFactor(connectivity: 75.0, baseline: 100.0), almostEquals(0.9));
  });
}
