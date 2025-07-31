/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
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
  List<BaselineConnectivityRequiredData> get requiredBaselineData => [
    BaselineConnectivityRequiredData.connectivityScores,
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

  @override
  List<CompetitorConnectivityRequiredData> get requiredCompetitorData => [
    CompetitorConnectivityRequiredData.match,
    CompetitorConnectivityRequiredData.matchPointers,
    CompetitorConnectivityRequiredData.competitorRatings,
  ];

  @override
  bool updateCompetitorData({
    required DbShooterRating rating,
    ShootingMatch? match,
    Iterable<DbShooterRating>? competitors,
    int? competitorCount,
    List<MatchPointer>? matchPointers,
  }) {
    Set<int> ids = {};
    for(var c in competitors!) {
      if(c.id != rating.id) {
        ids.add(c.id);
      }
    }
    var window = MatchWindow.createFromHydratedMatch(
      match: match!,
      uniqueOpponentIds: ids.toList(),
      totalOpponents: ids.length,
    );

    MatchWindow? oldestWindow;
    // While we have more than 4 match windows, remove the oldest one
    // (so that the new one we add brings us to 5).
    var editableList = rating.matchWindows.toList();
    while(editableList.length > (matchWindowCount - 1)) {
      for(var window in editableList) {
        if(oldestWindow == null || window.date.isBefore(oldestWindow.date)) {
          oldestWindow = window;
        }
      }
      if(oldestWindow != null) {
        editableList.remove(oldestWindow);
        oldestWindow = null;
      }
    }
    editableList.add(window);
    rating.matchWindows = editableList;

    return true;
  }

  @override
  bool rollbackCompetitorData({
    required DbShooterRating rating,
    List<ShootingMatch>? matchesRemoved,
    Iterable<Iterable<DbShooterRating>>? competitorsRemoved,
    Iterable<int>? competitorCountsRemoved,
    List<MatchPointer>? matchPointers,
  }) {
    for(var match in matchesRemoved!) {
      rating.matchWindows.remove(match);
    }

    // TODO: this is an incomplete implementation
    // Getting it actually correct may be extremely hard, though, as we'll need
    // to rebuild connectivity data for old matches to get up to the correct window.
    return true;
  }


  @override
  bool get useHistoryForRollback => true;
}
