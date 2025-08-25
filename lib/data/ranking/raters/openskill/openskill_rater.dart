/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_mode.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/model/plackett_luce.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_settings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

class OpenskillRater extends RatingSystem<OpenskillRating, OpenskillSettings> {
  static const muKey = "mu";
  static const sigmaKey = "sigma";

  final OpenskillSettings settings;

  double get beta => settings.beta;
  double get epsilon => OpenskillSettings.defaultEpsilon;
  double get tau => settings.tau;
  double get betaSquared => beta * beta;

  OpenskillRater({required this.settings});
  factory OpenskillRater.fromJson(Map<String, dynamic> json) {
    var settings = OpenskillSettings();
    settings.loadFromJson(json);
    return OpenskillRater(settings: settings);
  }

  @override
  bool get byStage => settings.byStage;

  @override
  OpenskillRating copyShooterRating(OpenskillRating rating) {
    return OpenskillRating.copy(rating);
  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    json[DbRatingProject.algorithmKey] = DbRatingProject.openskillValue;
    settings.encodeToJson(json);
  }

  @override
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  RatingEvent newEvent({
    required ShootingMatch match,
    MatchStage? stage,
    required ShooterRating rating,
    required RelativeMatchScore matchScore,
    required RelativeScore score,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],

  }) {
    rating as OpenskillRating;
    return OpenskillRatingEvent(
      initialMu: rating.mu,
      initialSigma: rating.sigma,
      muChange: 0,
      sigmaChange: 0,
      match: match,
      stage: stage,
      score: score,
      matchScore: matchScore,
      infoLines: infoLines,
      infoData: infoData,
    );
  }


  @override
  OpenskillRating newShooterRating(MatchEntry shooter, {required DateTime date, required Sport sport}) {
    return OpenskillRating(
      shooter,
      sport.initialOpenskillRatings[shooter.classification]?.elementAt(_muIndex) ?? OpenskillSettings.defaultMu,
      sport.initialOpenskillRatings[shooter.classification]?.elementAt(_sigmaIndex) ?? OpenskillSettings.defaultSigma,
      sport: sport,
      date: date,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    String csv = "Member#,Name,Rating,Mu,Sigma,${byStage ? "Stages" : "Matches"}\n";

    for(var s in ratings) {
      s as OpenskillRating;
      csv += "${s.originalMemberNumber},";
      csv += "${s.getName()},";
      csv += "${s.ordinal.toStringAsFixed(2)},";
      csv += "${s.mu.toStringAsFixed(2)}";
      csv += "${s.sigma.toStringAsFixed(2)}";
      csv += "${s.length}\n";
    }
    return csv;
  }

  @override
  List<JsonShooterRating> ratingsToJson(List<ShooterRating> ratings) {
    return ratings.map((e) => JsonShooterRating.fromShooterRating(e)).toList();
  }

  // TODO
  static const _muIndex = 0;
  static const _sigmaIndex = 1;

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
    Map<OpenskillRating, RatingChange> changes = {};

    if(shooters.isEmpty) {
      return changes;
    }
    if(shooters.length == 1) {
      return {
        (shooters[0] as OpenskillRating): RatingChange(
          change: {
            OpenskillRater.muKey: 0,
            OpenskillRater.sigmaKey: 0,
          }
        )
      };
    }

    List<OpenskillRating> provisionalTeams = shooters.map((e) => e as OpenskillRating).toList();

    provisionalTeams.retainWhere((element) {
      var score = scores[element]!;
      RawScore rawScore;
      if(score is RelativeMatchScore) {
        rawScore = score.total;
      }
      else if(score is RelativeStageScore) {
        rawScore = score.score;
      }
      else {
        throw StateError("impossible");
      }

      if(rawScore.targetEventCount == 0 && rawScore.rawTime <= 0.5) {
          return false;
      }

      return true;
    });

    List<OpenskillScore> teams = provisionalTeams.map((e) => OpenskillScore(e, scores[e]!, tau: tau)).toList();
    teams.sort((a, b) => a.rank.compareTo(b.rank));

    var model = PlackettLuce();
    model.update(this, teams, changes);

    return changes;
  }

  @override
  int histogramBucketSize({required int shooterCount, required int matchCount, required double minRating, required double maxRating}) {
    return (settings.beta).round();
  }

  @override
  OpenskillRating wrapDbRating(DbShooterRating rating) {
    return OpenskillRating.wrapDbRating(rating);
  }
}

class OpenskillScore {
  OpenskillRating rating;
  RelativeScore actualScore;

  int rank = -1;
  double get score => -actualScore.points;

  late double sumQ;
  late int a;

  double mu;
  double sigma;
  double get sigmaSquared => sigma * sigma;

  double muChange = 0.0;
  double sigmaChange = 0.0;

  OpenskillScore(this.rating, this.actualScore, {double? tau}) :
      mu = rating.mu,
      sigma = sqrt((rating.sigma * rating.sigma) + pow(tau ?? OpenskillSettings.defaultTau, 2));
}
