/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/help/scalers_and_distributions_help.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/group_carrier_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/standardized_maximum_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/top_2pct_average_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/distribution_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/distribution_significance_scaler.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/z_score_scaler.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/ui/rater/display_settings.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';

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
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Miscellaneous settings"),
          HelpButton(helpTopicId: scalersAndDistributionsHelpId),
        ],
      ),
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
              dropdownMenuEntries: RatingScalerType.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
            ),
            const SizedBox(height: 15),
            DropdownMenu<AvailableEstimator>(
              label: const Text("Rating distribution"),
              initialSelection: AvailableEstimator.fromEstimator(_displayModel.estimator),
              onSelected: (value) {
                if(value != null) {
                  _displayModel.estimator = value.estimator;
                }
              },
              dropdownMenuEntries: AvailableEstimator.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () {
          widget.displayModel.copyFrom(_displayModel);
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
  distributionPercentile,
  distributionZScore,
  distributionZScoreEloScale,
  groupCarrier;

  String get uiLabel => switch(this) {
    none => "None",
    standardizedMaximum => "Standardized maximum",
    top2PercentAverage => "Top 2% average",
    zScore => "Z-score",
    zScoreEloScale => "Z-score (Elo scale)",
    distributionPercentile => "Distribution percentile",
    distributionZScore => "Distribution Z-score",
    distributionZScoreEloScale => "Distribution Z-score (Elo scale)",
    groupCarrier => "Group carrier",
  };

  static fromScaler(RatingScaler scaler) {
    if (scaler is StandardizedMaximumScaler) {
      return RatingScalerType.standardizedMaximum;
    }
    else if(scaler is Top2PercentAverageScaler) {
      return RatingScalerType.top2PercentAverage;
    }
    else if(scaler is DistributionScaler) {
      return RatingScalerType.distributionPercentile;
    }
    else if(scaler is ZScoreScaler && scaler.scaleFactor == 100) {
      return RatingScalerType.zScore;
    }
    else if(scaler is ZScoreScaler) {
      return RatingScalerType.zScoreEloScale;
    }
    else if(scaler is DistributionZScoreScaler && scaler.scaleFactor == 100) {
      return RatingScalerType.distributionZScore;
    }
    else if(scaler is DistributionZScoreScaler) {
      return RatingScalerType.distributionZScoreEloScale;
    }
    else if(scaler is GroupCarrierScaler) {
      return RatingScalerType.groupCarrier;
    }
    return RatingScalerType.none;
  }

  RatingScaler? scaler() {
    switch(this) {
      case RatingScalerType.standardizedMaximum:
        return StandardizedMaximumScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.top2PercentAverage:
        return Top2PercentAverageScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.distributionPercentile:
        return DistributionScaler(info: RatingScalerInfo.empty(), percentiles: [0.995, 0.95, 0.85], percentileRatings: [1920, 1610, 1410]);
      case RatingScalerType.zScore:
        return ZScoreScaler(info: RatingScalerInfo.empty(), scaleFactor: 100, scaleOffset: 0);
      case RatingScalerType.zScoreEloScale:
        return ZScoreScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.distributionZScore:
        return DistributionZScoreScaler(info: RatingScalerInfo.empty(), scaleFactor: 100, scaleOffset: 0);
      case RatingScalerType.distributionZScoreEloScale:
        return DistributionZScoreScaler(info: RatingScalerInfo.empty());
      case RatingScalerType.groupCarrier:
        return GroupCarrierScaler(info: RatingScalerInfo.empty(), targetRating: 2000,
          groupSourceRatings: {
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-open")!: 1903,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-carryoptics")!: 1851,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-production")!: 2015,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-limited")!: 2025,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-limited-optics")!: 1775,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-pcc")!: 1840,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-singlestack")!: 2100,
            UspsaRatingGroupsProvider.instance.getGroup("uspsa-revolver")!: 1929,
          }
        );
      case RatingScalerType.none:
        return null;
    }
  }
}
