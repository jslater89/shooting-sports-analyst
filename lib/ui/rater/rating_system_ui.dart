/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/ui/elo_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/ui/glicko2_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/ui/marble_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/ui/openskill_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/ui/points_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

// This file is kind of ugly, but it's a necessary evil to keep UI imports out of the core rating engine
// code. Every rating system has an extension on it that fits the buildRatingKey/buildRatingRow interface,
// but I don't think I have a way to fully augment the class to implement an interface yet.
class RatingSystemUiBuilder {
  static Row buildRatingKey(RatingSystem algorithm, BuildContext context, {DateTime? trendDate}) {
    if(algorithm is MultiplayerPercentEloRater) {
      return algorithm.buildRatingKey(context, trendDate: trendDate);
    }
    else if(algorithm is MarbleRater) {
      return algorithm.buildRatingKey(context, trendDate: trendDate);
    }
    else if(algorithm is OpenskillRater) {
      return algorithm.buildRatingKey(context, trendDate: trendDate);
    }
    else if(algorithm is PointsRater) {
      return algorithm.buildRatingKey(context, trendDate: trendDate);
    }
    else if(algorithm is Glicko2Rater) {
      return algorithm.buildRatingKey(context, trendDate: trendDate);
    }
    throw UnimplementedError("Rating system UI not implemented for ${algorithm.runtimeType}");
  }

  static ScoreRow buildRatingRow(RatingSystem algorithm, {required BuildContext context, required int place, required ShooterRating rating, DateTime? trendDate, RatingScaler? scaler}) {
    if(algorithm is MultiplayerPercentEloRater) {
      return algorithm.buildRatingRow(context: context, place: place, rating: rating, trendDate: trendDate, scaler: scaler);
    }
    else if(algorithm is MarbleRater) {
      return algorithm.buildRatingRow(context: context, place: place, rating: rating, trendDate: trendDate, scaler: scaler);
    }
    else if(algorithm is OpenskillRater) {
      return algorithm.buildRatingRow(context: context, place: place, rating: rating, trendDate: trendDate, scaler: scaler);
    }
    else if(algorithm is PointsRater) {
      return algorithm.buildRatingRow(context: context, place: place, rating: rating, trendDate: trendDate, scaler: scaler);
    }
    else if(algorithm is Glicko2Rater) {
      return algorithm.buildRatingRow(context: context, place: place, rating: rating, trendDate: trendDate, scaler: scaler);
    }
    throw UnimplementedError("Rating system UI not implemented for ${algorithm.runtimeType}");
  }
}
