import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

extension PointsRatingsUi on PointsRater {
  static const _leadPaddingFlex = 4;
  static const _placeFlex = 1;
  static const _memNumFlex = 2;
  static const _classFlex = 1;
  static const _nameFlex = 3;
  static const _ratingFlex = 2;
  static const _stagesFlex = 2;
  static const _ppmFlex = 2;
  static const _trailPaddingFlex = 4;

  Row buildRatingKey(BuildContext context, {DateTime? trendDate}) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(flex: _leadPaddingFlex + _placeFlex, child: Text("")),
        Expanded(flex: _memNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Points", textAlign: TextAlign.end)),
        Expanded(
          flex: _stagesFlex,
          child: Tooltip(
            message: "At most ${settings.matchesToCount} matches will count for points.",
            child: Text("Matches/${settings.matchesToCount}", textAlign: TextAlign.end),
          ),
        ),
        Expanded(flex: _ppmFlex, child: Text("Points/Match", textAlign: TextAlign.end)),
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
    rating as PointsRating;

    var ratingText = "";
    if(settings.mode == PointsMode.inversePlace || settings.mode == PointsMode.f1) {
      ratingText = rating.rating.round().toString();
    }
    else {
      ratingText = rating.rating.toStringAsFixed(1);
    }

    var ppmText = (rating.rating / rating.length.clamp(1, settings.matchesToCount)).toStringAsFixed(1);

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _leadPaddingFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memNumFlex, child: Text(rating.memberNumber)),
            Expanded(flex: _classFlex, child: Text(rating.lastClassification?.shortDisplayName ?? "(none)")),
            Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
            Expanded(flex: _ratingFlex, child: Text("$ratingText", textAlign: TextAlign.end)),
            Expanded(flex: _stagesFlex, child: Text("${rating.length}", textAlign: TextAlign.end)),
            Expanded(flex: _ppmFlex, child: Text("$ppmText", textAlign: TextAlign.end)),
            Expanded(flex: _trailPaddingFlex, child: Text("")),
          ]
        )
      )
    );
  }
}
