/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/relative_score_function_model.dart';

class SigmoidModel extends RelativeScoreFunctionModel {
  static const modelName = "sigmoid";
  static const defaultSteepness = 6.0;
  static const defaultMidpoint = 0.75;

  @override
  String get name => modelName;

  double steepness;
  double midpoint;

  SigmoidModel({this.steepness = defaultSteepness, this.midpoint = defaultMidpoint});

  @override
  double shareForRelativeScore(double relativeScore) {
    return 1 / (1 + exp(-steepness * (relativeScore - midpoint)));
  }

  static SigmoidModel fromSettings(MarbleSettings settings) {
    return SigmoidModel(
      steepness: settings.sigmoidSteepness,
      midpoint: settings.sigmoidMidpoint,
    );
  }
}