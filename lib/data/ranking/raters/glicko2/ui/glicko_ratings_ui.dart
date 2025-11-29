/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

extension Glicko2RatingsUi on Glicko2Rater {
  static const _paddingFlex = 4;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _ratingFlex = 2;
  static const _rdFlex = 2;
  static const _volatilityFlex = 2;
  static const _matchesFlex = 2;
  static const _stagesFlex = 2;


  Row buildRatingKey(BuildContext context, {DateTime? trendDate}) {
    return Row(
      children: [
        Expanded(flex: _paddingFlex, child: Text("")),
        Expanded(flex: _placeFlex, child: Text("")),
        Expanded(flex: _memberNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Rating", textAlign: TextAlign.end)),
        Expanded(flex: _rdFlex, child: Text("RD", textAlign: TextAlign.end)),
        Expanded(flex: _volatilityFlex, child: Text("Volatility", textAlign: TextAlign.end)),
        Expanded(flex: _matchesFlex, child: Text("Matches", textAlign: TextAlign.end)),
        Expanded(flex: _stagesFlex, child: Text("Stages", textAlign: TextAlign.end)),
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
    rating as Glicko2Rating;
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
            Expanded(flex: _ratingFlex, child: Text(settings.scaleToDisplay(rating.rating, offset: settings.initialRating).round().toString(), textAlign: TextAlign.end)),
            Expanded(flex: _rdFlex, child: Text(settings.scaleToDisplay(rating.currentRD).round().toString(), textAlign: TextAlign.end)),
            Expanded(flex: _volatilityFlex, child: Text(rating.volatility.toStringAsFixed(4), textAlign: TextAlign.end)),
            Expanded(flex: _matchesFlex, child: Text(rating.lengthInMatches.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _stagesFlex, child: Text(rating.lengthInStages.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _paddingFlex, child: Text("")),
          ],
        ),
      ),
    );
  }
}