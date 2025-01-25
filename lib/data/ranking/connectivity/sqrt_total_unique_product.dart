/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/util.dart';

/// This connectivity calculator uses the square root of the product of the
/// number of unique competitors and the total number of competitors in a
/// particular competitor's record.
class SqrtTotalUniqueProductCalculator implements ConnectivityCalculator {
  @override
  NewConnectivity calculateRatingConnectivity(DbShooterRating rating) {
    Set<int> uniqueCompetitors = {};
    int totalCompetitors = 0;
    for(var w in rating.matchWindows) {
      uniqueCompetitors.addAll(w.uniqueOpponentIds);
      totalCompetitors += w.uniqueOpponentIds.length;
    }
    return NewConnectivity(
      connectivity: sqrt(uniqueCompetitors.length * totalCompetitors),
      rawConnectivity: (uniqueCompetitors.length * totalCompetitors).toDouble(),
    );
  }

  @override
  double calculateConnectivityBaseline({
    int? matchCount, 
    int? competitorCount, 
    double? connectivitySum, 
    List<double>? connectivityScores,
  }) {
    connectivityScores!.sort();
    double median = 0.0;
    if(connectivityScores.length.isOdd) {
      median = connectivityScores[connectivityScores.length ~/ 2];
    } 
    else {
      median = (connectivityScores[connectivityScores.length ~/ 2] + connectivityScores[connectivityScores.length ~/ 2 - 1]) / 2;
    }

    // For immature rating sets, use the average instead of the median so we have some reference.
    if(median == 0) return connectivityScores.average * 0.75;
    else return median * 0.75;
  }

  @override
  double getScaleFactor({required double connectivity, required double baseline, double minScale = 0.8, double baselineScale = 1.0, double maxScale = 1.2}) {
    return lerpAroundCenter(
      value: connectivity,
      center: baseline,
      minOut: minScale,
      centerOut: baselineScale,
      maxOut: maxScale,
    );
  }

  @override
  int get matchWindowCount => 5;

  @override
  List<ConnectivityRequiredData> get requiredBaselineData => [
    ConnectivityRequiredData.connectivityScores,
  ];
  
  @override
  double calculateMatchConnectivity(List<double> connectivityScores) {
    return connectivityScores.average;
  }

  @override
  double get defaultBaselineConnectivity => 400.0;
}