/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/career_stats.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/data/model.dart' as old;
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
// ignore: implementation_imports
import 'package:community_charts_flutter/src/text_style.dart' as style;
// ignore: implementation_imports
import 'package:community_charts_flutter/src/text_element.dart' as element;
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("ShooterStatsDialog");

final NumberFormat _separatedNumberFormat = NumberFormat("#,###");
final NumberFormat _nf = NumberFormat("####");
final NumberFormat _separatedDecimalFormat = NumberFormat("#,###.00");

/// This displays per-stage changes for a shooter.
class ShooterStatsDialog extends StatefulWidget {
  const ShooterStatsDialog({
    Key? key,
    required this.rating,
    required this.match,
    this.ratings,
    this.showDivisions = false,
  }) : super(key: key);

  final bool showDivisions;
  final ShooterRating rating;
  final ShootingMatch match;
  final RatingDataSource? ratings;

  @override
  State<ShooterStatsDialog> createState() => _ShooterStatsDialogState();

  static Future<void> show(BuildContext context, ShooterRating rating, ShootingMatch match, {RatingDataSource? ratings, bool showDivisions = false}) async {
    return showDialog<void>(
      context: context,
      builder: (context) => ShooterStatsDialog(rating: rating, match: match, ratings: ratings, showDivisions: showDivisions),
    );
  }
}

class _ShooterStatsDialogState extends State<ShooterStatsDialog> {
  final ScrollController _rightController = ScrollController();
  final ScrollController _leftController = ScrollController();

  RatingEvent? _highlighted;
  List<Widget>? _eventLines;
  List<Widget>? _historyLines;
  bool showingEvents = true;
  bool reverseHistoryLines = false;
  Sport get sport => widget.match.sport;
  late CareerStats careerStats;
  late PeriodicStats displayedStats;

  @override
  void initState() {
    super.initState();

    careerStats = CareerStats(sport, widget.rating);
    displayedStats = careerStats.careerStats;
  }

  String _divisionName(RatingEvent e) {
    return e.entry.division?.displayName ?? "UNK";
  }

  List<Widget> _buildEventLines() {
    _eventLines = displayedStats.events
      .map((e) => Tooltip(
      waitDuration: Duration(milliseconds: 500),
      message: e.infoLines.map((line) => line.apply(e.infoData)).join("\n"),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClickableLink(
              onTap: () {
                _launchScoreView(e.entry.division, e.match, stage: e.stage);
              },
              child: _StatefulContainer(
                key: GlobalObjectKey(e.hashCode),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 10,
                      child: Text("${e.eventName}${widget.showDivisions ? " (${_divisionName(e)})" : ""}",
                          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: e.ratingChange < 0 ? Theme.of(context).colorScheme.error : null)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: Text("${e.ratingChange.toStringAsFixed(2)}",
                              style:
                              Theme.of(context).textTheme.bodyMedium!.copyWith(color: e.ratingChange < 0 ? Theme.of(context).colorScheme.error : null))),
                    )
                  ],
                ),
              ),
            ),
            Divider(
              height: 2,
              thickness: 1,
            )
          ],
        ),
      ),
    )).toList();
    return _eventLines!;
  }

  Future<void> exportCSV() async{
    String header = "Date,Match,StageNum,StageName,StageRounds,RatingBefore,RatingChange,RatingAfter\n";
    String content = "";

    for(var event in displayedStats.events) {
      content +=
          "${(event.match.date).toString()}"
          "${event.match.name}," +
          "${event.stage?.stageId ?? ""}," +
          "${event.stage?.name ?? ""}," +
          "${event.stage?.minRounds ?? ""}," +
          "${event.oldRating}," +
          "${event.ratingChange}," +
          "${event.newRating}\n";
    }

    var csv = header + content;

    await HtmlOr.saveFile("${widget.rating.getName(suffixes: false)}-rating-export.csv".safeFilename(replacement: "-"), csv);
  }

  List<Widget> _buildHistoryLines() {
    List<Widget> widgets = [];
    widgets.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text("Match", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 1, child: Text("Place", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end)),
          Expanded(flex: 1, child: Text("Shooters", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end)),
          Expanded(flex: 1, child: Text("Percent", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end)),
          Expanded(flex: 1, child: Text("Rating change", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end))
        ],
      ),
    ));
    widgets.add(Divider(
      height: 2,
      thickness: 1,
    ));

    Iterable<MatchHistoryEntry> entries;
    if(reverseHistoryLines) {
      entries = displayedStats.matchHistory.reversed;
    }
    else {
      entries = displayedStats.matchHistory;
    }

    for(var entry in entries) {
      widgets.add(ClickableLink(
        onTap: () {
          _launchScoreView(entry.divisionEntered, entry.match);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text(entry.match.name, style: Theme.of(context).textTheme.bodyMedium)),
              Expanded(flex: 1, child: Text("${entry.place}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end)),
              Expanded(flex: 1, child: Text("${entry.competitors}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end)),
              Expanded(flex: 1, child: Text(entry.percentFinish, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end)),
              Expanded(flex: 1, child: Text("${entry.ratingChange.toStringAsFixed(1)}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.end))
            ],
          ),
        ),
      ));
      widgets.add(Divider(
        height: 2,
        thickness: 1,
      ));
    }

    _historyLines = widgets;
    return _historyLines!;
  }

  @override
  Widget build(BuildContext context) {
    // if(rating.ratingEvents.length < 30) {
    //   events = rating.ratingEvents;
    // }
    // else {
    //   events = rating.ratingEvents.sublist(rating.ratingEvents.length - 30);
    // }
    var eventLines = _eventLines ?? _buildEventLines();
    var historyLines = _historyLines ?? _buildHistoryLines();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ClickableLink(
            url: Uri.parse("https://uspsa.org/classification/${widget.rating.memberNumber}"),
            child: Text("Ratings for ${widget.rating.getName(suffixes: false)} ${widget.rating.memberNumber} (${widget.rating.lastClassification?.displayName})"),
          ),
          Row(
            children: [
              Tooltip(
                child: Icon(Icons.numbers),
                message: "Known member numbers:\n${widget.rating.knownMemberNumbers.join("\n")}\n\n"
                  "All possible member numbers:\n${widget.rating.allPossibleMemberNumbers.join("\n")}",
              ),
              Tooltip(
                message: "Export event-by-event ratings for this shooter",
                child: IconButton(
                  icon: Icon(Icons.download),
                  onPressed: () {
                    exportCSV();
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: Navigator.of(context).pop,
              ),
            ],
          ),
        ],
      ),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            child: _buildChart(widget.rating),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Scrollbar(
                    controller: _leftController,
                    child: SingleChildScrollView(
                      controller: _leftController,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        // mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: 10),
                          DropdownMenu<int>(
                            initialSelection: 0,
                            label: Text("Period"),
                            dropdownMenuEntries: [
                              DropdownMenuEntry(value: 0, label: "Career"),
                              ...careerStats.years.map((e) => DropdownMenuEntry(value: e, label: e.toString())).toList(),
                            ],
                            onSelected: (value) {
                              if(value != null) {
                                var stats = careerStats.statsForYear(value);
                                if(stats != null) {
                                  setState(() {
                                    // rebuild chart and event table
                                    _eventLines = null;
                                    _historyLines = null;
                                    _series = null;
                                    _chart = null;
                                    displayedStats = stats;
                                  });
                                }
                              }
                            },
                          ),
                          ..._buildShooterStats(context),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClickableLink(
                            child: Text(showingEvents ? "Event history" : "Match history",
                                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.tertiary)),
                            onTap: () {
                              setState(() {
                                showingEvents = !showingEvents;
                              });
                              _rightController.animateTo(0, duration: Duration(milliseconds: 200), curve: Curves.easeInOut);
                            },
                          ),
                          if(!showingEvents)
                            IconButton(
                              icon: Icon(reverseHistoryLines ? Icons.arrow_downward : Icons.arrow_upward),
                              onPressed: () {
                                setState(() {
                                  reverseHistoryLines = !reverseHistoryLines;
                                  _historyLines = null;
                              });
                            })
                        ],
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _rightController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _rightController,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if(showingEvents) ...eventLines,
                                if(!showingEvents) ...historyLines,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TODO: let raters build their own series, optionally?
  // Mostly for points rater, which doesn't do charts well
  // Doesn't do recreating well
  charts.Series<_AccumulatedRatingEvent, int>? _series;
  charts.LineChart? _chart;
  late List<_AccumulatedRatingEvent> _ratings;
  // TODO: go back to Division as key once rater is updated
  Map<String, charts.Color> _divisionColors = {};
  int _colorIndex = 0;
  List<charts.Color> _colorOptions = [
    charts.MaterialPalette.blue.shadeDefault,
    charts.MaterialPalette.indigo.shadeDefault,
    charts.MaterialPalette.cyan.shadeDefault,
    charts.MaterialPalette.green.shadeDefault,
    charts.MaterialPalette.lime.shadeDefault,
    charts.MaterialPalette.yellow.shadeDefault,
    charts.MaterialPalette.deepOrange.shadeDefault,
    charts.MaterialPalette.red.shadeDefault,
    charts.MaterialPalette.purple.shadeDefault,
  ];

  Widget _buildChart(ShooterRating rating) {
    double accumulator = 0;
    double minRating = 10000000;
    double maxRating = -10000000;
    double minWithError = 10000000;
    double maxWithError = -10000000;

    var size = MediaQuery.of(context).size;

    if(_series == null) {
      var eventsOfInterest = displayedStats.events.reversed.where((e) => e.newRating != 0 && e.ratingChange != 0);
      _ratings = eventsOfInterest.mapIndexed((i, e) {
        if(e.newRating < minRating) minRating = e.newRating;
        if(e.newRating > maxRating) maxRating = e.newRating;

        double error = 0;
        if(rating is EloShooterRating) {
          error = rating.standardErrorWithOffset(offset: eventsOfInterest.length - (i + 1));

          // print("Comparison: ${error.toStringAsFixed(2)} vs ${e2.toStringAsFixed(2)}");
        }
        else if(rating is OpenskillRating) {
          error = rating.sigmaWithOffset(eventsOfInterest.length - (i + 1)) / 2;
        }

        var plusError = e.newRating + error;
        var minusError = e.newRating - error;
        if(plusError > maxWithError) maxWithError = plusError;
        if(minusError < minWithError) minWithError = minusError;

        return _AccumulatedRatingEvent(e, accumulator += e.ratingChange, error);
      }).toList();

      _series = charts.Series<_AccumulatedRatingEvent, int>(
        id: 'Results',
        colorFn: (e, __) {
          if(!widget.showDivisions) return charts.MaterialPalette.blue.shadeDefault;

          var division = e.baseEvent.entry.division?.displayName;
          if(division == null) {
            return _colorOptions.first;
          }

          if(_divisionColors.containsKey(division)) {
            return _divisionColors[division]!;
          }
          else {
            var color = _colorOptions[_colorIndex];
            _colorIndex += 1;
            _colorIndex %= _colorOptions.length;
            _divisionColors[division] = color;
            return color;
          }
        },
        measureFn: (_AccumulatedRatingEvent e, _) => e.baseEvent.newRating,
        domainFn: (_, int? index) => index!,
        measureLowerBoundFn: (e, i) {
          if(rating is EloShooterRating || rating is OpenskillRating) {
            return e.baseEvent.newRating - e.errorAt;
          }
          return null;
        },
        measureUpperBoundFn: (e, i) {
          if(rating is EloShooterRating || rating is OpenskillRating) {
            return e.baseEvent.newRating + e.errorAt;
          }
          return null;
        },
        data: _ratings,
      );
    }

    if(_chart == null) {
      _chart = charts.LineChart(
        [_series!],
        animate: false,
        behaviors: [
          charts.SelectNearest(
            eventTrigger: charts.SelectionTrigger.hover,
            selectionModelType: charts.SelectionModelType.info,
            maximumDomainDistancePx: 100,
          ),
          charts.SelectNearest(
            eventTrigger: charts.SelectionTrigger.tap,
            selectionModelType: charts.SelectionModelType.action,
            maximumDomainDistancePx: 100,
          ),
          charts.LinePointHighlighter(
            selectionModelType: charts.SelectionModelType.info,
            symbolRenderer: _EloTooltipRenderer(),
          ),
        ],
        selectionModels: [
          charts.SelectionModelConfig(
            type: charts.SelectionModelType.info,
            updatedListener: (model) {
              if(model.hasDatumSelection) {
                final rating = _ratings[model.selectedDatum[0].index!];
                _EloTooltipRenderer.index = model.selectedDatum[0].index!;
                _EloTooltipRenderer.indexTotal = _ratings.length;
                _EloTooltipRenderer.rating = rating.baseEvent.newRating;
                _EloTooltipRenderer.error = rating.errorAt;
                _highlight(rating);
              }
            },
          ),
          charts.SelectionModelConfig(
            type: charts.SelectionModelType.action,
            updatedListener: (model) {
              if(model.hasDatumSelection) {
                final rating = _ratings[model.selectedDatum[0].index!];
                _launchScoreView(rating.baseEvent.entry.division, rating.baseEvent.match, stage: rating.baseEvent.stage);
              }
            },
          )
        ],
        domainAxis: charts.NumericAxisSpec(
          renderSpec: charts.NoneRenderSpec(
              axisLineStyle: charts.LineStyleSpec(
                thickness: 1,
              )
          ),
          showAxisLine: true,
        ),
        primaryMeasureAxis: charts.NumericAxisSpec(
          viewport: charts.NumericExtents(minWithError - 50, maxWithError + 50),
          tickProviderSpec: charts.BasicNumericTickProviderSpec(
            dataIsInWholeNumbers: true,
            desiredMinTickCount: 8,
            desiredTickCount: 10,
          ),
          tickFormatterSpec: charts.BasicNumericTickFormatterSpec.fromNumberFormat(_nf),
          showAxisLine: true,
        ),
      );
    }

    double width = max(600, size.width * 0.9);
    double height = size.height > size.width ? width / 1.5 : width / 3;
    return SizedBox(
      height: height,
      width: width,
      child: _chart!,
    );
  }

  void _launchScoreView(Division? division, ShootingMatch match, {MatchStage? stage}) {
    var filters = FilterSet(match.sport, empty: true)
      ..mode = FilterMode.or;
    if(division != null) {
      filters.divisions = FilterSet.divisionListToMap(match.sport, [division]);
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return ResultPage(
        canonicalMatch: match,
        initialStage: stage,
        initialFilters: filters,
        allowWhatIf: false,
        ratings: widget.ratings,
      );
    }));
  }

  void _highlight(_AccumulatedRatingEvent e) {
    var oldState = GlobalObjectKey(_highlighted.hashCode).currentState;
    if(oldState != null) {
      oldState as _StatefulContainerState;
      oldState.highlighted = false;
    }

    setState(() {
      _highlighted = e.baseEvent;
    });

    var key = GlobalObjectKey(e.baseEvent.hashCode);
    var ctx = key.currentContext;
    if(ctx != null) Scrollable.ensureVisible(ctx);

    var state = key.currentState;
    if(state != null) {
      state as _StatefulContainerState;
      state.highlighted = true;
    }
  }

  bool get byStage {
    return careerStats.byStage;
  }


  List<Widget> _buildShooterStats(BuildContext context) {
    if(displayedStats.events.isEmpty) {
      return [Text("No data available", style: Theme.of(context).textTheme.bodyMedium)];
    }

    AverageRating average;
    if(displayedStats.isCareer) {
      average = widget.rating.averageRating();
    }
    else {
      average = widget.rating.averageRatingByDate(start: displayedStats.start, end: displayedStats.end);
    }
    var lifetimeAverage = widget.rating.averageRating(window: careerStats.careerStats.events.length);

    int powerFactorsPresent = 0;
    if(displayedStats.majorEntries > 0) powerFactorsPresent += 1;
    if(displayedStats.minorEntries > 0) powerFactorsPresent += 1;
    if(displayedStats.otherEntries > 0) powerFactorsPresent += 1;

    var levelI = displayedStats.matchesByLevel.keys.firstWhereOrNull((e) => e.eventLevel == EventLevel.local);
    var levelII = displayedStats.matchesByLevel.keys.firstWhereOrNull((e) => e.eventLevel == EventLevel.regional);
    var levelIIIPlus = displayedStats.matchesByLevel.keys.where((e) => e.eventLevel.index >= EventLevel.area.index);

    int levelICount = displayedStats.matchesByLevel[levelI] ?? 0;
    int levelIICount = displayedStats.matchesByLevel[levelII] ?? 0;
    int levelIIICount = 0;
    for(var level in levelIIIPlus) {
      levelIIICount += displayedStats.matchesByLevel[level] ?? 0;
    }

    return [
      Row(
        children: [
          Expanded(flex: 4, child: Text("Current rating", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${widget.rating.rating.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Peak rating", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${lifetimeAverage.maxRating.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average rating (${displayedStats.isCareer ? "past 30 events" : displayedStats.start.year})", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${average.averageOfIntermediates.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max rating (${displayedStats.isCareer ? "past 30 events" : displayedStats.start.year})", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${average.minRating.round()}-${average.maxRating.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Total stages/matches", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${displayedStats.combinedEvents.length}/${displayedStats.matches.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage && displayedStats.combinedEvents.length != displayedStats.events.length) Row(
        children: [
          Expanded(flex: 4, child: Text("Stages/matches with rating changes", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${displayedStats.events.length}/${displayedStats.matchesWithRatingChanges.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage && displayedStats.combinedEvents.length != displayedStats.events.length) Divider(height: 2, thickness: 1),
      if(!byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Total matches", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${displayedStats.matches.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(!byStage) Divider(height: 2, thickness: 1),
      if(!byStage && displayedStats.combinedEvents.length != displayedStats.events.length) Row(
        children: [
          Expanded(flex: 4, child: Text("Matches with rating changes", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${displayedStats.matchesWithRatingChanges.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(!byStage && displayedStats.combinedEvents.length != displayedStats.events.length) Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Matches of level I/II/III", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "$levelICount/$levelIICount/$levelIIICount",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(displayedStats.classMatchPlaces.isNotEmpty) Row(
        children: [
          Expanded(flex: 4, child: Text("Match wins/class wins", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.matchWins}/${displayedStats.classMatchWins}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. match place/class place", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.matchPlaces.isNotEmpty ? displayedStats.matchPlaces.average.toStringAsFixed(1) : "-"}/"
              "${displayedStats.classMatchPlaces.isNotEmpty ? displayedStats.classMatchPlaces.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. match pct./class pct.", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.matchPercentages.isNotEmpty ? displayedStats.matchPercentages.average.toStringAsFixed(1) : "-"}/"
              "${displayedStats.classMatchPercentages.isNotEmpty ? displayedStats.classMatchPercentages.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. no. competitors", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.competitorCounts.average.toStringAsFixed(1)}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Stage wins/class stage wins", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.stageWins}/${displayedStats.classStageWins}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Stage pct./class stage pct.", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.stagePercentages.isNotEmpty ? displayedStats.stagePercentages.average.toStringAsFixed(1) : "-"}/"
              "${displayedStats.classStagePercentages.isNotEmpty ? displayedStats.classStagePercentages.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. stage finish/class stage finish", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${displayedStats.stageFinishes.isNotEmpty ? displayedStats.stageFinishes.average.toStringAsFixed(1) : "-"}/"
              "${displayedStats.classStageFinishes.isNotEmpty ? displayedStats.classStageFinishes.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(powerFactorsPresent > 1) Row(
        children: [
          Expanded(flex: 4, child: Text("Major/minor/other PF", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${(displayedStats.majorEntries / displayedStats.totalEntries).asPercentage(decimals: 0)}%/${(displayedStats.minorEntries / displayedStats.totalEntries).asPercentage(decimals: 0)}%/${(displayedStats.otherEntries / displayedStats.totalEntries).asPercentage(decimals: 0)}%"
              , style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(powerFactorsPresent > 1) Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total hits", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(displayedStats.totalScore?.scoringEventText(sport) ?? "",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 2, child: Text("Hit percentages", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(displayedStats.totalScore?.hitPercentages(sport) ?? "",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total time/points/hit factor", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(
            // TODO: display hit factor, final time, or points based on scoring
              "${_separatedDecimalFormat.format(displayedStats.totalScore!.finalTime)} s/${_separatedNumberFormat.format(displayedStats.totalPoints)} pts/${(displayedStats.totalPoints / displayedStats.totalScore!.finalTime).toStringAsFixed(4)} HF",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("DQs", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(
              "${displayedStats.dqs.length}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(widget.rating is PointsRating) Row(
        children: [
          Expanded(flex: 4, child: Text("Points from scores", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(
              "${(widget.rating as PointsRating).ratingFromScores.toStringAsFixed(1)}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(widget.rating is PointsRating) Divider(height: 2, thickness: 1),
      if(widget.rating is PointsRating) Row(
        children: [
          Expanded(flex: 4, child: Text("Points from participation", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(
              "${(widget.rating as PointsRating).ratingFromParticipation.toStringAsFixed(1)}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(widget.rating is PointsRating) Divider(height: 2, thickness: 1),
    ];
  }
}

class _AccumulatedRatingEvent {
  RatingEvent baseEvent;
  double accumulated;
  double errorAt;

  _AccumulatedRatingEvent(this.baseEvent, this.accumulated, this.errorAt);
}

class _EloTooltipRenderer extends charts.CircleSymbolRenderer {
  static late double rating;
  static late double error;
  static late int index;
  static late int indexTotal;

  @override
  void paint(charts.ChartCanvas canvas, Rectangle<num> bounds, {List<int>? dashPattern, charts.Color? fillColor, charts.FillPatternType? fillPattern, charts.Color? strokeColor, double? strokeWidthPx}) {
    super.paint(canvas, bounds, dashPattern: dashPattern, fillColor: fillColor, strokeColor: strokeColor, strokeWidthPx: strokeWidthPx);

    var proportion = index.toDouble() / (indexTotal.toDouble() - 1);
    var leftOffset = -(proportion * 60) + 10;

    if(leftOffset.isNaN) {
      return;
    }

    var ratingText = "${rating.round()}";
    if(error != 0) {
      ratingText += "±${error.round()}";
    }

    canvas.drawRect(
        Rectangle(bounds.left - 5, bounds.top - 30, bounds.width + 10, bounds.height + 10),
        fill: charts.Color.transparent
    );
    var textStyle = style.TextStyle();
    textStyle.color = charts.Color.black;
    textStyle.fontSize = 12;
    canvas.drawText(
        element.TextElement("$ratingText", style: textStyle),
        (bounds.left + leftOffset).round(),
        (bounds.top - 40).round()
    );
  }
}

class _StatefulContainer extends StatefulWidget {
  const _StatefulContainer({Key? key, required this.child}) : super(key: key);

  final Widget child;

  @override
  State<_StatefulContainer> createState() => _StatefulContainerState();
}

class _StatefulContainerState extends State<_StatefulContainer> {
  bool _highlighted = false;

  bool get highlighted => _highlighted;
  set highlighted(bool value) {
    setState(() {
      _highlighted = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: highlighted ? Colors.black12 : null,
      child: widget.child,
    );
  }
}

extension _HitPercentagesText on RawScore {
  String hitPercentages(Sport sport) {
    List<String> entries = [];
    var totalCount = this.targetEventCount;
    Map<String, int> eventCountsByName = {};
    var sortedEvents = this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    for(var entry in sortedEvents) {
      var event = entry.key;
      var count = entry.value;
      eventCountsByName.incrementBy(event.name, count);
    }

    var powerFactor = sport.defaultPowerFactor;
    for(var entry in eventCountsByName.entries) {
      var event = powerFactor.targetEvents.lookupByName(entry.key);
      if(event != null && event.displayInOverview) {
        entries.add("${(entry.value / totalCount).asPercentage(decimals: 1)} ${event.shortDisplayName}");
      }
    }

    return entries.join(", ");
  }

  String scoringEventText(Sport sport) {
    var message = StringBuffer();
    Map<String, int> eventCountsByName = {};
    var sortedEvents = this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));
    for(var entry in sortedEvents) {
      var event = entry.key;
      var count = entry.value;
      eventCountsByName.incrementBy(event.name, count);
    }

    var powerFactor = sport.defaultPowerFactor;
    for(var entry in eventCountsByName.entries) {
      var event = powerFactor.targetEvents.lookupByName(entry.key);
      var count = entry.value;
      if(event != null && event.displayInOverview) {
        if(sport.displaySettings.eventNamesAsSuffix) {
          message.write("$count${event.shortDisplayName} ");
        }
        else {
          message.write("${event.shortDisplayName}: $count ");
        }
      }
    }

    return message.toString();
  }
}
