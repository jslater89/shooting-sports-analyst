/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/ordinal_place_function_model.dart';

class OrdinalPowerLawModel extends OrdinalPlaceFunctionModel {
  static const modelName = "ordinalPowerLaw";
  static const defaultPower = 2.0;
  @override
  String get name => modelName;

  double power;

  OrdinalPowerLawModel({this.power = defaultPower});

  @override
  double shareForOrdinalPlace(int place, int competitors) {
    var share = pow(competitors - place + 1, power).toDouble();
    if(share.isNaN) {
      print("break");
    }
    return share;
  }

  static OrdinalPowerLawModel fromSettings(MarbleSettings settings) {
    return OrdinalPowerLawModel(power: settings.ordinalPower);
  }
}