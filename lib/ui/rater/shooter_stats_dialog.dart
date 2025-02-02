/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rating_change.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:sprintf/sprintf.dart';
import 'package:shooting_sports_analyst/data/model.dart' as old;
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:charts_flutter/flutter.dart' as charts;
// ignore: implementation_imports
import 'package:charts_flutter/src/text_style.dart' as style;
// ignore: implementation_imports
import 'package:charts_flutter/src/text_element.dart' as element;
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("ShooterStatsDialog");

final NumberFormat _separatedNumberFormat = NumberFormat("#,###");
final NumberFormat _nf = NumberFormat("####");
final NumberFormat _separatedDecimalFormat = NumberFormat("#,###.00");

/// This displays per-stage changes for a shooter.
class ShooterStatsDialog extends StatefulWidget {
  const ShooterStatsDialog({Key? key, required this.rating, required this.match, this.ratings, this.showDivisions = false}) : super(key: key);

  final bool showDivisions;
  final ShooterRating rating;
  final ShootingMatch match;
  final RatingDataSource? ratings;

  @override
  State<ShooterStatsDialog> createState() => _ShooterStatsDialogState();
}

class _ShooterStatsDialogState extends State<ShooterStatsDialog> {
  final ScrollController _rightController = ScrollController();
  final ScrollController _leftController = ScrollController();

  RatingEvent? _highlighted;
  List<Widget>? _eventLines;
  List<Widget>? _historyLines;
  bool showingEvents = true;
  Sport get sport => widget.match.sport;
  List<RatingEvent> ratingEvents = [];
  List<RatingEvent> combinedRatingEvents = [];

  @override
  void initState() {
    super.initState();
    combinedRatingEvents = widget.rating.ratingEvents;
    ratingEvents = combinedRatingEvents.where((e) => e.ratingChange != 0).toList();
    matchHistory = widget.rating.careerHistory();
  }

  String _divisionName(RatingEvent e) {
    return e.entry.division?.displayName ?? "UNK";
  }

  List<Widget> _buildEventLines() {
    _eventLines = ratingEvents
      .map((e) => Tooltip(
      message: e.info.keys.map((line) => sprintf(line, e.info[line])).join("\n"),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _launchScoreView(e);
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

    for(var event in ratingEvents) {
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

    for(var entry in matchHistory.reversed) {
      widgets.add(Padding(
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
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              child: Text("Ratings for ${widget.rating.getName(suffixes: false)} ${widget.rating.memberNumber} (${widget.rating.lastClassification?.displayName})"),
              onTap: () {
                HtmlOr.openLink("https://uspsa.org/classification/${widget.rating.memberNumber}");
              },
            ),
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
                          ..._buildShooterStats(context),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Scrollbar(
                    controller: _rightController,
                    thumbVisibility: true,
                    child: Column(
                      children: [
                        MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              child: Text(showingEvents ? "Event history" : "Match history",
                                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.tertiary)),
                              onTap: () {
                                setState(() {
                                  showingEvents = !showingEvents;
                                });
                              },
                            )
                        ),
                        Expanded(
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
                      ],
                    ),
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
    double minRating = 10000;
    double maxRating = -10000;
    double minWithError = 10000;
    double maxWithError = -10000;

    var size = MediaQuery.of(context).size;

    if(_series == null) {
      _ratings = rating.ratingEvents.reversed.where((e) => e.newRating != 0 && e.ratingChange != 0).mapIndexed((i, e) {
        if(e.newRating < minRating) minRating = e.newRating;
        if(e.newRating > maxRating) maxRating = e.newRating;

        double error = 0;
        if(rating is EloShooterRating) {
          error = rating.standardErrorWithOffset(offset: rating.ratingEvents.length - (i + 1));

          // print("Comparison: ${error.toStringAsFixed(2)} vs ${e2.toStringAsFixed(2)}");
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
          if(rating is EloShooterRating) {
            return e.baseEvent.newRating - e.errorAt;
          }
          return null;
        },
        measureUpperBoundFn: (e, i) {
          if(rating is EloShooterRating) {
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
                _launchScoreView(rating.baseEvent);
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

  void _launchScoreView(RatingEvent e) {
    var division = e.entry.division;
    var filters = FilterSet(e.match.sport, empty: true)
      ..mode = FilterMode.or;
    if(division != null) {
      filters.divisions = FilterSet.divisionListToMap(e.match.sport, [division]);
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return ResultPage(
        canonicalMatch: e.match,
        initialStage: e.match.lookupStageByName(e.stage?.name),
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
    if(ratingEvents.isEmpty) return true;

    return ratingEvents.last.stage != null;
  }
  List<MatchHistoryEntry> matchHistory = [];
  RawScore? totalScore;
  double totalPoints = 0;
  Set<ShootingMatch> dqs = {};
  Set<ShootingMatch> matches = {};
  Map<ShootingMatch, Classification> classesByMatch = {};
  Map<ShootingMatch, Division> divisionsByMatch = {};
  Set<ShootingMatch> matchesWithRatingChanges = {};
  Map<MatchLevel, int> matchesByLevel = {};
  int majorEntries = 0;
  int minorEntries = 0;
  int otherEntries = 0;
  int get totalEntries => majorEntries + minorEntries + otherEntries;
  int stageWins = 0;
  List<int> stageFinishes = [];
  int classStageWins = 0;
  List<int> classStageFinishes = [];
  int matchWins = 0;
  List<int> matchFinishes = [];
  int classMatchWins = 0;
  List<int> classMatchFinishes = [];
  List<int> competitorCounts = [];

  void calculateTotalScore() {
    // scoring isn't important; we'll add to targetEvents/penaltyEvents later
    var total = RawScore(scoring: const HitFactorScoring(), targetEvents: {}, penaltyEvents: {});

    Map<ShootingMatch, RelativeMatchScore> matchScores = {};
    for(var event in combinedRatingEvents) {
      var match = event.match;
      var divisions = widget.rating.group.divisions;
      RelativeScore eventScore;
      RelativeMatchScore? matchScore;
      if(matchScores.containsKey(match)) {
        matchScore = matchScores[match]!;
      }
      else {
        var scores = match.getScoresFromFilters(FilterSet(sport, divisions: divisions));
        matchScore = scores.entries.firstWhereOrNull((element) => widget.rating.equalsShooter(element.key))?.value;
        if(matchScore == null) {
          _log.w("Shooter ${widget.rating.name} doesn't have a score for match ${match.name}");
          continue;
        }
        matchScores[match] = matchScore;
      }
      if(byStage) {
        var stage = match.stages.firstWhere((s) => s.stageId == event.stageNumber);
        var stageScore = matchScore.stageScores[stage];
        if(stageScore == null) {
          _log.w("Shooter ${widget.rating.name} doesn't have a score for stage ${stage.name} in match ${match.name}");
          continue;
        }
        eventScore = stageScore;
        
        if(eventScore.place == 1) {
          stageWins += 1;
        }
        stageFinishes.add(eventScore.place);

        var stageClassScores = match.getScores(
          stages: [stage], 
          shooters: match.shooters.where((element) => 
            eventScore.shooter.division == element.division 
            && eventScore.shooter.classification == element.classification
          ).toList()
        );
        var stageClassScore = stageClassScores.entries.firstWhereOrNull((element) => widget.rating.equalsShooter(element.key))?.value;

        if(stageClassScore != null) {
          classStageFinishes.add(stageClassScore.place);
          if (stageClassScore.place == 1) {
            classStageWins += 1;
          }
        }
      }
      else {
        eventScore = matchScore;
      }

      if(eventScore is RelativeMatchScore) {
        total += eventScore.total;
        totalPoints += eventScore.total.points;
      }
      else if(eventScore is RelativeStageScore) {
        total += eventScore.score;
        totalPoints += eventScore.score.points;
      }

      if(eventScore.shooter.dq) {
        dqs.add(event.match);
      }
      if(ratingEvents.contains(event)) {
        matchesWithRatingChanges.add(event.match);
      }
      if(!matches.contains(event.match) && event.match.level != null) {
        matchesByLevel[event.match.level!] ??= 0;
        matchesByLevel[event.match.level!] = matchesByLevel[event.match.level ?? old.MatchLevel.I]! + 1;
      }
      matches.add(event.match);
      if(eventScore.shooter.classification != null) {
        classesByMatch[event.match] = eventScore.shooter.classification!;
      }
      if(eventScore.shooter.division != null) {
        divisionsByMatch[event.match] = eventScore.shooter.division!;
      }

      // switch(score.shooter.powerFactor) {
      //   case old.PowerFactor.major:
      //     majorEntries += 1;
      //     break;
      //   case old.PowerFactor.minor:
      //     minorEntries += 1;
      //     break;
      //   default:
      //     otherEntries += 1;
      //     break;
      // }
    }

    totalScore = total;

    for(var match in matches) {
      var classification = classesByMatch[match]!;
      var division = divisionsByMatch[match]!;
      var scores = match.getScores(shooters: match.shooters.where((element) => element.division == division).toList());
      competitorCounts.add(scores.length);
      var score = scores.entries.firstWhereOrNull((element) => widget.rating.equalsShooter(element.key))?.value;

      if(score == null) {
        throw StateError("Shooter in match doesn't have a score");
      }

      matchFinishes.add(score.place);
      if (score.place == 1) matchWins += 1;

      if (classification != old.Classification.unknown) {
        var scores = match.getScores(
            shooters: match.shooters.where((element) => element.division == division && element.classification == classification).toList());
        var score = scores.entries.firstWhereOrNull((element) => widget.rating.equalsShooter(element.key))!.value;

        if(classification != old.Classification.U) {
          classMatchFinishes.add(score.place);
          if (score.place == 1) {
            classMatchWins += 1;
          }
        }
      }
    }

  }

  List<Widget> _buildShooterStats(BuildContext context) {
    if(ratingEvents.isEmpty) {
      return [Text("No data available", style: Theme.of(context).textTheme.bodyMedium)];
    }

    var average = widget.rating.averageRating();
    var lifetimeAverage = widget.rating.averageRating(window: ratingEvents.length);

    if(totalScore == null) {
      calculateTotalScore();
    }

    int powerFactorsPresent = 0;
    if(majorEntries > 0) powerFactorsPresent += 1;
    if(minorEntries > 0) powerFactorsPresent += 1;
    if(otherEntries > 0) powerFactorsPresent += 1;

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
          Expanded(flex: 4, child: Text("Average rating (past 30 events)", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${average.averageOfIntermediates.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max rating (past 30 events)", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${average.minRating.round()}-${average.maxRating.round()}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Total stages/matches", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${widget.rating.combinedRatingEvents.length}/${matches.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage && ratingEvents.length != widget.rating.combinedRatingEvents.length) Row(
        children: [
          Expanded(flex: 4, child: Text("Stages/matches with rating changes", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${ratingEvents.length}/${matchesWithRatingChanges.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage && ratingEvents.length != widget.rating.combinedRatingEvents.length) Divider(height: 2, thickness: 1),
      if(!byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Total matches", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${matches.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(!byStage) Divider(height: 2, thickness: 1),
      if(!byStage && ratingEvents.length != widget.rating.combinedRatingEvents.length) Row(
        children: [
          Expanded(flex: 4, child: Text("Matches with rating changes", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text("${matchesWithRatingChanges.length}", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(!byStage && ratingEvents.length != widget.rating.combinedRatingEvents.length) Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Matches of level I/II/III", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${matchesByLevel[old.MatchLevel.I] ?? 0}/${matchesByLevel[old.MatchLevel.II] ?? 0}/${matchesByLevel[old.MatchLevel.III] ?? 0}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(classMatchFinishes.isNotEmpty) Row(
        children: [
          Expanded(flex: 4, child: Text("Match wins/class wins", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${matchWins}/${classMatchWins}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. match finish/class finish", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${matchFinishes.isNotEmpty ? matchFinishes.average.toStringAsFixed(1) : "-"}/"
              "${classMatchFinishes.isNotEmpty ? classMatchFinishes.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. no. competitors", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${competitorCounts.average.toStringAsFixed(1)}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Stage wins/class stage wins", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${stageWins}/${classStageWins}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. stage finish/class stage finish", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${stageFinishes.isNotEmpty ? stageFinishes.average.toStringAsFixed(1) : "-"}/"
                  "${classStageFinishes.isNotEmpty ? classStageFinishes.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(powerFactorsPresent > 1 || widget.rating.division == old.Division.singleStack) Row(
        children: [
          Expanded(flex: 4, child: Text("Major/minor/other PF", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(
              "${(majorEntries / totalEntries).asPercentage(decimals: 0)}%/${(minorEntries / totalEntries).asPercentage(decimals: 0)}%/${(otherEntries / totalEntries).asPercentage(decimals: 0)}%"
              , style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      if(powerFactorsPresent > 1 || widget.rating.division == old.Division.singleStack) Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total hits", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(totalScore?.scoringEventText(sport) ?? "",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 2, child: Text("Hit percentages", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(totalScore?.hitPercentages(sport) ?? "",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total time/points/hit factor", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(
            // TODO: display hit factor, final time, or points based on scoring
              "${_separatedDecimalFormat.format(totalScore!.finalTime)} s/${_separatedNumberFormat.format(totalPoints)} pts/${(totalPoints / totalScore!.finalTime).toStringAsFixed(4)} HF",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("DQs", style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(flex: 4, child: Text(
              "${dqs.length}",
              style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
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
    for(var entry in this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder))) {
      var event = entry.key;
      var count = entry.value;

      if(event.displayInOverview) {
        entries.add("${(count / totalCount).asPercentage(decimals: 1)} ${event.shortDisplayName}");
      }
    }

    return entries.join(", ");
  }

  String scoringEventText(Sport sport) {
    var message = StringBuffer();
    for(var entry in this.targetEvents.entries.sorted((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder))) {
      var event = entry.key;
      var count = entry.value;

      if(event.displayInOverview) {
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