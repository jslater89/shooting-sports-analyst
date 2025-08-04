/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/decaying_points.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/f1_points.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/inverse_place.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/percent_finish.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';

class PointsRater extends RatingSystem<PointsRating, PointsSettings> {
  PointsRater(this.settings) : model = PointsModel.fromSettings(settings);

  final PointsModel model;

  factory PointsRater.fromJson(Map<String, dynamic> json) {
    var settings = PointsSettings();
    settings.loadFromJson(json);

    return PointsRater(settings);
  }

  @override
  bool get byStage => settings.byStage;

  @override
  PointsRating copyShooterRating(PointsRating rating) {
    return PointsRating.copy(rating);
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[DbRatingProject.algorithmKey] = DbRatingProject.pointsValue;
    settings.encodeToJson(json);
  }

  @override
  int histogramBucketSize({required int shooterCount, required int matchCount, required double minRating, required double maxRating}) {
    // About 10% of the maximum points available
    switch(settings.mode) {
      case PointsMode.f1:
        return (0.1 * 25 * matchCount).round();
      case PointsMode.inversePlace:
        return (0.1 * 0.2 * shooterCount * matchCount).round();
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
    required ShootingMatch match,
    MatchStage? stage,
    required ShooterRating rating,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  }) {
    return PointsRatingEvent(
      oldRating: rating.rating,

      ratingChange: 0,
      match: match,
      score: score,
      matchScore: matchScore,
      infoLines: infoLines,
      infoData: infoData,
    );
  }

  @override
  PointsRating newShooterRating(MatchEntry shooter, {required DateTime date, required Sport sport}) {
    return PointsRating(
      shooter,
      sport: sport,
      date: date,
      participationBonus: model.participationBonus,
      matchesToCount: settings.matchesToCount,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    var contents = "Name,Member #,Class,Points,Matches,Points/Match\n";

    for(var s in ratings) {
      s as PointsRating;
      contents += "${s.getName(suffixes: false)},";
      contents += "${s.originalMemberNumber},";
      contents += "${s.lastClassification?.displayName ?? "(none)"},";
      contents += "${model.displayRating(s.rating)},";
      contents += "${s.length},";
      contents += "${(s.rating / s.length).toStringAsFixed(1)},";
      contents += "\n";
    }

    return contents;
  }

  @override
  List<JsonShooterRating> ratingsToJson(List<ShooterRating> ratings) {
    return ratings.map((e) => JsonShooterRating.fromShooterRating(e)).toList();
  }

  @override
  PointsSettings settings;

  List<RatingSortMode> get supportedSorts => [
    RatingSortMode.rating,
    RatingSortMode.pointsPerMatch,
    RatingSortMode.classification,
    RatingSortMode.firstName,
    RatingSortMode.lastName,
    RatingSortMode.stages,
  ];

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({
    required ShootingMatch match,
    bool isMatchOngoing = false,
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  }) {
    late Map<ShooterRating, RatingChange> changes;
    changes = model.apply(scores);

    return changes;
  }

  @override
  PointsRating wrapDbRating(DbShooterRating rating) {
    return PointsRating.wrapDbRating(rating);
  }
}

abstract class PointsModel {
  final PointsSettings settings;
  PointsModel(this.settings);

  Map<ShooterRating, RatingChange> apply(Map<ShooterRating, RelativeScore> scores);
  double get participationBonus => settings.participationBonus;

  String displayRating(double rating);

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
