/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/math/gamma/gamma_estimator.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

class RaterViewDisplayModel with ChangeNotifier {
  // TODO: bring in other stuff from RaterView.

  late ContinuousDistributionEstimator _estimator;
  ContinuousDistributionEstimator get estimator => _estimator;
  set estimator(ContinuousDistributionEstimator value) {
    _estimator = value;
    notifyListeners();
  }

  RatingScaler? _scaler;
  RatingScaler? get scaler => _scaler;
  set scaler(RatingScaler? value) {
    _scaler = value;
    notifyListeners();
  }

  RaterViewDisplayModel({
    RatingScaler? scaler,
    ContinuousDistributionEstimator? estimator,
  }) {
    _scaler = scaler;
    _estimator = estimator ?? GammaEstimator();
  }

  RaterViewDisplayModel copy() {
    return RaterViewDisplayModel(
      scaler: scaler?.copy(),
      estimator: estimator,
    );
  }

  void copyFrom(RaterViewDisplayModel other) {
    _scaler = other.scaler;
    _estimator = other.estimator;
    notifyListeners();
  }
}
