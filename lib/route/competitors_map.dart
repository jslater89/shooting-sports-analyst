/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';
import 'package:shooting_sports_analyst/ui/widget/color_legend.dart';
import 'package:shooting_sports_analyst/ui/widget/us_data_map.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

class CompetitorMap extends StatefulWidget {
  const CompetitorMap({super.key, required this.title, required this.data});

  final String title;
  final Map<String, double> data;

  @override
  State<CompetitorMap> createState() => _CompetitorMapState();
}

class _CompetitorMapState extends State<CompetitorMap> {

  List<RgbColor> get _referenceColors => _colorScheme.referenceColors;
  LerpColorScheme _colorScheme = LerpColorScheme.thermal;

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return EmptyScaffold(
      title: widget.title,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          spacing: 8 * uiScaleFactor,
          children: [
            DropdownMenu<LerpColorScheme>(
              initialSelection: _colorScheme,
              label: Text("Color scheme"),
              dropdownMenuEntries: LerpColorScheme.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
              onSelected: (value) {
                if(value != null) {
                  _colorScheme = value;
                  setState(() {});
                }
              },
            ),
            ColorLegend(
              legendEntries: 10,
              minValue: widget.data.values.min,
              maxValue: widget.data.values.max,
              referenceColors: _referenceColors,
              labelDecimals: 0,
            ),
            Expanded(
              child: USDataMap(
                data: widget.data,
                rgbColors: _referenceColors,
                tooltipTextBuilder: (state) => "${state}: ${(widget.data[state] ?? 0).round()} competitors",
              ),
            ),
          ],
        ),
      ),
    );
  }
}