import 'dart:math';

import 'package:collection/collection.dart';
import 'package:color_models/color_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/db_oneoffs.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:community_charts_common/community_charts_common.dart' as common;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchHeatGraphPage");

class MatchHeatGraphPage extends StatefulWidget {
  const MatchHeatGraphPage({super.key});

  @override
  State<MatchHeatGraphPage> createState() => _MatchHeatGraphPageState();
}

class _MatchHeatGraphPageState extends State<MatchHeatGraphPage> {

  @override
  void initState() {
    _startCalculation();
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  Map<MatchPointer, MatchHeat> _matchHeat = {};
  double _minY = 1000;
  double _maxY = 2000;
  DbRatingProject? _project;
  Map<Classification, double> _classStrengths = {};
  TextEditingController _searchController = TextEditingController();
  List<MatchPointer> _highlightedMatches = [];

  void _startCalculation() async {
    var db = AnalystDatabase();
    _project = (await db.getRatingProjectByName("L2s Main"))!;

    for(var c in _project!.sport.classifications.values) {
      _classStrengths[c] = _project!.sport.ratingStrengthProvider!.strengthForClass(c);
    }

    _rebuildChart();

    var matchHeat = await calculateMatchHeat(db, _project!, heatCallback: _heatCallback);
    setStateIfMounted(() {
      _matchHeat = matchHeat;
    });
  }

  void _heatCallback(MatchPointer ptr, MatchHeat heat) {
    setStateIfMounted(() {
      _matchHeat[ptr] = heat;
      _minY = min(_minY, heat.topTenPercentAverageRating);
      _maxY = max(_maxY, heat.topTenPercentAverageRating);
      _rebuildChart();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          child: const Text("Match Heat"),
          onTap: () {
            _rebuildChart();
          }
        ),
      ),
      body: _chartWidget != null ? Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search",
                    ),
                    onSubmitted: (value) {
                      _search(value);
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _search(_searchController.text);
                  },
                  icon: Icon(Icons.search),
                ),
                IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _highlightedMatches = [];
                    setState(() {
                      _rebuildChart();
                    });
                  },
                  icon: Icon(Icons.clear),
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

  void _search(String value) {
    for(var match in _matchHeat.keys) {
      if(match.name.toLowerCase().contains(_searchController.text.toLowerCase())) {
        _highlightedMatches.add(match);
      }
    }
    setState(() {
      _rebuildChart();
    });
  }

  Offset? _mousePosition;
  Widget? _chartWidget;
  charts.Series<MatchHeat, int>? _series;
  charts.ScatterPlotChart? _chart;
  void _rebuildSeries() {
    _series = charts.Series<MatchHeat, int>(
      id: "matchHeat",
      data: _matchHeat.values.toList(),
      domainFn: (MatchHeat heat, _) => heat.competitorCount,
      measureFn: (MatchHeat heat, _) => heat.topTenPercentAverageRating,
      radiusPxFn: (MatchHeat heat, _) {
        if(heat.medianRating < 800) {
          return 1;
        }
        else {
          return 1 + ((heat.medianRating - 800) / 50);
        }
      },
      colorFn: (MatchHeat heat, _) {
        if(_project == null || _project!.sport.ratingStrengthProvider == null) {
          return charts.MaterialPalette.blue.shadeDefault;
        }
        else {
          return _calculateStrengthColor(
            dimmed: _highlightedMatches.isNotEmpty && !_highlightedMatches.contains(heat.matchPointer),
            value: heat.classificationStrength,
            classStrengths: _classStrengths,
          ) ?? charts.MaterialPalette.blue.shadeDefault;
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
        charts.PanAndZoomBehavior(),
        charts.SelectNearest(
          eventTrigger: charts.SelectionTrigger.hover,
          selectionModelType: charts.SelectionModelType.info,
          maximumDomainDistancePx: 5,
        )
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
      ],
      animate: false,
      primaryMeasureAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(_minY, _maxY),
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
          top -= 100;
        }

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: 300,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
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
                        "${match.name}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Competitors: ${heat.competitorCount}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Top 10%: ${heat.topTenPercentAverageRating.round()}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Median: ${heat.medianRating.round()}",
                        style: TextStyles.tooltipText(context),
                      ),
                      Text(
                        "Classification: ${_calculateClassification(heat.classificationStrength)}",
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

  String _calculateClassification(double classificationStrength) {
    var above = _classStrengths.entries.lastWhereOrNull((e) => e.value > classificationStrength);
    var below = _classStrengths.entries.firstWhereOrNull((e) => e.value < classificationStrength);

    if(above != null && below != null) {
      var fromBelow = (classificationStrength - below.value) / (above.value - below.value);
      var fromBelowSteps = (fromBelow * 100).floor();
      if(fromBelowSteps > 50) {
        return "${above.key.shortDisplayName}-${100 - fromBelowSteps}%";
      }
      else {
        return "${below.key.shortDisplayName}+${fromBelowSteps}%";
      }
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

  charts.Color? _calculateStrengthColor({
    required double value,
    required Map<Classification, double> classStrengths,
    bool dimmed = false,
  }) {
    var above = classStrengths.entries.lastWhereOrNull((e) => e.value > value);
    var below = classStrengths.entries.firstWhereOrNull((e) => e.value < value);

    RgbColor? color;

    if(above != null && below != null) {
      var fromBelow = (value - below.value) / (above.value - below.value);
      var fromBelowSteps = (fromBelow * 10).floor();
      var colorAbove = above.key.color.toRgbColor();
      var colorBelow = below.key.color.toRgbColor();
      // 18 steps, including below and above, for 20
      var steps = colorBelow.lerpTo(colorAbove, 8);
      color = steps[fromBelowSteps];
    }
    else if(above != null) {
      color = above.key.color.toRgbColor();
    }
    else if(below != null) {
      color = below.key.color.toRgbColor();
    }

    double alpha = 0.75;
    if(dimmed) {
      color = color?.withChroma(color.chroma * 0.2);
      alpha = 0.1;
    }
    if(!dimmed && _highlightedMatches.isNotEmpty) {
      alpha = 0.9;
    }
    if(color != null) {
      return color.toChartsColor(alpha: alpha);
    }
    return null;
  }
}
