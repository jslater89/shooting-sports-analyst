/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

extension MarbleRatingsUi on MarbleRater {
  static const _paddingFlex = 6;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _marblesFlex = 2;
  static const _lastChangeFlex = 2;
  static const _trendFlex = 2;
  static const _matchesFlex = 2;

  Row buildRatingKey(BuildContext context, {DateTime? trendDate}) {
    String trendTooltip = "Change over the last 3 matches";
    if(byStage) {
      trendTooltip = "Change over the last 30 stages";
    }
    return Row(
      children: [
        Expanded(flex: _paddingFlex, child: Text("")),
        Expanded(flex: _placeFlex, child: Text("")),
        Expanded(flex: _memberNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _marblesFlex, child: Text("Marbles", textAlign: TextAlign.end)),
        Expanded(
          flex: _lastChangeFlex,
          child: Tooltip(
            message: "Last ±",
            child: Text("Last ±", textAlign: TextAlign.end)
          )
        ),
        Expanded(
          flex: _trendFlex,
          child: Tooltip(
            message: trendDate != null ? "Change in rating since ${DateFormat.yMd().format(trendDate)}" : trendTooltip,
            child: Text("Trend", textAlign: TextAlign.end)
          )
        ),
        Expanded(flex: _matchesFlex, child: Text("Matches", textAlign: TextAlign.end)),
        Expanded(flex: _paddingFlex, child: Text("")),
      ],
    );
  }

  ScoreRow buildRatingRow({
    required BuildContext context,
    required int place,
    required ShooterRating<RatingEvent> rating,
    DateTime? trendDate,
    RatingScaler? scaler,
  }) {
    rating as MarbleRating;
    var lastChange = rating.lastMatchChange;
    int trend = 0;
    if(trendDate != null) {
      var forDate = rating.ratingForDate(trendDate);
      trend = (rating.rating - forDate).round();
    }
    else {
      if(byStage) {
        trend = rating.trend.round();
      }
      else {
        trend = rating.trend3.round();
      }
    }

    return ScoreRow(
      color: ThemeColors.backgroundColor(context, rowIndex: place - 1),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _paddingFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memberNumFlex, child: Text(rating.memberNumber)),
            Expanded(flex: _classFlex, child: Text(rating.lastClassification?.shortDisplayName ?? "none")),
            Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
            Expanded(flex: _marblesFlex, child: Text(rating.marbles.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _lastChangeFlex, child: Text(lastChange.round().toString(), textAlign: TextAlign.end)),
            Expanded(flex: _trendFlex, child: Text(trend.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _matchesFlex, child: Text(rating.length.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _paddingFlex, child: Text("")),
          ],
        )
      )
    );
  }

}
