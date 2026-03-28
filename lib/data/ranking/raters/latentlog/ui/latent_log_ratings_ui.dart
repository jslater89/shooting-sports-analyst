/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_change.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart";
import "package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart";
import "package:shooting_sports_analyst/ui/colors.dart";
import "package:shooting_sports_analyst/ui/widget/maybe_tooltip.dart";
import "package:shooting_sports_analyst/ui/widget/score_row.dart";

extension LatentLogRatingsUi on LatentLogRater {
  static const _paddingFlex = 2;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _ratingFlex = 2;
  static const _lastChangeFlex = 2;
  static const _varianceFlex = 2;
  static const _dispersionFlex = 2;
  static const _momentumFlex = 2;
  static const _matchesFlex = 2;
  static const _stagesFlex = 2;

  Row buildRatingKey(BuildContext context, {DateTime? trendDate, RatingSortMode? sortMode}) {
    return Row(
      children: [
        Expanded(flex: _paddingFlex, child: Text("")),
        Expanded(flex: _placeFlex, child: Text("")),
        Expanded(flex: _memberNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Rating", textAlign: TextAlign.end)),
        Expanded(flex: _lastChangeFlex, child: Text("Last ±", textAlign: TextAlign.end)),
        Expanded(
          flex: _varianceFlex,
          child: Tooltip(
            message: "Approximate standard deviation of the rating..",
            child: Text("Uncertainty", textAlign: TextAlign.end),
          ),
        ),
        Expanded(
          flex: _dispersionFlex,
          child: Tooltip(
            message: "How much a competitor's rating tends to move from event to event.",
            child: Text("Dispersion", textAlign: TextAlign.end),
          ),
        ),
        Expanded(
          flex: _momentumFlex,
          child: Tooltip(
            message: "The directional tendency of the rating change over time.",
            child: Text("Momentum", textAlign: TextAlign.end),
          ),
        ),
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
    RatingSortMode? sortMode,
  }) {
    rating as LatentLogRating;
    final displayDelta = rating.lastMatchChange * settings.scaleFactor;
    final seenYearsAgo = (DateTime.now().difference(rating.lastSeen).inDays / 365);
    final String? ratingTooltip = seenYearsAgo > 1 ?
      "Last active ${seenYearsAgo.toStringAsFixed(1)} years ago." :
      null;

    final rowContents = Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
        children: [
          Expanded(flex: _paddingFlex, child: Text("")),
          Expanded(flex: _placeFlex, child: Text("$place")),
          Expanded(flex: _memberNumFlex, child: Text(rating.memberNumber)),
          Expanded(flex: _classFlex, child: Text(rating.lastClassification?.shortDisplayName ?? "none")),
          Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
          Expanded(
            flex: _ratingFlex,
            child: MaybeTooltip(
              message: ratingTooltip,
              child: Text(sortMode == RatingSortMode.agedRating ? rating.formattedAgedRating : rating.formattedRating, textAlign: TextAlign.end)),
            ),
          Expanded(flex: _lastChangeFlex, child: Text(displayDelta.round().toString(), textAlign: TextAlign.end)),
          Expanded(
            flex: _varianceFlex,
            child: MaybeTooltip(
              message: "Current: ${rating.displayCurrentStandardDeviation.toStringAsFixed(1)}",
              child:
                Text(
                  "${rating.displayStandardDeviation.toStringAsFixed(1)}",
                  textAlign: TextAlign.end,
                )
              )
            ),
          Expanded(
            flex: _dispersionFlex,
            child: Text(
              rating.displayDispersionStandardDeviation.toStringAsFixed(1),
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: _momentumFlex,
            child: Text(
              rating.displayMomentum.toStringAsFixed(1),
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(flex: _matchesFlex, child: Text(rating.lengthInMatches.toString(), textAlign: TextAlign.end)),
          Expanded(flex: _stagesFlex, child: Text(rating.lengthInStages.toString(), textAlign: TextAlign.end)),
          Expanded(flex: _paddingFlex, child: Text("")),
        ],
      ),
    );

    return ScoreRow(
      color: ThemeColors.backgroundColor(context, rowIndex: place - 1),
      child: rowContents,
      textColor: seenYearsAgo > 1 ? ThemeColors.fadedTextColor(context) : null,
    );
  }
}
