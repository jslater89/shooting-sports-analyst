/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

extension EloRatingsUi on MultiplayerPercentEloRater {
  static const _leadPaddingFlex = 2;
  static const _placeFlex = 1;
  static const _memNumFlex = 2;
  static const _classFlex = 1;
  static const _nameFlex = 5;
  static const _ratingFlex = 2;
  static const _matchChangeFlex = 2;
  // ignore: unused_field
  static const _uncertaintyFlex = 2;
  static const _errorFlex = 2;
  static const _connectednessFlex = 2;
  static const _trendFlex = 2;
  static const _directionFlex = 2;
  static const _stagesFlex = 2;
  static const _trailPaddingFlex = 2;

  Row buildRatingKey(BuildContext context, {DateTime? trendDate}) {
    var errorText = "The error calculated by the rating system.";
    if(MultiplayerPercentEloRater.doBackRating) {
      errorText += " A negative number means the calculated rating\n"
          "was too low. A positive number means the calculated rating was too high.";
    }
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(flex: _leadPaddingFlex + _placeFlex, child: Text("")),
        Expanded(flex: _memNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Rating", textAlign: TextAlign.end)),
        Expanded(
            flex: _errorFlex,
            child: Tooltip(
                message: errorText,
                child: Text("Error", textAlign: TextAlign.end)
            )
        ),
        Expanded(
            flex: _matchChangeFlex,
            child: Tooltip(
                message:
                "The change in the shooter's rating at the last match.",
                child: Text("Last ±", textAlign: TextAlign.end)
            )
        ),
        Expanded(
          flex: _trendFlex,
          child: Tooltip(
            message: trendDate != null ? "The change in the shooter's rating since ${DateFormat.yMd().format(trendDate)}." : "The change in the shooter's rating over the last 30 rating events.",
            child: Text("Trend", textAlign: TextAlign.end)
          )
        ),
        Expanded(
            flex: _directionFlex,
            child: Tooltip(
                message: "The shooter's rating trajectory: 100 if all of the last 30 rating events were positive, -100 if all were negative.",
                child: Text("Direction", textAlign: TextAlign.end)
            )
        ),
        Expanded(
          flex: _connectednessFlex,
          child: Tooltip(
            message: "The shooter's connectedness, a measure of how much he shoots against other shooters in the set.",
            child: Text("Conn.", textAlign: TextAlign.end)
          )
        ),
        Expanded(flex: _stagesFlex, child: Text(byStage ? "Stages" : "Matches", textAlign: TextAlign.end)),
        Expanded(flex: _trailPaddingFlex, child: Text("")),
      ],
    );
  }

  ScoreRow buildRatingRow({
    required BuildContext context,
    required int place,
    required ShooterRating rating,
    DateTime? trendDate,
    RatingScaler? scaler,
  }) {
    rating as EloShooterRating;

    var trend = rating.trend.round();
    if(trendDate != null) {
      var forDate = rating.ratingForDate(trendDate);
      trend = (rating.rating - forDate).round();
      // _log.vv("rating: ${rating.rating}, date: $trendDate, forDate: $forDate, trend: $trend");
    }
    var positivity = (rating.direction * 100).round();
    var error = rating.standardError; //rating.decayingAverageRatingChangeError;
    if(MultiplayerPercentEloRater.doBackRating) {
      error = rating.backRatingError;
    }
    var lastMatchChange = rating.lastMatchChange;

    var ratingNumber = rating.rating.round();
    if(scaler != null) {
      ratingNumber = scaler.scaleRating(rating.rating, group: rating.group).round();
      error = scaler.scaleNumber(error, originalRating: rating.rating, group: rating.group);
      lastMatchChange = scaler.scaleNumber(lastMatchChange, originalRating: rating.rating);
      trend = scaler.scaleNumber(rating.trend, originalRating: rating.rating).round();
    }

    return ScoreRow(
      color: ThemeColors.backgroundColor(context, rowIndex: place - 1),
      child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            children: [
              Expanded(flex: _leadPaddingFlex, child: Text("")),
              Expanded(flex: _placeFlex, child: Text("$place")),
              Expanded(flex: _memNumFlex, child: Text(rating.memberNumber)),
              Expanded(flex: _classFlex, child: Text(rating.lastClassification?.shortDisplayName ?? "?")),
              Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
              Expanded(flex: _ratingFlex, child: Text("$ratingNumber", textAlign: TextAlign.end)),
              Expanded(flex: _errorFlex, child: Text("${error.toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _matchChangeFlex, child: Text("${lastMatchChange.round()}", textAlign: TextAlign.end)),
              Expanded(flex: _trendFlex, child: Text("$trend", textAlign: TextAlign.end)),
              Expanded(flex: _directionFlex, child: Text("$positivity", textAlign: TextAlign.end)),
              Expanded(flex: _connectednessFlex, child: Text("${(rating.connectivity).toStringAsFixed(1)}", textAlign: TextAlign.end)),
              Expanded(flex: _stagesFlex, child: Text("${rating.length}", textAlign: TextAlign.end,)),
              Expanded(flex: _trailPaddingFlex, child: Text("")),
            ],
          )
      ),
    );
  }

}
