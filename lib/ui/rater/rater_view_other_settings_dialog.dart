/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/top_2pct_average_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/weibull_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/weibull_significance_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/z_score_scaler.dart';
import 'package:shooting_sports_analyst/ui/rater/display_settings.dart';

class RaterViewOtherSettingsDialog extends StatefulWidget {
  const RaterViewOtherSettingsDialog({super.key, required this.displayModel});

  final RaterViewDisplayModel displayModel;

  @override
  State<RaterViewOtherSettingsDialog> createState() => _RaterViewOtherSettingsDialogState();

  static Future<void> show(BuildContext context, RaterViewDisplayModel displayModel) async {
    return showDialog<void>(
      context: context,
      builder: (context) => RaterViewOtherSettingsDialog(displayModel: displayModel),
    );
  }
}

class _RaterViewOtherSettingsDialogState extends State<RaterViewOtherSettingsDialog> {
  late RaterViewDisplayModel _displayModel;

  @override
  void initState() {
    super.initState();
    _displayModel = widget.displayModel.copy();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Miscellaneous settings"),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<RatingScalerType>(
              label: const Text("Rating scaler"),
              initialSelection: _displayModel.scaler != null ? RatingScalerType.fromScaler(_displayModel.scaler!) : RatingScalerType.none,
              onSelected: (value) {
                _displayModel.scaler = value?.scaler();
              },
              dropdownMenuEntries: RatingScalerType.values.map((e) => DropdownMenuEntry(value: e, label: e.name)).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () {
          widget.displayModel.scaler = _displayModel.scaler;
          Navigator.of(context).pop();
        }, child: const Text("SAVE")),
      ],
    );
  }
}

enum RatingScalerType {
  none,
  standardizedMaximum,
  top2PercentAverage,
  zScore,
  zScoreEloScale,
  weibullPercentile,
  weibullZScore,
  weibullZScoreEloScale;

  static fromScaler(RatingScaler scaler) {
    if (scaler is StandardizedMaximumScaler) {
      return RatingScalerType.standardizedMaximum;
    }
    else if(scaler is Top2PercentAverageScaler) {
      return RatingScalerType.top2PercentAverage;
    }
    else if(scaler is WeibullScaler) {
      return RatingScalerType.weibullPercentile;
    }
    else if(scaler is ZScoreScaler && scaler.scaleFactor == 100) {
      return RatingScalerType.zScore;
    }
    else if(scaler is ZScoreScaler) {
      return RatingScalerType.zScoreEloScale;
    }
    else if(scaler is WeibullZScoreScaler && scaler.scaleFactor == 100) {
      return RatingScalerType.weibullZScore;
    }
    else if(scaler is WeibullZScoreScaler) {
      return RatingScalerType.weibullZScoreEloScale;
    }
    return RatingScalerType.none;
  }

  RatingScaler? scaler() {
    switch(this) {
      case RatingScalerType.standardizedMaximum:
        return StandardizedMaximumScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.top2PercentAverage:
        return Top2PercentAverageScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.weibullPercentile:
        return WeibullScaler(info: RatingScalerInfo.empty(), percentiles: [0.995, 0.95, 0.85], percentileRatings: [1920, 1610, 1410]);
      case RatingScalerType.zScore:
        return ZScoreScaler(info: RatingScalerInfo.empty(), scaleFactor: 100, scaleOffset: 0);
      case RatingScalerType.zScoreEloScale:
        return ZScoreScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.weibullZScore:
        return WeibullZScoreScaler(info: RatingScalerInfo.empty(), scaleFactor: 100, scaleOffset: 0);
      case RatingScalerType.weibullZScoreEloScale:
        return WeibullZScoreScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.none:
        return null;
    }
  }
}
