/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

class MonteCarloSimulationResult {
  /// The percentages of the shooter in each trial, ordered by trial number.
  final List<double> percentages;

  /// The places of the shooter in each trial, ordered by trial number.
  final List<int> places;

  MonteCarloSimulationResult({
    required this.percentages,
    required this.places,
  });
}