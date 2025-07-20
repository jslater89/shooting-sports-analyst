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
import 'package:shooting_sports_analyst/data/help/match_heat_help.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/db_oneoffs.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
// import 'package:community_charts_common/community_charts_common.dart' as common;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/stacked_distribution_chart.dart';
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
    _searchController.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  Map<MatchPointer, MatchHeat> _matchHeat = {};
  double _minY = 1200;
  double _maxY = 1800;
  double _minX = 0;
  double _maxX = 0;
  double _progress = 0;
  DbRatingProject? _project;
  bool _loadError = false;
  Map<Classification, double> _classStrengths = {};
  double _minClassStrength = 2e32;
  double _maxClassStrength = -2e32;
  TextEditingController _searchController = TextEditingController();
  List<MatchPointer> _highlightedMatches = [];
  List<MatchPointer> _excludedMatches = [];
  List<String> _searchTerms = [];

  void _loadMatchHeat() async {
    var db = AnalystDatabase();
    var projectId = await widget.dataSource.getProjectId();
    if(projectId.isErr()) {
      _log.w("Error getting project ID: ${projectId.unwrapErr()}");
      setState(() {
        _loadError = true;
      });
      return;
    }
    _project = await db.getRatingProjectById(projectId.unwrap());
    if(_project == null) {
      _log.w("Rating project not found: ${projectId.unwrap()}");
      setState(() {
        _loadError = true;
      });
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

    for(var (i, ptr) in missingMatches.indexed) {
      var matchHeat = await db.calculateHeatForMatch(_project!.id, ptr);
      if(matchHeat != null) {
        _matchHeat[ptr] = matchHeat;
        db.saveMatchHeat(matchHeat);
      }
      _recalculateSizes();
      setStateIfMounted(() {
        _progress = (i + 1) / missingMatches.length;
        _rebuildChart();
      });
    }

  }

  void _recalculateSizes() {
    _minY = 2e32;
    _maxY = -2e32;
    _minX = 0;
    _maxX = 0;
    _minClassStrength = 2e32;
    _maxClassStrength = -2e32;
    for(var heat in _matchHeat.values) {
      _minY = min(_minY, heat.weightedTopTenPercentAverageRating - 100);
      _maxY = max(_maxY, heat.weightedTopTenPercentAverageRating + 100);
      _maxX = max(_maxX, heat.rawCompetitorCount + 10);
      _minClassStrength = min(_minClassStrength, heat.weightedClassificationStrength);
      _maxClassStrength = max(_maxClassStrength, heat.weightedClassificationStrength);
    }

    setStateIfMounted(() {});
  }

  @override
  Widget build(BuildContext context) {
    var searchedResults = _highlightedMatches.whereNot((e) => _excludedMatches.contains(e)).length;
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
                Tooltip(
                  message: "Clear all searches",
                  child: IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _searchTerms = [];
                      _highlightedMatches = [];
                      _excludedMatches = [];
                      setState(() {
                        _rebuildChart();
                      });
                    },
                    icon: Icon(Icons.clear),
                  ),
                ),
                if(_highlightedMatches.isNotEmpty)
                  Tooltip(
                    message: "Searched for:\n${_searchTerms.join("\n")}",
                    child: Text("${_searchTerms.length} search term${_searchTerms.length == 1 ? "" : "s"}")
                  ),
                if(_highlightedMatches.isNotEmpty)
                  SizedBox(width: 10),
                if(_highlightedMatches.isNotEmpty)
                  Tooltip(
                    message: _calculateAverageHighlightedHeat(),
                    child: Text("$searchedResults results")
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
    bool exclude = false;
    if(value.startsWith("-")) {
      exclude = true;
      value = value.substring(1);
    }
    for(var match in _matchHeat.keys) {
      if(match.name.toLowerCase().contains(value.toLowerCase())) {
        if(exclude) {
          _excludedMatches.add(match);
        }
        else {
          _highlightedMatches.add(match);
        }
      }
    }
    if(exclude) {
      _searchTerms.add("-$value");
    }
    else {
      _searchTerms.add(value);
    }
    setState(() {
      _rebuildChart();
    });
  }

  bool get hasHighlighting => _highlightedMatches.isNotEmpty;

  bool _isHighlighted(MatchPointer match) {
    if(_highlightedMatches.isNotEmpty) {
      return _highlightedMatches.contains(match) && !_excludedMatches.contains(match);
    }
    // If nothing is highlighted, everything is
    return true;
  }

  Offset? _mousePosition;
  Widget? _chartWidget;
  charts.Series<MatchHeat, int>? _series;
  charts.ScatterPlotChart? _chart;

  void _rebuildSeries() {
    _series = charts.Series<MatchHeat, int>(
      id: "matchHeat",
      data: _matchHeat.values.toList(),
      domainFn: (MatchHeat heat, _) => heat.rawCompetitorCount,
      measureFn: (MatchHeat heat, _) => heat.weightedTopTenPercentAverageRating,
      radiusPxFn: (MatchHeat heat, _) {
        if(heat.weightedMedianRating < 800) {
          return 1;
        }
        else {
          return 1 + ((heat.weightedMedianRating - 800) / 40);
        }
      },
      colorFn: (MatchHeat heat, _) {
        if(_project!.sport.ratingStrengthProvider == null) {
          return charts.MaterialPalette.blue.shadeDefault;
        }
        else {
          return _calculateStrengthColor(
            dimmed: !_isHighlighted(heat.matchPointer),
            value: heat.weightedClassificationStrength,
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
          "Elo",
          behaviorPosition: charts.BehaviorPosition.start,
        ),
        charts.ChartTitle(
          "Competitor Count",
          behaviorPosition: charts.BehaviorPosition.bottom,
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
      ),
      domainAxis: charts.NumericAxisSpec(
        viewport: charts.NumericExtents(_minX, _maxX),
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
    if(hasHighlighting && (!_highlightedMatches.contains(match) || _excludedMatches.contains(match))) {
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

  charts.Color? _calculateStrengthColor({
    required double value,
    required Map<Classification, double> classStrengths,
    bool dimmed = false,
  }) {
    final referenceColors = [
      Color.fromARGB(0xff, 0x09, 0x1f, 0x92).toRgbColor(),
      Colors.blue.toRgbColor(),
      Colors.green.toRgbColor(),
      Colors.yellow.toRgbColor(),
      Colors.orange.toRgbColor(),
      Colors.red.toRgbColor(),
    ];

    final stepsPerColor = 100 ~/ referenceColors.length;
    List<RgbColor> dotColorRange = [];
    for(var i = 1; i < referenceColors.length; i++) {
      // For each color, add a range of stepsPerColor steps
      dotColorRange.addAll(referenceColors[i - 1].lerpTo(referenceColors[i], stepsPerColor));
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

    for(var match in _highlightedMatches.whereNot((e) => _excludedMatches.contains(e))) {
      var heat = _matchHeat[match]!;
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
