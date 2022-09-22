
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/prediction/match_prediction.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/model/plackett_luce.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/ui/openskill_settings_ui.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';

class OpenskillRater extends RatingSystem<OpenskillRating, OpenskillSettings, OpenskillSettingsController> {
  static const muKey = "mu";
  static const sigmaKey = "sigma";

  static const _paddingFlex = 6;
  static const _placeFlex = 2;
  static const _memberNumFlex = 3;
  static const _classFlex = 1;
  static const _nameFlex = 6;
  static const _ordinalFlex = 2;
  static const _muFlex = 2;
  static const _sigmaFlex = 2;
  static const _connectednessFlex = 2;
  static const _eventsFlex = 2;

  final OpenskillSettings settings;

  double get beta => settings.beta;
  double get epsilon => OpenskillSettings.defaultEpsilon;
  double get tau => settings.tau;
  double get betaSquared => beta * beta;

  @override
  Row buildRatingKey(BuildContext context) {
    return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(flex: _paddingFlex - _placeFlex, child: Text("")),
          Expanded(flex: _placeFlex, child: Text("")),
          Expanded(flex: _memberNumFlex, child: Text("Member #")),
          Expanded(flex: _classFlex, child: Text("Class")),
          Expanded(flex: _nameFlex, child: Text("Name")),
          Expanded(flex: _ordinalFlex, child: Text("Rating", textAlign: TextAlign.end)),
          Expanded(flex: _muFlex, child: Text("Mu", textAlign: TextAlign.end)),
          Expanded(flex: _sigmaFlex, child: Text("Sigma", textAlign: TextAlign.end)),
          Expanded(flex: _eventsFlex, child: Text(byStage ? "Stages" : "Matches", textAlign: TextAlign.end)),
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
            Expanded(flex: _classFlex, child: Text(rating.lastClassification.displayString())),
            Expanded(flex: _nameFlex, child: Text(rating.shooter.getName(suffixes: false))),
            Expanded(flex: _ordinalFlex, child: Text(rating.ordinal.toStringAsFixed(1), textAlign: TextAlign.end)),
            Expanded(flex: _muFlex, child: Text(rating.mu.toStringAsFixed(1), textAlign: TextAlign.end)),
            Expanded(flex: _sigmaFlex, child: Text(rating.sigma.toStringAsFixed(2), textAlign: TextAlign.end)),
            Expanded(flex: _eventsFlex, child: Text("${rating.length}", textAlign: TextAlign.end,)),
            Expanded(flex: _paddingFlex, child: Text("")),
          ]
        )
      )
    );
  }

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
    json[RatingProject.algorithmKey] = RatingProject.openskillValue;
    settings.encodeToJson(json);
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
      initialClassRatings[shooter.classification]?.elementAt(_muIndex) ?? OpenskillSettings.defaultMu,
      initialClassRatings[shooter.classification]?.elementAt(_sigmaIndex) ?? OpenskillSettings.defaultSigma,
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
    Classification.GM: [OpenskillSettings.defaultMu + 25, OpenskillSettings.defaultSigma],
    Classification.M: [OpenskillSettings.defaultMu + 20, OpenskillSettings.defaultSigma],
    Classification.A: [OpenskillSettings.defaultMu + 15, OpenskillSettings.defaultSigma],
    Classification.B: [OpenskillSettings.defaultMu + 10, OpenskillSettings.defaultSigma],
    Classification.C: [OpenskillSettings.defaultMu + 5, OpenskillSettings.defaultSigma],
    Classification.D: [OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma],
    Classification.U: [OpenskillSettings.defaultMu + 5, OpenskillSettings.defaultSigma],
    Classification.unknown: [OpenskillSettings.defaultMu, OpenskillSettings.defaultSigma],
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

  @override
  OpenskillSettingsController newSettingsController() {
    return OpenskillSettingsController();
  }

  @override
  OpenskillSettingsWidget newSettingsWidget(OpenskillSettingsController controller) {
    return OpenskillSettingsWidget(controller: controller);
  }

  @override
  int histogramBucketSize(int shooters, int matchCount) => 10;

  @override
  List<ShooterPrediction> predict(List<ShooterRating> ratings) {
    // TODO: implement predict
    throw UnimplementedError();
  }

  @override
  double validate({required PracticalMatch result, required List<ShooterPrediction> predictions}) {
    // TODO: implement validate
    throw UnimplementedError();
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

  OpenskillScore(this.rating, this.actualScore, {double? tau}) :
      mu = rating.mu,
      sigma = sqrt((rating.sigma * rating.sigma) + pow(tau ?? OpenskillSettings.defaultTau, 2));
}