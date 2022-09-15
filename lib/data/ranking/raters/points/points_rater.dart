import 'package:flutter/src/widgets/basic.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
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
import 'package:uspsa_result_viewer/ui/score_row.dart';

class PointsRater extends RatingSystem<PointsRating, PointsSettings, PointsSettingsController> {
  PointsRater(this.settings);

  factory PointsRater.fromJson(Map<String, dynamic> json) {
    var settings = PointsSettings();
    settings.loadFromJson(json);

    return PointsRater(settings);
  }

  @override
  Row buildRatingKey(BuildContext context) {
    // TODO: implement buildRatingKey
    throw UnimplementedError();
  }

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating}) {
    // TODO: implement buildRatingRow
    throw UnimplementedError();
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
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  RatingEvent newEvent({
    required PracticalMatch match,
    Stage? stage,
    required ShooterRating rating,
    required RelativeScore score,
    List<String> info = const []
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
    return PointsRating(shooter, date: date);
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    // TODO: implement ratingsToCsv
    throw UnimplementedError();
  }

  @override
  PointsSettings settings;

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
    switch(settings.mode) {
      case PointsMode.f1:
        changes = applyF1Points(scores, settings);
        break;
      case PointsMode.inversePlace:
        changes = applyInversePlace(scores, settings);
        break;
      case PointsMode.percentageFinish:
        changes = applyPercentFinish(scores, settings);
        break;
      case PointsMode.decayingPoints:
        changes = applyDecayingPoints(scores, settings);
        break;
    }

    return changes;
  }
}