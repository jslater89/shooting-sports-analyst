import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/basic.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/models/decaying_points.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/models/f1_points.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/models/inverse_place.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/models/percent_finish.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/ui/points_settings_ui.dart';
import 'package:uspsa_result_viewer/ui/rater/rater_view.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';

class PointsRater extends RatingSystem<PointsRating, PointsSettings, PointsSettingsController> {
  PointsRater(this.settings) : model = PointsModel.fromSettings(settings);

  final PointsModel model;

  factory PointsRater.fromJson(Map<String, dynamic> json) {
    var settings = PointsSettings();
    settings.loadFromJson(json);

    return PointsRater(settings);
  }

  static const _leadPaddingFlex = 4;
  static const _placeFlex = 1;
  static const _memNumFlex = 2;
  static const _classFlex = 1;
  static const _nameFlex = 3;
  static const _ratingFlex = 2;
  static const _stagesFlex = 2;
  static const _trailPaddingFlex = 4;

  @override
  Row buildRatingKey(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(flex: _leadPaddingFlex + _placeFlex, child: Text("")),
        Expanded(flex: _memNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _ratingFlex, child: Text("Points", textAlign: TextAlign.end)),
        Expanded(flex: _stagesFlex, child: Text("Matches", textAlign: TextAlign.end)),
        Expanded(flex: _trailPaddingFlex, child: Text("")),
      ],
    );
  }

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating}) {
    rating as PointsRating;

    var ratingText = "";
    if(settings.mode == PointsMode.inversePlace) {
      ratingText = rating.rating.round().toString();
    }
    else {
      ratingText = rating.rating.toStringAsFixed(1);
    }

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _leadPaddingFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memNumFlex, child: Text(rating.shooter.memberNumber)),
            Expanded(flex: _classFlex, child: Text(rating.lastClassification.displayString())),
            Expanded(flex: _nameFlex, child: Text(rating.shooter.getName(suffixes: false))),
            Expanded(flex: _ratingFlex, child: Text("$ratingText", textAlign: TextAlign.end)),
            Expanded(flex: _stagesFlex, child: Text("${rating.length}", textAlign: TextAlign.end,)),
            Expanded(flex: _trailPaddingFlex, child: Text("")),
          ]
        )
      )
    );
  }

  @override
  bool get byStage => settings.byStage;

  @override
  PointsRating copyShooterRating(PointsRating rating) {
    return PointsRating.copy(rating);
  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    json[RatingProject.algorithmKey] = RatingProject.pointsValue;
    settings.encodeToJson(json);
  }

  @override
  int histogramBucketSize(int shooters, int matchCount) {
    // About 10% of the maximum points available
    switch(settings.mode) {
      case PointsMode.f1:
        return (0.1 * 25 * matchCount).round();
      case PointsMode.inversePlace:
        return (0.1 * 0.2 * shooters * matchCount).round();
      case PointsMode.percentageFinish:
        return (0.1 * 100 * matchCount).round();
      case PointsMode.decayingPoints:
        return (0.1 * settings.decayingPointsStart * matchCount).round();
    }
  }

  @override
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  String nameForSort(RatingSortMode mode) {
    if(mode == RatingSortMode.rating) return "Points";
    return super.nameForSort(mode);
  }

  @override
  RatingEvent newEvent({
    required PracticalMatch match,
    Stage? stage,
    required ShooterRating rating,
    required RelativeScore score,
    Map<String, List<dynamic>> info = const {}
  }) {
    return PointsRatingEvent(oldRating: rating.rating, ratingChange: 0, match: match, score: score, info: info);
  }

  @override
  PointsSettingsController newSettingsController() {
    return PointsSettingsController();
  }

  @override
  PointsSettingsWidget newSettingsWidget(PointsSettingsController controller) {
    return PointsSettingsWidget(controller: controller);
  }

  @override
  PointsRating newShooterRating(Shooter shooter, {DateTime? date}) {
    return PointsRating(shooter, settings, date: date, participationBonus: model.participationBonus);
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    // TODO: implement ratingsToCsv
    throw UnimplementedError();
  }

  @override
  PointsSettings settings;

  List<RatingSortMode> get supportedSorts => [
    RatingSortMode.rating,
    RatingSortMode.classification,
    RatingSortMode.firstName,
    RatingSortMode.lastName,
    RatingSortMode.stages,
  ];

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  }) {
    late Map<ShooterRating, RatingChange> changes;
    changes = model.apply(scores);

    return changes;
  }
}

abstract class PointsModel {
  final PointsSettings settings;
  PointsModel(this.settings);

  Map<ShooterRating, RatingChange> apply(Map<ShooterRating, RelativeScore> scores);
  double get participationBonus => settings.participationBonus;

  static PointsModel fromSettings(PointsSettings settings) {
    switch(settings.mode) {
      case PointsMode.f1:
        return F1Points(settings);
      case PointsMode.inversePlace:
        return InversePlace(settings);
      case PointsMode.percentageFinish:
        return PercentFinish(settings);
      case PointsMode.decayingPoints:
        return DecayingPoints(settings);
    }
  }
}