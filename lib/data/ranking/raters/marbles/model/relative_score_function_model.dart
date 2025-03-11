/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/marble_model.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

abstract class RelativeScoreFunctionModel implements MarbleModel {
  const RelativeScoreFunctionModel();

  double shareForRelativeScore(double relativeScore);

  @override
  Map<ShooterRating, RatingChange> distributeMarbles({
    required Map<ShooterRating, RatingChange> changes,
    required Map<ShooterRating, RelativeScore> results,
    required Map<ShooterRating, int> stakes,
    required int totalStake,
  }) {
    var maxPerformance = results.values.map((e) => e.percentage).max;
    var sumShares = 0.0;
    var shares = <ShooterRating, double>{};

    for(var s in results.keys) {
      var relativeScore = results[s]!.percentage;
      var share = shareForRelativeScore(relativeScore / maxPerformance);
      shares[s] = share;
      sumShares += share;
    }
    
    for(var s in results.keys) {
      var score = results[s]!;
      var relativeShare = shares[s]! / sumShares;
      var marblesWon = (totalStake * relativeShare).round();
      changes[s]!.change[MarbleRater.marblesWonKey] = marblesWon.toDouble();
      changes[s]!.change[MarbleRater.matchStakeKey] = totalStake.toDouble();
      changes[s]!.infoLines = [
        "Marbles staked/won/net: {{staked}}/{{won}}/{{net}} at {{matchPercent}}%",
        "Total match stake: {{matchStake}} from {{competitors}} competitors",
        "Match stake percentage: {{matchStakePercent}}%",
      ];
      changes[s]!.infoData = [
        RatingEventInfoElement.int(name: "staked", intValue: stakes[s]!),
        RatingEventInfoElement.int(name: "won", intValue: marblesWon),
        RatingEventInfoElement.int(name: "net", intValue: marblesWon - stakes[s]!),
        RatingEventInfoElement.int(name: "competitors", intValue: results.length),
        RatingEventInfoElement.int(name: "matchStake", intValue: totalStake),
        RatingEventInfoElement.double(name: "matchStakePercent", doubleValue: relativeShare * 100, numberFormat: "%00.2f"),
        RatingEventInfoElement.double(name: "matchPercent", doubleValue: score.percentage, numberFormat: "%00.2f"),
      ];
    }

    return changes;
  }
}