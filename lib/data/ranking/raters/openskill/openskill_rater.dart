
import 'package:flutter/src/widgets/basic.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:uspsa_result_viewer/data/match/relative_scores.dart';
import 'package:uspsa_result_viewer/data/match/shooter.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_change.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_mode.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

class OpenskillRater implements RatingSystem<OpenskillRating> {
  static const muKey = "mu";
  static const sigmaKey = "sigma";

  static const _paddingFlex = 6;
  static const _memberNumFlex = 3;
  static const _nameFlex = 6;
  static const _ordinalFlex = 2;
  static const _muFlex = 2;
  static const _sigmaflex = 2;
  static const _connectednessFlex = 2;
  static const _eventsFlex = 2;

  @override
  Row buildRatingKey(BuildContext context) {
    // TODO: implement buildRatingKey
    throw UnimplementedError();
  }

  @override
  ScoreRow buildRatingRow({required BuildContext context, required int place, required ShooterRating rating}) {
    // TODO: implement buildShooterRatingRow
    throw UnimplementedError();
  }

  OpenskillRater({required this.byStage});

  @override
  bool byStage;

  @override
  ShooterRating<OpenskillRating> copyShooterRating(OpenskillRating rating) {
    return OpenskillRating.copy(rating);
  }

  @override
  encodeToJson(Map<String, dynamic> json) {
    // TODO: implement encodeToJson
    throw UnimplementedError();
  }

  @override
  RatingMode get mode => RatingMode.wholeEvent;

  @override
  RatingEvent newEvent({required String eventName, required RelativeScore score, List<String> info = const []}) {
    // TODO: implement newEvent
    throw UnimplementedError();
  }

  @override
  ShooterRating<OpenskillRating> newShooterRating(Shooter shooter, {DateTime? date}) {
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
      csv += "${Rater.processMemberNumber(s.shooter.memberNumber)},";
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
  static const defaultMu = 25.0;
  static const defaultSigma = 8.0;
  static const initialClassRatings = {
    Classification.GM: [defaultMu, defaultSigma],
    Classification.M: [defaultMu, defaultSigma],
    Classification.A: [defaultMu, defaultSigma],
    Classification.B: [defaultMu, defaultSigma],
    Classification.C: [defaultMu, defaultSigma],
    Classification.D: [defaultMu, defaultSigma],
    Classification.U: [defaultMu, defaultSigma],
    Classification.unknown: [defaultMu, defaultSigma],
  };

  @override
  Map<ShooterRating, RatingChange> updateShooterRatings({required List<ShooterRating> shooters, required Map<ShooterRating, RelativeScore> scores, double matchStrengthMultiplier = 1.0, double connectednessMultiplier = 1.0, double eventWeightMultiplier = 1.0}) {
    // TODO: implement updateShooterRatings
    throw UnimplementedError();
  }
}