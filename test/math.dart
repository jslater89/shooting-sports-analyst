/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:shooting_sports_analyst/util.dart';

void main() {
  group("lerpAroundCenter", () {
    test("returns minOut when value is below minimum threshold", () {
      // With center=10, centerMinFactor=0.5, bottom=5.0
      // Value of 3.0 is below bottom, should return minOut
      var result = lerpAroundCenter(
        value: 3.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, equals(0.5));

      // Test edge case: exactly at bottom threshold
      result = lerpAroundCenter(
        value: 5.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, equals(0.5));
    });

        test("interpolates between minOut and centerOut when value is between minimum and center", () {
      // With center=10, bottom=5.0, centerOut=1.0, minOut=0.5
      // Value of 7.0 should interpolate between 0.5 and 1.0
      // 7.0 is 2/5 of the way from 5.0 to 10.0, so result should be 0.5 + (1.0-0.5) * (2/5) = 0.7
      var result = lerpAroundCenter(
        value: 7.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, closeTo(0.7, 0.001));

      // Test a point very close to center (9.5) to ensure interpolation direction is correct
      // 9.5 should be 4.5/5 = 0.9 of the way from 5.0 to 10.0
      // Result should be 0.5 + (1.0-0.5) * 0.9 = 0.95 (close to centerOut, not minOut)
      result = lerpAroundCenter(
        value: 9.5,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, closeTo(0.95, 0.001));
    });

    test("returns centerOut when value equals center", () {
      var result = lerpAroundCenter(
        value: 10.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, equals(1.0));
    });

        test("interpolates between centerOut and maxOut when value is between center and maximum", () {
      // With center=10, top=20.0, centerOut=1.0, maxOut=2.0
      // Value of 15.0 should interpolate between 1.0 and 2.0
      // 15.0 is 5/10 = 0.5 of the way from 10.0 to 20.0, so result should be 1.0 + (2.0-1.0) * 0.5 = 1.5
      var result = lerpAroundCenter(
        value: 15.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, closeTo(1.5, 0.001));

      // Test a point very close to center (10.5) to ensure interpolation direction is correct
      // 10.5 should be 0.5/10 = 0.05 of the way from 10.0 to 20.0
      // Result should be 1.0 + (2.0-1.0) * 0.05 = 1.05 (close to centerOut, not maxOut)
      result = lerpAroundCenter(
        value: 10.5,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, closeTo(1.05, 0.001));
    });

    test("returns maxOut when value is above maximum threshold", () {
      // With center=10, centerMaxFactor=2.0, top=20.0
      // Value of 25.0 is above top, should return maxOut
      var result = lerpAroundCenter(
        value: 25.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, equals(2.0));

      // Test edge case: exactly at top threshold
      result = lerpAroundCenter(
        value: 20.0,
        center: 10.0,
        centerMinFactor: 0.5,
        centerMaxFactor: 2.0,
        minOut: 0.5,
        centerOut: 1.0,
        maxOut: 2.0,
      );
      expect(result, equals(2.0));
    });

    test("works correctly with different parameter values", () {
      // Test with different center, factors, and output values
      var result = lerpAroundCenter(
        value: 50.0,
        center: 100.0,
        centerMinFactor: 0.8,  // bottom = 80.0
        centerMaxFactor: 1.5,  // top = 150.0
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // 50.0 is below bottom of 80.0, should return minOut
      expect(result, equals(0.2));

      // Test interpolation in the lower range, close to center
      result = lerpAroundCenter(
        value: 98.0,
        center: 100.0,
        centerMinFactor: 0.8,  // bottom = 80.0
        centerMaxFactor: 1.5,  // top = 150.0
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // 98.0 is 18/20 = 0.9 of the way from 80.0 to 100.0
      // Result should be 0.2 + (0.8-0.2) * 0.9 = 0.74 (close to centerOut, not minOut)
      expect(result, closeTo(0.74, 0.001));

            // Test interpolation in the upper range, close to center
      result = lerpAroundCenter(
        value: 105.0,
        center: 100.0,
        centerMinFactor: 0.8,  // bottom = 80.0
        centerMaxFactor: 1.5,  // top = 150.0
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // 105.0 is 5/50 = 0.1 of the way from 100.0 to 150.0
      // Result should be 0.8 + (1.4-0.8) * 0.1 = 0.86 (close to centerOut, not maxOut)
      expect(result, closeTo(0.86, 0.001));
    });

    test("handles zero center with rangeMin and rangeMax", () {
      // Test below rangeMin
      var result = lerpAroundCenter(
        value: -2.0,
        center: 0.0,
        rangeMin: -1.0,
        rangeMax: 2.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // Value of -2.0 is below rangeMin of -1.0, should return minOut
      expect(result, equals(0.2));

      // Test between rangeMin and center, very close to center
      result = lerpAroundCenter(
        value: -0.1,
        center: 0.0,
        rangeMin: -1.0,
        rangeMax: 2.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // -0.1 is 0.9/1.0 = 0.9 of the way from -1.0 to 0.0
      // Result should be 0.2 + (0.8-0.2) * 0.9 = 0.74 (close to centerOut, not minOut)
      expect(result, closeTo(0.74, 0.001));

      // Test at center
      result = lerpAroundCenter(
        value: 0.0,
        center: 0.0,
        rangeMin: -1.0,
        rangeMax: 2.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // At center, should return centerOut
      expect(result, equals(0.8));

      // Test between center and rangeMax, very close to center
      result = lerpAroundCenter(
        value: 0.1,
        center: 0.0,
        rangeMin: -1.0,
        rangeMax: 2.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // 0.1 is 0.1/2.0 = 0.05 of the way from 0.0 to 2.0
      // Result should be 0.8 + (1.4-0.8) * 0.05 = 0.83 (close to centerOut, not maxOut)
      expect(result, closeTo(0.83, 0.001));

      // Test above rangeMax
      result = lerpAroundCenter(
        value: 3.0,
        center: 0.0,
        rangeMin: -1.0,
        rangeMax: 2.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      );
      // Value of 3.0 is above rangeMax of 2.0, should return maxOut
      expect(result, equals(1.4));
    });

    test("throws error when center is zero without rangeMin/rangeMax", () {
      expect(() => lerpAroundCenter(
        value: 1.0,
        center: 0.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      ), throwsArgumentError);

      // Should also throw if only one range parameter is provided
      expect(() => lerpAroundCenter(
        value: 1.0,
        center: 0.0,
        rangeMin: -1.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      ), throwsArgumentError);

      expect(() => lerpAroundCenter(
        value: 1.0,
        center: 0.0,
        rangeMax: 2.0,
        minOut: 0.2,
        centerOut: 0.8,
        maxOut: 1.4,
      ), throwsArgumentError);
    });

  });
}
