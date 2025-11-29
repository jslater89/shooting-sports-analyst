/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';

class Glicko2Settings extends RaterSettings {

  static const _scalingFactorKey = "g2ScalingFactor";
  static const _maximumRDKey = "g2MaximumRD";
  static const _tauKey = "g2Tau";
  static const _pseudoRatingPeriodLengthKey = "g2PseudoRatingPeriodLength";

  Glicko2Settings({
    this.scalingFactor = defaultScalingFactor,
    this.maximumRD = defaultMaximumRD,
    this.tau = defaultTau,
    this.pseudoRatingPeriodLength = defaultPseudoRatingPeriodLength,
    this.initialRating = defaultInitialRating,
    this.initialVolatility = defaultInitialVolatility,
    this.startingRD = defaultStartingRD,
  });

  /// The default default rating for Glicko-2, in display units.
  static const defaultInitialRating = 1500.0;
  /// The 1500pt-center Glicko-2 scaling factor.
  static const defaultScalingFactor = 173.7178;
  /// The maximum RD to allow, in display units.
  static const defaultMaximumRD = 400.0;
  /// The default tau value for Glicko-2.
  static const defaultTau = 0.5;
  /// The length of a pseudo-rating-period for the purposes of
  /// increasing RD over time, in days.
  static const defaultPseudoRatingPeriodLength = 7;
  /// The default initial volatility for Glicko-2.
  static const defaultInitialVolatility = 0.06;
  /// The default starting RD for Glicko-2.
  static const defaultStartingRD = 350.0;

  /// The default initial rating for Glicko-2, in display units.
  double initialRating;

  /// The scaling factor to convert from small-float internal ratings to display ratings and RDs.
  double scalingFactor;

  /// The initial volatility for Glicko-2.
  double initialVolatility;

  /// The starting RD for Glicko-2.
  double startingRD;

  double scaleToInternal(double number, {double? offset}) => (number - (offset ?? 0)) / scalingFactor;
  double scaleToDisplay(double number, {double? offset}) => (number * scalingFactor) + (offset ?? 0);

  /// The maximum RD to allow, in display units.
  double maximumRD;

  /// The maximum RD to allow, in internal units.
  double get internalMaximumRD => scaleToInternal(maximumRD);

  /// The tau value for Glicko-2, which controls the rate of volatility change.
  double tau;

  /// The length of a pseudo-rating-period for the purposes of
  /// increasing volatility over time, in days.
  int pseudoRatingPeriodLength;

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[_scalingFactorKey] = scalingFactor;
    json[_maximumRDKey] = maximumRD;
    json[_tauKey] = tau;
    json[_pseudoRatingPeriodLengthKey] = pseudoRatingPeriodLength;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    scalingFactor = (json[_scalingFactorKey] ?? defaultScalingFactor) as double;
    maximumRD = (json[_maximumRDKey] ?? defaultMaximumRD) as double;
    tau = (json[_tauKey] ?? defaultTau) as double;
    pseudoRatingPeriodLength = (json[_pseudoRatingPeriodLengthKey] ?? defaultPseudoRatingPeriodLength) as int;
  }
}
