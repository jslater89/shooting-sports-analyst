import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/location_normalizer.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/ui/widget/custom_tooltip.dart';
import 'package:shooting_sports_analyst/ui/widget/interactive_svg.dart';
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

class USDataMap extends StatelessWidget {
  /// A map of state names to data values. Use the two-letter state code as the key.
  final Map<String, double> data;

  /// The colors to use for the map. If null, the default colors will be used.
  /// [rgbColors] takes precedence over [colors].
  final List<RgbColor>? rgbColors;

  /// The colors to use for the map. If null, the default colors will be used.
  /// [rgbColors] takes precedence over [colors].
  final List<Color>? colors;

  /// A function that returns the text to display in the tooltip when hovering
  /// over a state. The function is called with the two-letter state code as
  /// the argument.
  final Function(String?)? tooltipTextBuilder;

  /// The default width of the tooltip.
  final double tooltipWidth;

  /// The default height of the tooltip.
  final double tooltipHeight;

  /// The size multiplier to apply to the SVG, which will otherwise be sized
  /// to the size of the parent. Setting this allows for the use of e.g. InteractiveView
  /// to zoom/pan.
  final double sizeMultiplier;

  late final _tooltip = CustomTooltip<String>(
    child: Text(""), width: tooltipWidth, height: tooltipHeight);

  USDataMap({
    super.key, 
    required this.data, 
    this.rgbColors,
    this.colors,
    this.tooltipTextBuilder,
    this.tooltipWidth = 150,
    this.tooltipHeight = 24,
    this.sizeMultiplier = 1,
  });

  List<RgbColor> resolveColors() {
    if(rgbColors != null) {
      return rgbColors!;
    }
    if(colors != null) {
      return colors!.map((e) => e.toRgbColor()).toList();
    }
    return blueToYellowLerpReferenceColors;
  }

  static const svgAsset = "assets/images/us-states-map.svg";

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var size = MediaQuery.of(context).size;
    if(data.isEmpty) {
      return InteractiveSvg(
      assetPath: svgAsset,
      colorMapper: _StateColorMapper(context, {}),
      width: size.width * sizeMultiplier,
      height: size.height * sizeMultiplier,
    );
    }
    var minValue = data.values.min;
    var maxValue = data.values.max;
    var colors = resolveColors();
    Map<String, Color?> stateColors = {};
    for(var state in data.keys) {
      var value = data[state]!;
      var color = lerpRgbColor(
        value: value,
        minValue: minValue,
        maxValue: maxValue,
        referenceColors: colors,
      );
      stateColors[state] = color?.toFlutterColor();
    }
    var colorMapper = _StateColorMapper(context, stateColors);
    return InteractiveSvg(
      assetPath: svgAsset,
      colorMapper: colorMapper,
      width: size.width * sizeMultiplier,
      height: size.height * sizeMultiplier,
      onHover: tooltipTextBuilder == null ? null : (event, pathId) {
        _tooltip.onHover(event);
        if(pathId == null) {
          return;
        }
        var normalizedId = normalizeUSState(pathId);
        var tooltipText = tooltipTextBuilder?.call(normalizedId);
        if(tooltipText == null) {
          return;
        }
        _tooltip.insert(
          context: context,
          data: pathId,
          width: tooltipWidth * uiScaleFactor,
          height: tooltipHeight * uiScaleFactor,
          child: Text(tooltipText, style: TextStyles.tooltipText(context)),
        );
      },
      onExit: tooltipTextBuilder == null ? null : (event, pathId) {
        _tooltip.remove(context);
      },
    );
  }
}

class _StateColorMapper extends ColorMapper {
  final BuildContext context;
  final Map<String, Color?> _stateColors;

  _StateColorMapper(this.context, this._stateColors);

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) {
    if(id == null) {
      if(Theme.of(context).brightness == Brightness.light) {
        // invert some borders/dividers for light mode
        if(color.toHex().toLowerCase() == "#ffffff") {
          return Colors.black;
        }
        else if(color.toHex().toLowerCase() == "#b0b0b0") {         
          return Color.fromARGB(255, 0x50, 0x50, 0x50);
        }
      }
      return color;
    }
    var normalizedId = normalizeUSState(id);
    var stateColor = _stateColors[normalizedId];
    return stateColor ?? color;
  }
  
}