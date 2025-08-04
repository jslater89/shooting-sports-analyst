import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/ui/elo_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/ui/marble_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/ui/openskill_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/ui/points_ratings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

class RatingSystemUiBuilder {
  static Row buildRatingKey(RatingSystem algorithm, BuildContext context, {DateTime? trendDate}) {
    if(algorithm is MultiplayerPercentEloRater) {
      return algorithm.buildRatingKey(context);
    }
    else if(algorithm is MarbleRater) {
      return algorithm.buildRatingKey(context);
    }
    else if(algorithm is OpenskillRater) {
      return algorithm.buildRatingKey(context);
    }
    else if(algorithm is PointsRater) {
      return algorithm.buildRatingKey(context);
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
    throw UnimplementedError("Rating system UI not implemented for ${algorithm.runtimeType}");
  }
}
