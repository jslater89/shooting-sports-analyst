/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/decaying_points.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/f1_points.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/inverse_place.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/models/percent_finish.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/ui/points_settings_ui.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

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
  static const _ppmFlex = 2;
  static const _trailPaddingFlex = 4;

  @override
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

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating, DateTime? trendDate}) {
    rating as PointsRating;

    var ratingText = "";
    if(settings.mode == PointsMode.inversePlace || settings.mode == PointsMode.f1) {
      ratingText = rating.rating.round().toString();
    }
    else {
      ratingText = rating.rating.toStringAsFixed(1);
    }

    var ppmText = (rating.rating / min(rating.length, settings.matchesToCount)).toStringAsFixed(1);

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _leadPaddingFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memNumFlex, child: Text(rating.originalMemberNumber)),
            Expanded(flex: _classFlex, child: Text(rating.lastClassification?.displayName ?? "(none)")),
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

  @override
  bool get byStage => settings.byStage;

  @override
  PointsRating copyShooterRating(PointsRating rating) {
    return PointsRating.copy(rating);
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[OldRatingProject.algorithmKey] = OldRatingProject.pointsValue;
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
  PointsSettingsController newSettingsController() {
    return PointsSettingsController();
  }

  @override
  PointsSettingsWidget newSettingsWidget(PointsSettingsController controller) {
    return PointsSettingsWidget(controller: controller);
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