/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:color_models/color_models.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts show Color;
import 'package:flutter/material.dart';

extension SetStateIfMounted<T extends StatefulWidget> on State<T> {
  void setStateIfMounted(VoidCallback fn) {
    if(mounted) {
      // ignore: invalid_use_of_protected_member
      setState(fn);
    }
  }
}

enum LerpColorScheme {
  rainbow,
  blueToRed,
  grayscale,
  thermal,
  hotMetal,
  blueToYellow;

  String get uiLabel => switch(this) {
    rainbow => "Rainbow",
    blueToRed => "Blue to red",
    grayscale => "Grayscale",
    thermal => "Thermal",
    hotMetal => "Hot metal",
    blueToYellow => "Blue to yellow",
  };

  List<RgbColor> get referenceColors => switch(this) {
    rainbow => rainbowLerpReferenceColors,
    blueToRed => blueToRedLerpReferenceColors,
    grayscale => grayscaleLerpReferenceColors,
    thermal => thermalLerpReferenceColors,
    hotMetal => hotMetalLerpReferenceColors,
    blueToYellow => blueToYellowLerpReferenceColors,
  };
}

final rainbowLerpReferenceColors = [
  Color.fromARGB(0xff, 0x09, 0x1f, 0x92).toRgbColor(),
  Colors.blue.toRgbColor(),
  Colors.green.toRgbColor(),
  Colors.yellow.toRgbColor(),
  Colors.orange.toRgbColor(),
  Colors.red.toRgbColor(),
];

final hotMetalLerpReferenceColors = [
  RgbColor.fromHex("#50353a"),
  RgbColor.fromHex("#923436"),
  RgbColor.fromHex("#dd3c3a"),
  RgbColor.fromHex("#fc6b3c"),
  RgbColor.fromHex("#fe9733"),
  RgbColor.fromHex("#ffc872"),
  RgbColor.fromHex("#f8e3c3"),
];

final blueToRedLerpReferenceColors = [
  Color.fromARGB(200, 0, 0, 187).toRgbColor(),
  Color.fromARGB(239, 207, 0, 0).toRgbColor(),
];

final grayscaleLerpReferenceColors = [
  Color.fromARGB(255, 0, 0, 0).toRgbColor(),
  Color.fromARGB(255, 255, 255, 255).toRgbColor(),
];

final thermalLerpReferenceColors = [
  RgbColor.fromHex("#003f5c"),
  RgbColor.fromHex("#394871"),
  RgbColor.fromHex("#644e81"),
  RgbColor.fromHex("#8f518b"),
  RgbColor.fromHex("#bb5090"),
  RgbColor.fromHex("#db5c79"),
  RgbColor.fromHex("#f07060"),
  RgbColor.fromHex("#fc8942"),
  RgbColor.fromHex("#ffa600"),
];

final blueToYellowLerpReferenceColors = [
  RgbColor.fromHex("#00429d"),
  RgbColor.fromHex("#2e59a8"),
  RgbColor.fromHex("#4771b2"),
  RgbColor.fromHex("#5d8abd"),
  RgbColor.fromHex("#73a2c6"),
  RgbColor.fromHex("#8abccf"),
  RgbColor.fromHex("#a5d5d8"),
  RgbColor.fromHex("#c5eddf"),
  RgbColor.fromHex("#ffffe0"),
];

RgbColor? lerpRgbColor({
  required double value,
  required double minValue,
  required double maxValue,
  bool isDark = false,
  bool dimmed = false,
  List<RgbColor>? referenceColors,
}) {
  final colors = referenceColors ?? rainbowLerpReferenceColors;
  final stepsPerColor = 100 ~/ colors.length;
  List<RgbColor> dotColorRange = [];
  for(var i = 1; i < colors.length; i++) {
    // For each color, add a range of stepsPerColor steps
    dotColorRange.addAll(colors[i - 1].lerpTo(colors[i], stepsPerColor));
  }
  var colorCount = dotColorRange.length;

  List<double> rangeSteps = [];
  for(var i = 0; i < colorCount; i++) {
    rangeSteps.add(minValue + (i * ((maxValue - minValue) / colorCount)));
  }

  RgbColor? color;
  if(minValue == maxValue) {
    color = dotColorRange[colorCount ~/ 2];
  }
  else if(value > minValue && value < maxValue) {
    var fromBelow = (value - minValue) / (maxValue - minValue);
    var fromBelowSteps = (fromBelow * colorCount).floor();
    color = dotColorRange[fromBelowSteps];
  }
  else if(value <= minValue) {
    color = dotColorRange.first;
  }
  else if(value >= maxValue) {
    color = dotColorRange.last;
  }

  if(dimmed) {
    color = color?.withChroma(color.chroma * 0.2);
  }

  return color;
}

Color? lerpColor({
  required double value,
  required double minValue,
  required double maxValue,
  bool isDark = false,
  bool dimmed = false,
  List<Color>? referenceColors,
}) {
  var color = lerpRgbColor(value: value, minValue: minValue, maxValue: maxValue, isDark: isDark, dimmed: dimmed, referenceColors: referenceColors?.map((e) => e.toRgbColor()).toList());
  return color?.toFlutterColor();
}


extension FlutterColorConverters on Color {
  charts.Color toChartsColor() {
    return charts.Color(r: red, g: green, b: blue);
  }

  RgbColor toRgbColor() {
    return RgbColor(red, green, blue);
  }

  String toHex() {
    return '#${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}';
  }
}

extension RgbColorConverters on RgbColor {
  charts.Color toChartsColor({double? alpha}) {
    return charts.Color(r: red, g: green, b: blue, a: alpha != null ? (alpha * 255).toInt() : 255);
  }

  Color toFlutterColor() {
    return Color.fromARGB(alpha, red, green, blue);
  }
}