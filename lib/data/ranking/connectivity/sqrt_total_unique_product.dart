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
    if(connectivityScores!.isEmpty) return defaultBaselineConnectivity;
    connectivityScores.sort();
    double median = 0.0;
    if(connectivityScores.length.isOdd) {
      median = connectivityScores[connectivityScores.length ~/ 2];
    } 
    else {
      median = (connectivityScores[connectivityScores.length ~/ 2] + connectivityScores[connectivityScores.length ~/ 2 - 1]) / 2;
    }

    // Calculate the 75th percentile
    double percentile75 = connectivityScores[connectivityScores.length * 3 ~/ 4];

    // For immature rating sets, use the raw 75th percentile, or the average of nonzero scores if the 75th percentile is 0.
    if(percentile75 == 0) {
      var nonzeroScores = connectivityScores.where((score) => score != 0);
      if(nonzeroScores.isEmpty) return defaultBaselineConnectivity;
      return nonzeroScores.average;
    }
    else if(median == 0) return percentile75;
    else return median * 0.6 + percentile75 * 0.4;
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
  int get baselineMatchWindowCount => 100;

  @override
  List<ConnectivityRequiredData> get requiredBaselineData => [
    ConnectivityRequiredData.connectivityScores,
  ];
  
  @override
  double calculateMatchConnectivity(List<double> connectivityScores) {
    if(connectivityScores.isEmpty) return 0;
    var median = connectivityScores[connectivityScores.length ~/ 2];
    var max = connectivityScores.last;
    return median * 0.7 + max * 0.3;
  }

  @override
  double get defaultBaselineConnectivity => 400.0;
}