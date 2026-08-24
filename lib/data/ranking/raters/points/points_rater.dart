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
import 'package:shooting_sports_analyst/data/ranking/rating_system_ui_data.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
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
  RatingChange noOpChangeFor({
    required PointsRating shooter,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    required NonRatingResultReason reason,
  }) {
    return RatingChange(
      change: {
        RatingSystem.ratingChangeKey: 0.0,
      },
      infoLines: [
        "No rating change ({{resultReason}})",
      ],
      infoData: [
        RatingEventInfoElement.string(name: "resultReason", stringValue: reason.name.toUpperCase()),
      ],
      nonRatingResultReason: reason,
    );
  }

  @override
  PointsRating wrapDbRating(DbShooterRating rating) {
    return PointsRating.wrapDbRating(rating);
  }

  static const _leadPaddingFlex = 4;
  static const _placeFlex = 1;
  static const _memNumFlex = 2;
  static const _ratingTableClassFlex = 1;
  static const _nameFlex = 3;
  static const _ratingFlex = 2;
  static const _ratingTableStagesFlex = 2;
  static const _ppmFlex = 2;
  static const _trailPaddingFlex = 4;

  @override
  List<RatingRowData> buildRatingKeyData({DateTime? trendDate, RatingSortMode? sortMode}) {
    return [
      RatingRowData(data: "", flex: _leadPaddingFlex + _placeFlex),
      RatingRowData(data: "Member #", flex: _memNumFlex),
      RatingRowData(data: "Class", flex: _ratingTableClassFlex),
      RatingRowData(data: "Name", flex: _nameFlex),
      RatingRowData(data: "Points", alignment: AbstractAlignment.end, flex: _ratingFlex),
      RatingRowData(
        data: "Matches/${settings.matchesToCount}",
        tooltip: "At most ${settings.matchesToCount} matches will count for points.",
        alignment: AbstractAlignment.end,
        flex: _ratingTableStagesFlex,
      ),
      RatingRowData(data: "Points/Match", alignment: AbstractAlignment.end, flex: _ppmFlex),
      RatingRowData(data: "", flex: _trailPaddingFlex),
    ];
  }

  @override
  List<RatingRowData> buildRatingRowData({
    required ShooterRating rating,
    required int place,
    DateTime? trendDate,
    RatingScaler? scaler,
    RatingSortMode? sortMode,
  }) {
    rating as PointsRating;
    final ratingText = settings.mode == PointsMode.inversePlace || settings.mode == PointsMode.f1 ?
      rating.rating.round().toString() :
      rating.rating.toStringAsFixed(1);
    final ppmText = (rating.rating / rating.length.clamp(1, settings.matchesToCount)).toStringAsFixed(1);
    return [
      RatingRowData(data: "", flex: _leadPaddingFlex),
      RatingRowData(data: "$place", flex: _placeFlex),
      RatingRowData(data: rating.memberNumber, flex: _memNumFlex),
      RatingRowData(data: rating.lastClassification?.shortDisplayName ?? "(none)", flex: _ratingTableClassFlex),
      RatingRowData(data: rating.getName(suffixes: false), flex: _nameFlex),
      RatingRowData(data: ratingText, alignment: AbstractAlignment.end, flex: _ratingFlex),
      RatingRowData(data: "${rating.length}", alignment: AbstractAlignment.end, flex: _ratingTableStagesFlex),
      RatingRowData(data: ppmText, alignment: AbstractAlignment.end, flex: _ppmFlex),
      RatingRowData(data: "", flex: _trailPaddingFlex),
    ];
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
