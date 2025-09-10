/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

abstract class RatingScalerUI {
  Widget? settingsWidget() => null;

  static RatingScalerUI? get(RatingScaler scaler) {
    return switch(scaler.runtimeType) {
      _ => null,
    };
  }
}
