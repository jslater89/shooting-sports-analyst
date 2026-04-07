/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

double placeWagerSimilarity({
  required int aBestPlace,
  required int aWorstPlace,
  required int bBestPlace,
  required int bWorstPlace,
}) {
  var (int a, int b) = (aBestPlace, aWorstPlace);
  var (int x, int y) = (bBestPlace, bWorstPlace);

  int left = max(a, x);
  int right = min(b, y);
  int intersection = max(0, right - left + 1);
  int sizeFrom = y - x + 1;
  if(sizeFrom == 0) {
    return 0.0;
  }
  return intersection / sizeFrom;
}

double percentageWagerSimilarity({
  required double aPercentage,
  required bool aAbove,
  required double bPercentage,
  required bool bAbove,
  double steepness = 20,
  double maxDistance = 0.05,
}) {
  // Predictions in opposite directions are always dissimilar.
  if(aAbove != bAbove) {
    return 0.0;
  }

  // If the predictions are too far apart, they are dissimilar.
  double distance = (aPercentage - bPercentage).abs();
  if(distance > maxDistance) {
    return 0.0;
  }

  // Otherwise, the similarity is a sigmoid function of the distance.
  double x = distance / maxDistance;
  return 1 / (1 + exp(steepness * (x - 0.5)));
}