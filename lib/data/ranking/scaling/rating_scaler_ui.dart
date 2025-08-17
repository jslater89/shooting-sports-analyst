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
