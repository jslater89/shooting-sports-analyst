/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

extension OpenskillRatingsUi on OpenskillRater {
  static const _paddingFlex = 6;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _ordinalFlex = 2;
  static const _muFlex = 2;
  static const _sigmaFlex = 2;
  static const _eventsFlex = 2;

  Row buildRatingKey(BuildContext context, {DateTime? trendDate}) {
    return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(flex: _paddingFlex - _placeFlex, child: Text("")),
          Expanded(flex: _placeFlex, child: Text("")),
          Expanded(flex: _memberNumFlex, child: Text("Member #")),
          Expanded(flex: _classFlex, child: Text("Class")),
          Expanded(flex: _nameFlex, child: Text("Name")),
          Expanded(flex: _ordinalFlex, child: Text("Rating", textAlign: TextAlign.end)),
          Expanded(flex: _muFlex, child: Text("Mu", textAlign: TextAlign.end)),
          Expanded(flex: _sigmaFlex, child: Text("Sigma", textAlign: TextAlign.end)),
          Expanded(flex: _eventsFlex, child: Text(byStage ? "Stages" : "Matches", textAlign: TextAlign.end)),
          Expanded(flex: _paddingFlex, child: Text("")),
        ]
    );
  }

  ScoreRow buildRatingRow({
    required BuildContext context,
    required int place,
    required ShooterRating rating,
    DateTime? trendDate,
    RatingScaler? scaler,
  }) {
    // double trend;
    // if(trendDate != null) {
    //   trend = rating.rating - rating.ratingForDate(trendDate);
    // }
    // else {
    //   trend = rating.rating - rating.averageRating().firstRating;
    // }

    rating as OpenskillRating;

    return ScoreRow(
      color: ThemeColors.backgroundColor(context, rowIndex: place - 1),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _paddingFlex - _placeFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memberNumFlex, child: Text(rating.memberNumber)),
            Expanded(flex: _classFlex, child: Text(rating.lastClassification?.shortDisplayName ?? "none")),
            Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
            Expanded(flex: _ordinalFlex, child: Text(rating.ordinal.toStringAsFixed(1), textAlign: TextAlign.end)),
            Expanded(flex: _muFlex, child: Text(rating.mu.toStringAsFixed(1), textAlign: TextAlign.end)),
            Expanded(flex: _sigmaFlex, child: Text(rating.sigma.toStringAsFixed(2), textAlign: TextAlign.end)),
            Expanded(flex: _eventsFlex, child: Text("${rating.length}", textAlign: TextAlign.end,)),
            Expanded(flex: _paddingFlex, child: Text("")),
          ]
        )
      )
    );
  }
}
