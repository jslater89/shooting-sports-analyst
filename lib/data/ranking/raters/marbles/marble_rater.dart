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
