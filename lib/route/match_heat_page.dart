/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_heat_help.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
// import 'package:community_charts_common/community_charts_common.dart' as common;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_heat_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_pointer_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';
import 'package:shooting_sports_analyst/ui_util.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchHeatGraphPage");

class MatchHeatGraphPage extends StatefulWidget {
  MatchHeatGraphPage({super.key, required this.dataSource});

  final RatingDataSource dataSource;

  @override
  State<MatchHeatGraphPage> createState() => _MatchHeatGraphPageState();
}

class _MatchHeatGraphPageState extends State<MatchHeatGraphPage> {

  @override
  void initState() {
    _loadMatchHeat();
    super.initState();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  Map<MatchPointer, MatchHeat> _matchHeat = {};
  MatchHeatSettings _settings = MatchHeatSettings();
  int _minCompetitorCount = 2e32.toInt();
  int _maxCompetitorCount = 0;
  double _minTopRating = 2e32;
  double _maxTopRating = -2e32;
  double _minMedianRating = 2e32;
  double _maxMedianRating = -2e32;
  double _minY = 1200;
  double _maxY = 1800;
  double _minX = 0;
  double _maxX = 0;
  double _progress = 0;
  DbRatingProject? _project;
  Map<Classification, double> _classStrengths = {};
  double _minClassStrength = 2e32;
  double _maxClassStrength = -2e32;
  List<MatchPointer> _highlightedMatches = [];

  void _loadMatchHeat() async {
    var db = AnalystDatabase();
    var projectId = await widget.dataSource.getProjectId();
    if(projectId.isErr()) {
      _log.w("Error getting project ID: ${projectId.unwrapErr()}");
      return;
    }
    _project = await db.getRatingProjectById(projectId.unwrap());
    if(_project == null) {
      _log.w("Rating project not found: ${projectId.unwrap()}");
      return;
    }

    var sport = _project!.sport;

    for(var c in sport.classifications.values) {
      _classStrengths[c] = sport.ratingStrengthProvider!.strengthForClass(c);
    }

    _rebuildChart();

    var precalculatedHeat = await db.getMatchHeatForProject(_project!.id);
    for(var heat in precalculatedHeat) {
      _matchHeat[heat.matchPointer] = heat;
    }

    List<MatchPointer> missingMatches = [];
    for(var ptr in _project!.matchPointers) {
      if(!_matchHeat.containsKey(ptr)) {
        missingMatches.add(ptr);
      }
    }

    if(missingMatches.isNotEmpty) {
      setStateIfMounted(() {
        _progress = 0;
      });
    }
    else {
      _recalculateSizes();
      setStateIfMounted(() {
        _progress = 1;
        _rebuildChart();
      });
    }

    bool updatedDuringMissingMatches = false;
    for(var (i, ptr) in missingMatches.indexed) {
      var matchHeat = await db.calculateHeatForMatch(_project!.id, ptr);
      if(matchHeat != null) {
        _matchHeat[ptr] = matchHeat;
        db.saveMatchHeat(matchHeat);
        _recalculateSizes();
        _rebuildChart();
        updatedDuringMissingMatches = true;
      }
      setStateIfMounted(() {
        _progress = (i + 1) / missingMatches.length;
      });
    }
    if(!updatedDuringMissingMatches) {
      _recalculateSizes();
      setStateIfMounted(() {
        _rebuildChart();
      });
    }
  }

  void _recalculateSizes() {
    _minY = 2e32;
    _maxY = -2e32;
    _minX = 2e32;
    _maxX = -2e32;
    _minClassStrength = 2e32;
    _maxClassStrength = -2e32;
    _minCompetitorCount = 2e32.toInt();
    _maxCompetitorCount = 0.toInt();
    _minTopRating = 2e32;
    _maxTopRating = -2e32;
    _minMedianRating = 2e32;
    _maxMedianRating = -2e32;
    var yMinOffset = switch(_settings.yAxis) {
        MatchHeatValue.matchSize => 0,
        MatchHeatValue.topTenPercentAverageRating => 100,
        MatchHeatValue.medianRating => 100,
        MatchHeatValue.averageClassification => 0,
      };
      var yMaxOffset = switch(_settings.yAxis) {
        MatchHeatValue.matchSize => 10,
        MatchHeatValue.topTenPercentAverageRating => 100,
        MatchHeatValue.medianRating => 100,
        MatchHeatValue.averageClassification => 0.5,
      };
      var xMinOffset = switch(_settings.xAxis) {
        MatchHeatValue.matchSize => 0,
        MatchHeatValue.topTenPercentAverageRating => 100,
        MatchHeatValue.medianRating => 100,
        MatchHeatValue.averageClassification => 0,
      };
      var xMaxOffset = switch(_settings.xAxis) {
        MatchHeatValue.matchSize => 10,
        MatchHeatValue.topTenPercentAverageRating => 100,
        MatchHeatValue.medianRating => 100,
        MatchHeatValue.averageClassification => 0.5,
      };

      if(_settings.yAxis == MatchHeatValue.averageClassification || _settings.yAxis == MatchHeatValue.matchSize) {
        _minY = 1;
      }
      else if(_settings.xAxis == MatchHeatValue.averageClassification || _settings.xAxis == MatchHeatValue.matchSize) {
        _minX = 1;
      }
    for(var heat in _matchHeat.values) {
      var yValue = switch(_settings.yAxis) {
        MatchHeatValue.matchSize => heat.rawCompetitorCount,
        MatchHeatValue.topTenPercentAverageRating => heat.weightedTopTenPercentAverageRating,
        MatchHeatValue.medianRating => heat.weightedMedianRating,
        MatchHeatValue.averageClassification => heat.weightedClassificationStrength,
      };
      var xValue = switch(_settings.xAxis) {
        MatchHeatValue.matchSize => heat.rawCompetitorCount,
        MatchHeatValue.topTenPercentAverageRating => heat.weightedTopTenPercentAverageRating,
        MatchHeatValue.medianRating => heat.weightedMedianRating,
        MatchHeatValue.averageClassification => heat.weightedClassificationStrength,
      };

      _minY = min(_minY, (yValue - yMinOffset).toDouble());
      _maxY = max(_maxY, (yValue + yMaxOffset).toDouble());
      _minX = min(_minX, (xValue - xMinOffset).toDouble());
      _maxX = max(_maxX, (xValue + xMaxOffset).toDouble());
      _minClassStrength = min(_minClassStrength, heat.weightedClassificationStrength);
      _maxClassStrength = max(_maxClassStrength, heat.weightedClassificationStrength);
      _minCompetitorCount = min(_minCompetitorCount, heat.rawCompetitorCount);
      _maxCompetitorCount = max(_maxCompetitorCount, heat.rawCompetitorCount);
      _minTopRating = min(_minTopRating, heat.weightedTopTenPercentAverageRating);
      _maxTopRating = max(_maxTopRating, heat.weightedTopTenPercentAverageRating);
      _minMedianRating = min(_minMedianRating, heat.weightedMedianRating);
      _maxMedianRating = max(_maxMedianRating, heat.weightedMedianRating);
    }

    setStateIfMounted(() {});
  }

  @override
  Widget build(BuildContext context) {
    String displaySettingsTooltip = "Display settings\nDot size: ${_settings.dotSize.axisLabel.toLowerCase()}\nDot color: ${_settings.dotColor.axisLabel.toLowerCase()}";
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          child: const Text("Match Heat"),
          onTap: () {
            _recalculateSizes();
            _rebuildChart();
          }
        ),
        actions: [
          IconButton(
            onPressed: () async {
              var confirmed = await ConfirmDialog.show(
                context,
                title: "Refresh",
                content: Text("Are you sure you want to fully recalculate match heat?"),
                positiveButtonLabel: "RECALCULATE",
                negativeButtonLabel: "CANCEL",
              );
              if(confirmed == true) {
                _matchHeat = {};
                await AnalystDatabase().deleteMatchHeatForProject(_project!.id);
                setState(() {
                  _progress = 0;
                });
                _loadMatchHeat();
              }
            },
            icon: Icon(Icons.refresh),
          ),
          HelpButton(helpTopicId: matchHeatHelpId),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _progress,
          ),
        ),
      ),
      body: _chartWidget != null ? Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: displaySettingsTooltip,
                  child: IconButton(
                    onPressed: () async {
                      var newSettings = await MatchHeatSettingsDialog.show(context: context, settings: _settings);
                      if(newSettings != null) {
                        setState(() {
                          _settings = newSettings;
                        });
                        _recalculateSizes();
                        _rebuildChart();
                      }
                    },
                    icon: Icon(Icons.settings),
                  ),
                ),
                Tooltip(
                  message: "Highlight matches",
                  child: IconButton(
                    onPressed: () async {
                      var pointers = await MatchPointerChooserDialog.showMultiple(context: context, matches: _project!.matchPointers);
                      if(pointers != null) {
                        _highlightedMatches = pointers;
                        setState(() {
                          _rebuildChart();
                        });
                      }
                    },
                    icon: Icon(Icons.filter_list),
                  ),
                ),
                Tooltip(
                  message: "Clear all searches",
                  child: IconButton(
                    onPressed: () {
                      _highlightedMatches = [];
                      setState(() {
                        _rebuildChart();
                      });
                    },
                    icon: Icon(Icons.clear),
                  ),
                ),
                if(_highlightedMatches.isNotEmpty)
                  SizedBox(width: 10),
                if(_highlightedMatches.isNotEmpty)
                  Tooltip(
                    message: _calculateAverageHighlightedHeat(),
                    child: Text("${_highlightedMatches.length} results")
                  ),
              ],
            ),
            SizedBox(height: 10),
            Expanded(child: _chartWidget!),
          ],
        ),
      ) : Container(),
    );
  }

  bool get hasHighlighting => _highlightedMatches.isNotEmpty;

  bool _isHighlighted(MatchPointer match) {
    if(_highlightedMatches.isNotEmpty) {
      return _highlightedMatches.contains(match);
    }
    // If nothing is highlighted, everything is
    return true;
  }

  Offset? _mousePosition;
  Widget? _chartWidget;
  charts.Series<MatchHeat, num>? _series;
  charts.ScatterPlotChart? _chart;

  void _rebuildSeries() {
    _series = charts.Series<MatchHeat, num>(
      id: "matchHeat",
      data: _matchHeat.values.toList(),
      domainFn: (MatchHeat heat, _) => switch(_settings.xAxis) {
        MatchHeatValue.matchSize => heat.rawCompetitorCount,
        MatchHeatValue.topTenPercentAverageRating => heat.weightedTopTenPercentAverageRating,
        MatchHeatValue.medianRating => heat.weightedMedianRating,
        MatchHeatValue.averageClassification => heat.weightedClassificationStrength,
      },
      measureFn: (MatchHeat heat, _) => switch(_settings.yAxis) {
        MatchHeatValue.matchSize => heat.rawCompetitorCount,
        MatchHeatValue.topTenPercentAverageRating => heat.weightedTopTenPercentAverageRating,
        MatchHeatValue.medianRating => heat.weightedMedianRating,
        MatchHeatValue.averageClassification => heat.weightedClassificationStrength,
      },
      radiusPxFn: (MatchHeat heat, _) {
        if(_settings.dotSize == MatchHeatValue.matchSize) {
          if(heat.rawCompetitorCount < 50) {
            return 1;
          }
          else {
            return 1 + ((heat.rawCompetitorCount - 50) / 50);
          }
        }
        else if(_settings.dotSize == MatchHeatValue.topTenPercentAverageRating) {
          if(heat.weightedMedianRating < 1200) {
            return 1;
          }
          else {
            return 1 + ((heat.weightedMedianRating - 1200) / 50);
          }
        }
        else if(_settings.dotSize == MatchHeatValue.medianRating) {
          if(heat.weightedMedianRating < 800) {
            return 1;
          }
          else {
            return 1 + ((heat.weightedMedianRating - 800) / 40);
          }
        }
        else if(_settings.dotSize == MatchHeatValue.averageClassification) {
          var range = _maxClassStrength - _minClassStrength;
          // Bottom 10% of the range is 1 pixel
          if(heat.weightedClassificationStrength <= _minClassStrength + (range * 0.1)) {
            return 1;
          }
          else {
            // Scale up from 1 pixel to 10 pixels, with 10 pixels being the strongest classification strength/*  */
            return 1 + ((heat.weightedClassificationStrength - (_minClassStrength + (range * 0.1))) / (range * 0.8) * 9);
          }
        }
        else {
          return 1;
        }
      },
      colorFn: (MatchHeat heat, _) {
        if(_project!.sport.ratingStrengthProvider == null) {
          return charts.MaterialPalette.blue.shadeDefault;
        }
        else {
          if(_settings.dotColor == MatchHeatValue.averageClassification) {
            return _calculateStrengthColor(
              dimmed: !_isHighlighted(heat.matchPointer),
              value: heat.weightedClassificationStrength,
              classStrengths: _classStrengths,
            ) ?? charts.MaterialPalette.blue.shadeDefault;
          }
          else if(_settings.dotColor == MatchHeatValue.matchSize) {
            return _calculateLerpColor(
              value: heat.rawCompetitorCount.toDouble(),
              minValue: _minCompetitorCount.toDouble(),
              maxValue: _maxCompetitorCount.toDouble(),
              dimmed: !_isHighlighted(heat.matchPointer),
            ) ?? charts.MaterialPalette.blue.shadeDefault;
          }
          else if(_settings.dotColor == MatchHeatValue.topTenPercentAverageRating) {
            return _calculateLerpColor(
              value: heat.weightedTopTenPercentAverageRating.toDouble(),
              minValue: _minTopRating.toDouble(),
              maxValue: _maxTopRating.toDouble(),
              dimmed: !_isHighlighted(heat.matchPointer),
            ) ?? charts.MaterialPalette.blue.shadeDefault;
          }
          else if(_settings.dotColor == MatchHeatValue.medianRating) {
            return _calculateLerpColor(
              value: heat.weightedMedianRating.toDouble(),
              minValue: _minMedianRating.toDouble(),
              maxValue: _maxMedianRating.toDouble(),
              dimmed: !_isHighlighted(heat.matchPointer),
            ) ?? charts.MaterialPalette.blue.shadeDefault;
          }
          else {
            return charts.MaterialPalette.blue.shadeDefault;
          }
        }
      }
    );
  }

  void _rebuildChart() {
    _rebuildSeries();
    _chart = charts.ScatterPlotChart(
      [
        _series!
      ],
      behaviors: [
        // charts.PanAndZoomBehavior(),
        charts.SelectNearest(
          eventTrigger: charts.SelectionTrigger.hover,
          selectionModelType: charts.SelectionModelType.info,
          maximumDomainDistancePx: 5,
        ),
        charts.SelectNearest(
          eventTrigger: charts.SelectionTrigger.tap,
          selectionModelType: charts.SelectionModelType.action,
          maximumDomainDistancePx: 5,
        ),
        charts.ChartTitle(
          _settings.yAxis.axisLabel,
          behaviorPosition: charts.BehaviorPosition.start,
          titleStyleSpec: charts.TextStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
          ),
        ),
        charts.ChartTitle(
          _settings.xAxis.axisLabel,
          behaviorPosition: charts.BehaviorPosition.bottom,
          titleStyleSpec: charts.TextStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
          ),
        ),
      ],
      selectionModels: [
        charts.SelectionModelConfig(
          type: charts.SelectionModelType.info,
          changedListener: (model) {
            if(model.hasDatumSelection) {
              var index = model.selectedDatum[0].index!;
              var match = _matchHeat.keys.toList()[index];
              var heat = _matchHeat[match]!;
              _addOverlay(match, heat);
            }
            else {
              _removeOverlay();
            }
          },
        ),
        charts.SelectionModelConfig(
          type: charts.SelectionModelType.action,
          changedListener: (model) async {
            if(model.hasDatumSelection)  {
              _removeOverlay();
              var index = model.selectedDatum[0].index!;
              var pointer = _matchHeat.keys.toList()[index];
              var dbMatch = await AnalystDatabase().getMatchByAnySourceId(pointer.sourceIds);
              if(dbMatch != null) {
                var matchRes = await dbMatch.hydrate(useCache: true);
                if(matchRes.isOk()) {
                  var match = matchRes.unwrap();
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ResultPage(
                    canonicalMatch: match,
                    ratings: _project
                  )));
                }
              }
            }
          },
        ),
      ],
      animate: false,
      primaryMeasureAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(_minY, _maxY),
        renderSpec: charts.GridlineRendererSpec(
          labelStyle: charts.TextStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
          ),
          axisLineStyle: charts.LineStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
            thickness: 1,
          ),
          lineStyle: charts.LineStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
            thickness: 1,
          ),
        ),
      ),
      domainAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(_minX, _maxX),
        renderSpec: charts.GridlineRendererSpec(
          labelStyle: charts.TextStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
          ),
          axisLineStyle: charts.LineStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
            thickness: 1,
          ),
          lineStyle: charts.LineStyleSpec(
            color: charts.Color.fromHex(code: ThemeColors.onBackgroundColorFaded(context).toHex()),
            thickness: 1,
          ),
        ),
      ),
    );
    _chartWidget = MouseRegion(
      onHover: (event) {
        _mousePosition = event.localPosition;
      },
      child: _chart,
    );
    setState(() {});
  }

  OverlayEntry? _overlayEntry;
  MatchPointer? _overlayMatch;
  void _addOverlay(MatchPointer match, MatchHeat heat) {
    // Don't shuffle the overlay if the same match is selected
    if(_overlayEntry != null && _overlayMatch == match) {
      return;
    }

    // If there is highlighting going on, only show overlays for highlighted matches
    if(hasHighlighting && !_highlightedMatches.contains(match)) {
      return;
    }

    // remove any existing overlay if we're changing matches
    _removeOverlay();

    _overlayMatch = match;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        var windowSize = MediaQuery.of(context).size;
        var mousePosition = _mousePosition;
        if(mousePosition == null) {
          mousePosition = Offset(0, 0);
        }
        var left = 25 + mousePosition.dx;
        var top = 25 + mousePosition.dy;
        if(left + 350 > windowSize.width) {
          // flip sides when close to the right
          left -= 350;
        }
        if(top + 200 > windowSize.height) {
          // move up when close to the bottom
          top -= 100;
        }

        var finalBackgroundColor = ThemeColors.onBackgroundColor(context);

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: 300,
                decoration: BoxDecoration(
                  color: finalBackgroundColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: EdgeInsets.all(8),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${match.name} (${programmerYmdFormat.format(match.date ?? DateTime(0))})",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Competitors: ${heat.rawCompetitorCount}${heat.usedCompetitorCount != heat.rawCompetitorCount ? " (${heat.usedCompetitorCount})" : ""}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Top 10%: ${heat.weightedTopTenPercentAverageRating.round()}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Median: ${heat.weightedMedianRating.round()}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Classification: ${_calculateClassificationLabel(heat.weightedClassificationStrength)}",
                        style: TextStyles.tooltipText(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  String _calculateClassificationLabel(double classificationStrength) {
    var above = _classStrengths.entries.lastWhereOrNull((e) => e.value > classificationStrength);
    var below = _classStrengths.entries.firstWhereOrNull((e) => e.value < classificationStrength);

    if(above != null && below != null) {
      var fromBelow = (classificationStrength - below.value) / (above.value - below.value);
      var fromBelowSteps = (fromBelow * 100).floor();
      return "${below.key.shortDisplayName}+${fromBelowSteps}%";
    }
    else if(above != null) {
      return above.key.shortDisplayName;
    }
    else if(below != null) {
      return below.key.shortDisplayName;
    }
    return "?";
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlayMatch = null;
  }

  final _referenceColors = [
      Color.fromARGB(0xff, 0x09, 0x1f, 0x92).toRgbColor(),
      Colors.blue.toRgbColor(),
      Colors.green.toRgbColor(),
      Colors.yellow.toRgbColor(),
      Colors.orange.toRgbColor(),
      Colors.red.toRgbColor(),
    ];

  charts.Color? _calculateLerpColor({
    required double value,
    required double minValue,
    required double maxValue,
    bool dimmed = false,
  }) {

    final stepsPerColor = 100 ~/ _referenceColors.length;
    List<RgbColor> dotColorRange = [];
    for(var i = 1; i < _referenceColors.length; i++) {
      // For each color, add a range of stepsPerColor steps
      dotColorRange.addAll(_referenceColors[i - 1].lerpTo(_referenceColors[i], stepsPerColor));
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

    double alpha = 0.75;
    var isDark = Theme.of(context).brightness == Brightness.dark;
    if(dimmed) {
      color = color?.withChroma(color.chroma * 0.2);
      alpha = isDark ? 0.25 : 0.1;
    }
    if(!dimmed && _highlightedMatches.isNotEmpty) {
      alpha = 0.9;
    }
    if(color != null) {
      return color.toChartsColor(alpha: alpha);
    }
    return null;
  }

  charts.Color? _calculateStrengthColor({
    required double value,
    required Map<Classification, double> classStrengths,
    bool dimmed = false,
  }) {

    final stepsPerColor = 100 ~/ _referenceColors.length;
    List<RgbColor> dotColorRange = [];
    for(var i = 1; i < _referenceColors.length; i++) {
      // For each color, add a range of stepsPerColor steps
      dotColorRange.addAll(_referenceColors[i - 1].lerpTo(_referenceColors[i], stepsPerColor));
    }
    var colorCount = dotColorRange.length;

    RgbColor? color;

    if(_minClassStrength == _maxClassStrength) {
      color = dotColorRange[colorCount ~/ 2];
    }
    else if(value > _minClassStrength && value < _maxClassStrength) {
      var fromBelow = (value - _minClassStrength) / (_maxClassStrength - _minClassStrength);
      var fromBelowSteps = (fromBelow * colorCount).floor();
      color = dotColorRange[fromBelowSteps];
    }
    else if(value <= _minClassStrength) {
      color = dotColorRange.first;
    }
    else if(value >= _maxClassStrength) {
      color = dotColorRange.last;
    }

    double alpha = 0.75;
    var isDark = Theme.of(context).brightness == Brightness.dark;
    if(dimmed) {
      color = color?.withChroma(color.chroma * 0.2);
      alpha = isDark ? 0.25 : 0.1;
    }
    if(!dimmed && _highlightedMatches.isNotEmpty) {
      alpha = 0.9;
    }
    if(color != null) {
      return color.toChartsColor(alpha: alpha);
    }
    return null;
  }

  String _calculateAverageHighlightedHeat() {
    var totalMatches = 0;
    MatchHeat total = MatchHeat(
      projectId: _project!.id,
      matchPointer: MatchPointer(),
      topTenPercentAverageRating: 0,
      weightedTopTenPercentAverageRating: 0,
      medianRating: 0,
      weightedMedianRating: 0,
      classificationStrength: 0,
      weightedClassificationStrength: 0,
      ratedCompetitorCount: 0,
      unratedCompetitorCount: 0,
      rawCompetitorCount: 0,
    );

    for(var match in _highlightedMatches) {
      var heat = _matchHeat[match];
      if(heat == null) {
        _log.d("No heat found for match: ${match.name}");
        continue;
      }
      total.topTenPercentAverageRating += heat.topTenPercentAverageRating;
      total.weightedTopTenPercentAverageRating += heat.weightedTopTenPercentAverageRating;
      total.medianRating += heat.medianRating;
      total.weightedMedianRating += heat.weightedMedianRating;
      total.classificationStrength += heat.classificationStrength;
      total.weightedClassificationStrength += heat.weightedClassificationStrength;
      total.ratedCompetitorCount += heat.ratedCompetitorCount;
      total.unratedCompetitorCount += heat.unratedCompetitorCount;
      total.rawCompetitorCount += heat.rawCompetitorCount;
      totalMatches++;
    }

    if(totalMatches == 0) {
      return "No matches with heat found";
    }

    total.topTenPercentAverageRating /= totalMatches;
    total.weightedTopTenPercentAverageRating /= totalMatches;
    total.medianRating /= totalMatches;
    total.weightedMedianRating /= totalMatches;
    total.classificationStrength /= totalMatches;
    total.weightedClassificationStrength /= totalMatches;
    total.ratedCompetitorCount = total.ratedCompetitorCount ~/ totalMatches;
    total.unratedCompetitorCount = total.unratedCompetitorCount ~/ totalMatches;
    total.rawCompetitorCount = total.rawCompetitorCount ~/ totalMatches;

    return "Top 10%: ${total.weightedTopTenPercentAverageRating.round()}\n"
        "Median: ${total.weightedMedianRating.round()}\n"
        "Classification: ${_calculateClassificationLabel(total.weightedClassificationStrength)}\n"
        "Competitors: ${total.rawCompetitorCount}${total.usedCompetitorCount != total.rawCompetitorCount ? " (${total.usedCompetitorCount})" : ""}";
  }
}
