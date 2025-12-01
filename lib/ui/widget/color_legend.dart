/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

class ColorLegend extends StatelessWidget {
  final int legendEntries;
  final double minValue;
  final double maxValue;
  final List<RgbColor> referenceColors;
  final int labelDecimals;
  final double boxSize;
  final double boxStrokeWidth;
  final Color? boxStrokeColor;
  final TextStyle? labelTextStyle;

  ColorLegend({
    required this.legendEntries,
    required this.minValue,
    required this.maxValue,
    required this.referenceColors,
    this.labelDecimals = 1,
    this.boxSize = 24,
    this.boxStrokeWidth = 1,
    this.boxStrokeColor,
    this.labelTextStyle,
  }) {
    if(legendEntries < 2) {
      throw ArgumentError("legendEntries must be at least 2");
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var stepSize = (maxValue - minValue) / (legendEntries - 1);
    Map<double, Color> colorMap = {};
    for(var i = 0; i < legendEntries; i++) {
      double value = minValue + (i * stepSize);
      colorMap[value] = lerpRgbColor(
        value: value,
        minValue: minValue,
        maxValue: maxValue,
        referenceColors: referenceColors,
      )!.toFlutterColor();
    }

    final boxStrokeColor = this.boxStrokeColor ?? Theme.of(context).colorScheme.onSurface;
    final labelTextStyle = this.labelTextStyle ?? Theme.of(context).textTheme.bodyMedium;
    final boxSize = this.boxSize * uiScaleFactor;
    final boxStrokeWidth = this.boxStrokeWidth * uiScaleFactor;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for(var entry in colorMap.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: entry.value,
                  border: Border.all(color: boxStrokeColor, width: boxStrokeWidth),
                ),
              ),
              SizedBox(width: 8 * uiScaleFactor),
              if(labelDecimals > 0) Text(entry.key.toStringAsFixed(labelDecimals), style: labelTextStyle),
              if(labelDecimals == 0) Text(entry.key.round().toString(), style: labelTextStyle),
            ],
          ),
        ],
    );
  }
}
