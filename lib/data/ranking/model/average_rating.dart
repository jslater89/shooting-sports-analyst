/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

class AverageRating {
  final double firstRating;
  final double minRating;
  final double maxRating;
  final double averageOfIntermediates;
  final int window;

  double get averageOfMinMax => (minRating + maxRating) / 2;

  AverageRating({
    required this.firstRating,
    required this.minRating,
    required this.maxRating,
    required this.averageOfIntermediates,
    required this.window,
  });
}