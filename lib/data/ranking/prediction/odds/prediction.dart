/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard.dart';
import 'package:shooting_sports_analyst/util.dart';

abstract class UserPrediction {
  final ShooterRating shooter;

  PredictionProbability calculateProbability(
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    {
      Random? random,
      double disasterChance = 0.01,
      double? houseEdge,
      double bestPossibleOdds = PredictionProbability.bestPossibleOddsDefault,
      double worstPossibleOdds = PredictionProbability.worstPossibleOddsDefault,
    });

  UserPrediction({
    required this.shooter,
  });

  UserPrediction deepCopy();

  /// A string suitable for display in a list of predictions that encapsulates the
  /// wager.
  String get descriptiveString;

  /// A string suitable for display in a tooltip that contains extra information
  /// about the prediction. Return null if no tooltip is needed. Info must be the
  /// info map in the probability returned by [calculateProbability].
  String? tooltipString(Map<String, double> info);
}

/// A prediction from a user for a shooter's finish.
class PlacePrediction extends UserPrediction {
  final int bestPlace;
  final int worstPlace;

  static const minPlaceInfo = "minPlace";
  static const maxPlaceInfo = "maxPlace";
  static const meanPlaceInfo = "meanPlace";
  static const stdDevPlaceInfo = "stdDevPlace";

  PlacePrediction({
    required super.shooter,
    required this.bestPlace,
    required this.worstPlace,
  }) {
    if (bestPlace > worstPlace) {
      throw ArgumentError("Best place must be less than worst place");
    }
  }

  PlacePrediction.exactPlace(ShooterRating shooter, this.bestPlace) : this.worstPlace = bestPlace, super(shooter: shooter);

  /// Return a copy of the prediction with the given fields updated.
  ///
  /// This is also a deep copy; [shooter] should not be modified, and
  /// the other fields are copied by value.
  PlacePrediction copyWith({
    ShooterRating? shooter,
    int? bestPlace,
    int? worstPlace,
  }) => PlacePrediction(
    shooter: shooter ?? this.shooter,
    bestPlace: bestPlace ?? this.bestPlace,
    worstPlace: worstPlace ?? this.worstPlace,
  );

  @override
  PredictionProbability calculateProbability(
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    {
      Random? random,
      double disasterChance = 0.01,
      double? houseEdge,
      double bestPossibleOdds = PredictionProbability.bestPossibleOddsDefault,
      double worstPossibleOdds = PredictionProbability.worstPossibleOddsDefault,
    }) {
    return PredictionProbability.fromPlacePrediction(
      this,
      shootersToPredictions,
      random: random,
      disasterChance: disasterChance,
      houseEdge: houseEdge,
      bestPossibleOdds: bestPossibleOdds,
      worstPossibleOdds: worstPossibleOdds,
    );
  }

  @override
  UserPrediction deepCopy() => copyWith();

  @override
  String get descriptiveString => "${shooter.name} ${bestPlace.ordinalPlace}-${worstPlace.ordinalPlace}";

  @override
  String? tooltipString(Map<String, double> info) {
    return
"""${info[minPlaceInfo]?.toStringAsFixed(0)} - ${info[maxPlaceInfo]?.toStringAsFixed(0)}
${info[meanPlaceInfo]?.toStringAsFixed(2)} ± ${info[stdDevPlaceInfo]?.toStringAsFixed(2)}""";
  }
}

class PercentagePrediction extends UserPrediction {
  final double ratio;
  double get percentage => ratio * 100;
  bool above;

  static const minPercentageInfo = "minPercentage";
  static const maxPercentageInfo = "maxPercentage";
  static const meanPercentageInfo = "meanPercentage";
  static const stdDevPercentageInfo = "stdDevPercentage";

  PercentagePrediction({
    required super.shooter,
    required this.ratio,
    this.above = true,
  });

  @override
  PredictionProbability calculateProbability(
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    {
      Random? random,
      double disasterChance = 0.01,
      double? houseEdge,
      double bestPossibleOdds = PredictionProbability.bestPossibleOddsDefault,
      double worstPossibleOdds = PredictionProbability.worstPossibleOddsDefault,
    }) {
    return PredictionProbability.fromPercentagePrediction(this, shootersToPredictions);
  }

  @override
  UserPrediction deepCopy() => copyWith();

  PercentagePrediction copyWith({
    ShooterRating? shooter,
    double? ratio,
    bool? above,
  }) => PercentagePrediction(
    shooter: shooter ?? this.shooter,
    ratio: ratio ?? this.ratio,
    above: above ?? this.above,
  );

  @override
  String get descriptiveString => "${shooter.name} ${above ? "≥" : "≤"}${ratio.asPercentage(decimals: 1, includePercent: true)}";

  @override
  String? tooltipString(Map<String, double> info) {
    return
"""${info[minPercentageInfo]?.asPercentage(decimals: 1, includePercent: true)} - ${info[maxPercentageInfo]?.asPercentage(decimals: 1, includePercent: true)}
${info[meanPercentageInfo]?.asPercentage(decimals: 1, includePercent: true)} ± ${info[stdDevPercentageInfo]?.asPercentage(decimals: 2, includePercent: true)}""";
  }
}

class PercentageSpreadPrediction extends UserPrediction {
  ShooterRating get favorite => shooter;
  final ShooterRating underdog;
  final double ratioSpread;
  double get percentageSpread => ratioSpread * 100;

  static const minPercentageSpreadInfo = "minPercentageSpread";
  static const maxPercentageSpreadInfo = "maxPercentageSpread";
  static const meanPercentageSpreadInfo = "meanPercentageSpread";
  static const stdDevPercentageSpreadInfo = "stdDevPercentageSpread";

  PercentageSpreadPrediction({
    required super.shooter,
    required this.underdog,
    required this.ratioSpread,
  });

  @override
  PredictionProbability calculateProbability(
    Map<ShooterRating, AlgorithmPrediction> shootersToPredictions,
    {
      Random? random,
      double disasterChance = 0.01,
      double? houseEdge,
      double bestPossibleOdds = PredictionProbability.bestPossibleOddsDefault,
      double worstPossibleOdds = PredictionProbability.worstPossibleOddsDefault,
    }) {
    return PredictionProbability.fromPercentageSpreadPrediction(this, shootersToPredictions,
      random: random,
      disasterChance: disasterChance,
      houseEdge: houseEdge,
      bestPossibleOdds: bestPossibleOdds,
      worstPossibleOdds: worstPossibleOdds,
    );
  }

  @override
  UserPrediction deepCopy() => copyWith();

  PercentageSpreadPrediction copyWith({
    ShooterRating? shooter,
    ShooterRating? underdog,
    double? ratioSpread,
  }) => PercentageSpreadPrediction(
    shooter: shooter ?? this.shooter,
    underdog: underdog ?? this.underdog,
    ratioSpread: ratioSpread ?? this.ratioSpread,
  );

  @override
  String get descriptiveString => "${shooter.name} -${ratioSpread.asPercentage(decimals: 2, includePercent: true)} vs. ${underdog.name}";

  @override
  String? tooltipString(Map<String, double> info) {
    return
"""${info[minPercentageSpreadInfo]?.asPercentage(decimals: 2, includePercent: true)} - ${info[maxPercentageSpreadInfo]?.asPercentage(decimals: 2, includePercent: true)}
${info[meanPercentageSpreadInfo]?.asPercentage(decimals: 2, includePercent: true)} ± ${info[stdDevPercentageSpreadInfo]?.asPercentage(decimals: 3, includePercent: true)}""";
  }
}
