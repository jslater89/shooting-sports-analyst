/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/basic.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/ui/marble_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

class MarbleRater extends RatingSystem<MarbleRating, MarbleSettings, MarbleSettingsController> {
  MarbleRater({required this.settings});

  MarbleSettings settings;

  static const marblesStakedKey = "staked";
  static const marblesWonKey = "won";
  static const matchStakeKey = "match";
  static const totalCompetitorsKey = "opponents";

  static const _paddingFlex = 6;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _marblesFlex = 2;
  static const _lastChangeFlex = 2;
  static const _trendFlex = 2;
  static const _matchesFlex = 2;

  @override
  Row buildRatingKey(BuildContext context, {DateTime? trendDate}) {
    String trendTooltip = "Change over the last 3 matches";
    if(byStage) {
      trendTooltip = "Change over the last 30 stages";
    }
    return Row(
      children: [
        Expanded(flex: _paddingFlex, child: Text("")),
        Expanded(flex: _placeFlex, child: Text("")),
        Expanded(flex: _memberNumFlex, child: Text("Member #")),
        Expanded(flex: _classFlex, child: Text("Class")),
        Expanded(flex: _nameFlex, child: Text("Name")),
        Expanded(flex: _marblesFlex, child: Text("Marbles", textAlign: TextAlign.end)),
        Expanded(
          flex: _lastChangeFlex,
          child: Tooltip(
            message: "Last ±",
            child: Text("Last ±", textAlign: TextAlign.end)
          )
        ),
        Expanded(
          flex: _trendFlex,
          child: Tooltip(
            message: trendDate != null ? "Change in rating since ${DateFormat.yMd().format(trendDate)}" : trendTooltip,
            child: Text("Trend", textAlign: TextAlign.end)
          )
        ),
        Expanded(flex: _matchesFlex, child: Text("Matches", textAlign: TextAlign.end)),
        Expanded(flex: _paddingFlex, child: Text("")),
      ],
    );
  }

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating<RatingEvent> rating, DateTime? trendDate}) {
    rating as MarbleRating;
    var lastChange = rating.lastMatchChange;
    int trend = 0;
    if(trendDate != null) {
      var forDate = rating.ratingForDate(trendDate);
      trend = (rating.rating - forDate).round();
    }
    else {
      if(byStage) {
        trend = rating.trend.round();
      }
      else {
        trend = rating.trend3.round();
      }
    }
    
    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _paddingFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memberNumFlex, child: Text(rating.memberNumber)),
            Expanded(flex: _classFlex, child: Text(rating.lastClassification?.shortDisplayName ?? "none")),
            Expanded(flex: _nameFlex, child: Text(rating.getName(suffixes: false))),
            Expanded(flex: _marblesFlex, child: Text(rating.marbles.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _lastChangeFlex, child: Text(lastChange.round().toString(), textAlign: TextAlign.end)),
            Expanded(flex: _trendFlex, child: Text(trend.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _matchesFlex, child: Text(rating.length.toString(), textAlign: TextAlign.end)),
            Expanded(flex: _paddingFlex, child: Text("")),
          ],
        )
      )
    );
  }

  // TODO: allow by stage later?
  @override
  bool get byStage => false;

  @override
  MarbleRating copyShooterRating(MarbleRating rating) {
    return MarbleRating.copy(rating);
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[OldRatingProject.algorithmKey] = OldRatingProject.marbleValue;
    settings.encodeToJson(json);
  }

  static MarbleRater fromJson(Map<String, dynamic> json) {
    var settings = MarbleSettings();
    settings.loadFromJson(json);
    return MarbleRater(settings: settings);
  }

  @override
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  RatingEvent newEvent({
    required ShootingMatch match,
    MatchStage? stage,
    required ShooterRating<RatingEvent> rating,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  }) {
    rating as MarbleRating;
    return MarbleRatingEvent(
      initialMarbles: rating.marbles,
      totalCompetitors: 0,
      marblesStaked: 0,
      marblesWon: 0,
      matchStake: 0,
      match: match,
      stage: stage,
      score: score,
      matchScore: matchScore,
      infoLines: infoLines,
      infoData: infoData,
    );
  }

  @override
  RaterSettingsController<MarbleSettings> newSettingsController() {
    return MarbleSettingsController();
  }

  @override
  RaterSettingsWidget<MarbleSettings, MarbleSettingsController> newSettingsWidget(controller) {
    return MarbleSettingsWidget(controller: controller);
  }

  @override
  ShooterRating<RatingEvent> newShooterRating(MatchEntry shooter, {required Sport sport, required DateTime date}) {
    return MarbleRating(
      shooter,
      initialMarbles: settings.startingMarbles,
      sport: sport,
      date: date,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating<RatingEvent>> ratings) {
    StringBuffer csv = StringBuffer();
    csv.writeln("Member#,Name,Marbles,Matches");
    for(var r in ratings) {
      r as MarbleRating;
      csv.writeln("${r.originalMemberNumber},${r.name},${r.marbles},${r.length}");
    }
    return csv.toString();
  }

  @override
  Map<ShooterRating<RatingEvent>, RatingChange> updateShooterRatings({
    required ShootingMatch match, bool isMatchOngoing = false,
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0,
  }) {
    late DateTime start;
    if(Timings.enabled) start = DateTime.now();

    if(shooters.isEmpty) return {};
    if(shooters.length == 1) {
      var s = shooters.first;
      s as MarbleRating;
      return {
        s: RatingChange(
          change: {
            marblesStakedKey: 0,
            marblesWonKey: 0,
            matchStakeKey: 0,
            totalCompetitorsKey: 1,
          },
          infoLines: [
            "No competitors",
          ]
        )
      };
    }

    Map<ShooterRating, RatingChange> changes = {};
    Map<ShooterRating, int> stakes = {};
    int totalStake = 0;

    for(var s in shooters) {
      s as MarbleRating;
      var stake = s.calculateStake(settings.ante);
      stakes[s] = stake;
      changes[s] = RatingChange(
        change: {
          marblesStakedKey: stake.toDouble(),
          totalCompetitorsKey: shooters.length.toDouble(),
        },
      );
      totalStake += stake;
    }

    changes = settings.model.distributeMarbles(
      changes: changes,
      results: scores,
      stakes: stakes,
      totalStake: totalStake,
    );

    if(Timings.enabled) Timings().add(TimingType.updateRatings, DateTime.now().difference(start).inMicroseconds);
    return changes;
  }

  @override
  MarbleRating wrapDbRating(DbShooterRating rating) {
    return MarbleRating.wrapDbRating(rating);
  }

  @override
  int histogramBucketSize({required int shooterCount, required int matchCount, required double minRating, required double maxRating}) {
    if(maxRating <= 300) {
      return 15;
    }
    else if(maxRating <= 400) {
      return 20;
    }
    else if(maxRating <= 500) {
      return 25;
    }
    else {
      return 30;
    }
  }
}