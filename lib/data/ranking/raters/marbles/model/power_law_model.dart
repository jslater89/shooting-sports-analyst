
import 'dart:math';

import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/relative_score_function_model.dart';

class PowerLawModel extends RelativeScoreFunctionModel {
  static const modelName = "powerLaw";
  static const defaultPower = 2.5;

  final double power;
  const PowerLawModel({required this.power});

  @override
  String get name => modelName;

  @override
  double shareForRelativeScore(double relativeScore) {
    return pow(relativeScore, power).toDouble();
  }

  static PowerLawModel fromSettings(MarbleSettings settings) {
    return PowerLawModel(power: settings.relativeScorePower);
  }
}