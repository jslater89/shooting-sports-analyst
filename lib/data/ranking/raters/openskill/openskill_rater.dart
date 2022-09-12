
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/model/plackett_luce.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating_change.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

class OpenskillRater implements RatingSystem<OpenskillRating> {
  static const muKey = "mu";
  static const sigmaKey = "sigma";

  static const _paddingFlex = 6;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _nameFlex = 6;
  static const _ordinalFlex = 2;
  static const _muFlex = 2;
  static const _sigmaFlex = 2;
  static const _connectednessFlex = 2;
  static const _eventsFlex = 2;

  static const defaultMu = 25.0;
  static const defaultSigma = 25/3;
  static const defaultBeta = 25/3/2; // half of defaultSigma
  static const defaultTau = 25/3/10;
  static const defaultEpsilon = 0.0001;

  final double beta = defaultBeta;
  final double epsilon = defaultEpsilon;
  final double tau = defaultTau;
  double get betaSquared => beta * beta;

  @override
  Row buildRatingKey(BuildContext context) {
    return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(flex: _paddingFlex - _placeFlex, child: Text("")),
          Expanded(flex: _placeFlex, child: Text("")),
          Expanded(flex: _memberNumFlex, child: Text("Member #")),
          Expanded(flex: _nameFlex, child: Text("Name")),
          Expanded(flex: _ordinalFlex, child: Text("Rating")),
          Expanded(flex: _muFlex, child: Text("Mu")),
          Expanded(flex: _sigmaFlex, child: Text("Sigma")),
          Expanded(flex: _paddingFlex, child: Text("")),
        ]
    );
  }

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating}) {
    var trend = rating.rating - rating.averageRating().firstRating;
    rating as OpenskillRating;

    return ScoreRow(
      color: (place - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: _paddingFlex - _placeFlex, child: Text("")),
            Expanded(flex: _placeFlex, child: Text("$place")),
            Expanded(flex: _memberNumFlex, child: Text(rating.shooter.memberNumber)),
            Expanded(flex: _nameFlex, child: Text(rating.shooter.getName(suffixes: false))),
            Expanded(flex: _ordinalFlex, child: Text(rating.ordinal.toStringAsFixed(2))),
            Expanded(flex: _muFlex, child: Text(rating.mu.toStringAsFixed(2))),
            Expanded(flex: _sigmaFlex, child: Text(rating.sigma.toStringAsFixed(3))),
            Expanded(flex: _paddingFlex, child: Text("")),
          ]
        )
      )
    );
  }

  OpenskillRater({required this.byStage});
  factory OpenskillRater.fromJson(Map<String, dynamic> json) {
    return OpenskillRater(byStage: (json[RatingProject.byStageKey] ?? true) as bool);
  }

  @override
  bool byStage;

  @override
  OpenskillRating copyShooterRating(OpenskillRating rating) {
    return OpenskillRating.copy(rating);
  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    // TODO: settings
  }

  @override
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  RatingEvent newEvent({
    required PracticalMatch match, Stage? stage,
    required ShooterRating rating, required RelativeScore score, List<String> info = const []
  }) {
    rating as OpenskillRating;
    return OpenskillRatingEvent(initialMu: rating.mu, muChange: 0, sigmaChange: 0, match: match, stage: stage, score: score, info: info);
  }

  @override
  OpenskillRating newShooterRating(Shooter shooter, {DateTime? date}) {
    return OpenskillRating(
      shooter,
      initialClassRatings[shooter.classification]?.elementAt(_muIndex) ?? defaultMu,
      initialClassRatings[shooter.classification]?.elementAt(_sigmaIndex) ?? defaultSigma,
    );
  }

  @override
  String ratingsToCsv(List<ShooterRating> ratings) {
    String csv = "Member#,Name,Rating,Mu,Sigma,${byStage ? "Stages" : "Matches"}\n";

    for(var s in ratings) {
      s as OpenskillRating;
      csv += "${s.shooter.memberNumber},";
      csv += "${s.shooter.getName()},";
      csv += "${s.ordinal.toStringAsFixed(2)},";
      csv += "${s.mu.toStringAsFixed(2)}";
      csv += "${s.sigma.toStringAsFixed(2)}";
      csv += "${s.ratingEvents.length}\n";
    }
    return csv;
  }

  // TODO
  static const _muIndex = 0;
  static const _sigmaIndex = 1;
  static const initialClassRatings = {
    Classification.GM: [defaultMu + 25, defaultSigma],
    Classification.M: [defaultMu + 20, defaultSigma],
    Classification.A: [defaultMu + 15, defaultSigma],
    Classification.B: [defaultMu + 10, defaultSigma],
    Classification.C: [defaultMu + 5, defaultSigma],
    Classification.D: [defaultMu, defaultSigma],
    Classification.U: [defaultMu + 5, defaultSigma],
    Classification.unknown: [defaultMu, defaultSigma],
  };

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({
    required List<ShooterRating> shooters,
    required Map<ShooterRating, RelativeScore> scores,
    required Map<ShooterRating, RelativeScore> matchScores,
    double matchStrengthMultiplier = 1.0,
    double connectednessMultiplier = 1.0,
    double eventWeightMultiplier = 1.0
  }) {
    Map<OpenskillRating, RatingChange> changes = {};

    List<OpenskillRating> provisionalTeams = shooters.map((e) => e as OpenskillRating).toList();
    provisionalTeams.retainWhere((element) {
      if(scores[element]!.score.hits == 0 && scores[element]!.score.time <= 0.5) {
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
}

class OpenskillScore {
  OpenskillRating rating;
  RelativeScore actualScore;

  int rank = -1;
  double get score => -actualScore.relativePoints;

  late double sumQ;
  late int a;

  double mu;
  double sigma;
  double get sigmaSquared => sigma * sigma;

  double muChange = 0.0;
  double sigmaChange = 0.0;

  OpenskillScore(this.rating, this.actualScore, {double tau = OpenskillRater.defaultTau}) :
      mu = rating.mu,
      sigma = sqrt((rating.sigma * rating.sigma) + (tau * tau));
}