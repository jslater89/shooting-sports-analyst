/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

class RaterViewDisplayModel with ChangeNotifier {
  // TODO: bring in other stuff from RaterView.

  RatingScaler? _scaler;
  RatingScaler? get scaler => _scaler;
  set scaler(RatingScaler? value) {
    _scaler = value;
    notifyListeners();
  }

  RaterViewDisplayModel({
    RatingScaler? scaler,
  }) {
    _scaler = scaler;
  }

  RaterViewDisplayModel copy() {
    return RaterViewDisplayModel(
      scaler: scaler?.copy(),
    );
  }
}
