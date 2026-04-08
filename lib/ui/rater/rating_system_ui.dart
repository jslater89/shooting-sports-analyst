/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_system_ui_data.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/widget/maybe_tooltip.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

/// Builds the rating key and row from a given rating system, building widgets
/// from the UI-agnostic [RatingRowData] objects.
class RatingSystemUiBuilder {
  static Row buildRatingKey(RatingSystem algorithm, BuildContext context, {DateTime? trendDate, RatingSortMode? sortMode}) {
    var data = algorithm.buildRatingKeyData(trendDate: trendDate, sortMode: sortMode);
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: data.map((e) => Expanded(
        flex: e.flex,
        child: MaybeTooltip(
          message: e.tooltip,
          child: Text(
            e.data,
            textAlign: e.alignment.toTextAlign(),
            style: _fadeTextStyle(context, e.fadeText),
          ),
        ),
      )).toList()
    );
  }

  static ScoreRow buildRatingRow(RatingSystem algorithm, {required BuildContext context, required int place, required ShooterRating rating, DateTime? trendDate, RatingScaler? scaler, RatingSortMode? sortMode}) {
    var data = algorithm.buildRatingRowData(rating: rating, place: place, trendDate: trendDate, scaler: scaler, sortMode: sortMode);
    return ScoreRow(
      color: ThemeColors.backgroundColor(context, rowIndex: place - 1),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: data.map((e) => Expanded(
            flex: e.flex,
            child: MaybeTooltip(
              message: e.tooltip,
              child: Text(
              e.data,
              textAlign: e.alignment.toTextAlign(),
              style: _fadeTextStyle(context, e.fadeText),
            ),
            ),
          )).toList()
        ),
      )
    );
  }

  static TextStyle? _fadeTextStyle(BuildContext context, bool fadeText) {
    if(!fadeText) {
      return null;
    }
    return TextStyle(color: ThemeColors.fadedTextColor(context));
  }
}

extension TextAlignExtension on AbstractAlignment {
  TextAlign toTextAlign() {
    switch(this) {
      case AbstractAlignment.start:
        return TextAlign.start;
      case AbstractAlignment.center:
        return TextAlign.center;
      case AbstractAlignment.end:
        return TextAlign.end;
    }
  }
}