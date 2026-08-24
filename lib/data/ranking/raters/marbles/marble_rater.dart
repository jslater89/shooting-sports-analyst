/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_system_ui_data.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class MarbleRater extends RatingSystem<MarbleRating, MarbleSettings> {
  MarbleRater({required this.settings});

  MarbleSettings settings;

  static const marblesStakedKey = "staked";
  static const marblesWonKey = "won";
  static const matchStakeKey = "match";
  static const totalCompetitorsKey = "opponents";

  // TODO: allow by stage later?
  @override
  bool get byStage => false;

  @override
  MarbleRating copyShooterRating(MarbleRating rating) {
    return MarbleRating.copy(rating);
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[DbRatingProject.algorithmKey] = DbRatingProject.marbleValue;
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
  List<JsonShooterRating> ratingsToJson(List<ShooterRating> ratings) {
    return ratings.map((e) => JsonShooterRating.fromShooterRating(e)).toList();
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
  RatingChange noOpChangeFor({
    required MarbleRating shooter,
    required RelativeScore score,
    required RelativeMatchScore matchScore,
    required NonRatingResultReason reason,
  }) {
    return RatingChange(
      change: {
        MarbleRater.marblesStakedKey: 0.0,
        MarbleRater.marblesWonKey: 0.0,
        MarbleRater.matchStakeKey: 0.0,
        MarbleRater.totalCompetitorsKey: 0.0,
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
  List<RatingRowData> buildRatingKeyData({DateTime? trendDate, RatingSortMode? sortMode}) {
    final baseTrendTooltip = byStage ?
      "Change over the last 30 stages" :
      "Change over the last 3 matches";
    final trendHeaderTooltip = trendDate != null ?
      "Change in rating since ${DateFormat.yMd().format(trendDate)}" :
      baseTrendTooltip;
    return [
      RatingRowData(data: "", flex: _paddingFlex),
      RatingRowData(data: "", flex: _placeFlex),
      RatingRowData(data: "Member #", flex: _memberNumFlex),
      RatingRowData(data: "Class", flex: _classFlex),
      RatingRowData(data: "Name", flex: _nameFlex),
      RatingRowData(data: "Marbles", alignment: AbstractAlignment.end, flex: _marblesFlex),
      RatingRowData(data: "Last ±", alignment: AbstractAlignment.end, flex: _lastChangeFlex),
      RatingRowData(data: "Trend", tooltip: trendHeaderTooltip, alignment: AbstractAlignment.end, flex: _trendFlex),
      RatingRowData(data: "Matches", alignment: AbstractAlignment.end, flex: _matchesFlex),
      RatingRowData(data: "", flex: _paddingFlex),
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
    rating as MarbleRating;
    final lastChange = rating.lastMatchChange;
    int trend;
    if(trendDate != null) {
      final forDate = rating.ratingForDate(trendDate);
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
    return [
      RatingRowData(data: "", flex: _paddingFlex),
      RatingRowData(data: "$place", flex: _placeFlex),
      RatingRowData(data: rating.memberNumber, flex: _memberNumFlex),
      RatingRowData(data: rating.lastClassification?.shortDisplayName ?? "none", flex: _classFlex),
      RatingRowData(data: rating.getName(suffixes: false), flex: _nameFlex),
      RatingRowData(data: rating.marbles.toString(), alignment: AbstractAlignment.end, flex: _marblesFlex),
      RatingRowData(data: lastChange.round().toString(), alignment: AbstractAlignment.end, flex: _lastChangeFlex),
      RatingRowData(data: trend.toString(), alignment: AbstractAlignment.end, flex: _trendFlex),
      RatingRowData(data: rating.length.toString(), alignment: AbstractAlignment.end, flex: _matchesFlex),
      RatingRowData(data: "", flex: _paddingFlex),
    ];
  }
}
