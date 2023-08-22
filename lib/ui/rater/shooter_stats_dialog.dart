import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:charts_flutter/flutter.dart' as charts;
// ignore: implementation_imports
import 'package:charts_flutter/src/text_style.dart' as style;
// ignore: implementation_imports
import 'package:charts_flutter/src/text_element.dart' as element;
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/filter_dialog.dart';

/// This displays per-stage changes for a shooter.
class ShooterStatsDialog extends StatefulWidget {
  const ShooterStatsDialog({Key? key, required this.rating, required this.match, this.ratings}) : super(key: key);

  final ShooterRating rating;
  final PracticalMatch match;
  final Map<RaterGroup, Rater>? ratings;

  @override
  State<ShooterStatsDialog> createState() => _ShooterStatsDialogState();
}

class _ShooterStatsDialogState extends State<ShooterStatsDialog> {
  final ScrollController _rightController = ScrollController();
  final ScrollController _leftController = ScrollController();

  RatingEvent? _highlighted;
  List<Widget>? _eventLines;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

  }

  List<Widget> _buildEventLines() {
    List<RatingEvent> events = widget.rating.ratingEvents;
    _eventLines = events.reversed
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
                        child: Text("${e.eventName}",
                            style: Theme.of(context).textTheme.bodyText2!.copyWith(color: e.ratingChange < 0 ? Theme.of(context).errorColor : null)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: Text("${e.ratingChange.toStringAsFixed(2)}",
                                style:
                                Theme.of(context).textTheme.bodyText2!.copyWith(color: e.ratingChange < 0 ? Theme.of(context).errorColor : null))),
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

  @override
  Widget build(BuildContext context) {
    // if(rating.ratingEvents.length < 30) {
    //   events = rating.ratingEvents;
    // }
    // else {
    //   events = rating.ratingEvents.sublist(rating.ratingEvents.length - 30);
    // }
    var eventLines = _eventLines ?? _buildEventLines();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              child: Text("Ratings for ${widget.rating.getName(suffixes: false)} ${widget.rating.originalMemberNumber} (${widget.rating.lastClassification.name})"),
              onTap: () {
                HtmlOr.openLink("https://uspsa.org/classification/${widget.rating.originalMemberNumber}");
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
          )
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
                Expanded(
                  flex: 5,
                  child: Scrollbar(
                    controller: _rightController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _rightController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: eventLines,
                      ),
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
  late NumberFormat _nf = NumberFormat("####");
  late NumberFormat _separatedNumberFormat = NumberFormat("#,###");
  late NumberFormat _separatedDecimalFormat = NumberFormat("#,###.00");
  late List<_AccumulatedRatingEvent> _ratings;

  Widget _buildChart(ShooterRating rating) {
    double accumulator = 0;
    double minRating = 10000;
    double maxRating = -10000;
    double minWithError = 10000;
    double maxWithError = -10000;

    var size = MediaQuery.of(context).size;

    if(_series == null) {
      _ratings = rating.ratingEvents.mapIndexed((i, e) {
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
        colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
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
    var filters = FilterSet(empty: true)
      ..mode = FilterMode.or
      ..divisions = FilterSet.divisionListToMap([widget.rating.division!]);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return ResultPage(
        canonicalMatch: e.match,
        initialStage: e.stage,
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

  bool get byStage => widget.rating.ratingEvents.last.stage != null;
  Score? totalScore;
  int totalPoints = 0;
  Set<PracticalMatch> dqs = {};
  Set<PracticalMatch> matches = {};
  Map<PracticalMatch, Classification> classesByMatch = {};
  Set<PracticalMatch> matchesWithRatingChanges = {};
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
    var total = Score(shooter: widget.rating);

    for(var event in widget.rating.combinedRatingEvents) {
      var score = event.score.score;

      if(byStage) {
        var stage = event.stage!;
        if(event.score.place == 1) {
          stageWins += 1;
        }
        stageFinishes.add(event.score.place);

        var stageClassScores = event.match.getScores(stages: [stage], shooters: event.match.shooters.where(
              (element) => element.division == widget.rating.division && event.score.score.shooter.classification == element.classification).toList()
        );
        var stageClassScore = stageClassScores.firstWhereOrNull((element) => widget.rating.equalsShooter(element.shooter));

        if(stageClassScore != null && event.score.score.shooter.classification != Classification.U) {
          classStageFinishes.add(stageClassScore.total.place);
          if (stageClassScore.total.place == 1) {
            classStageWins += 1;
          }
        }
      }

      total += score;
      totalPoints += score.getTotalPoints();
      if(score.shooter.dq) {
        dqs.add(event.match);
      }
      if(widget.rating.ratingEvents.contains(event)) {
        matchesWithRatingChanges.add(event.match);
      }
      if(!matches.contains(event.match)) {
        matchesByLevel[event.match.level ?? MatchLevel.I] ??= 0;
        matchesByLevel[event.match.level ?? MatchLevel.I] = matchesByLevel[event.match.level ?? MatchLevel.I]! + 1;
      }
      matches.add(event.match);
      classesByMatch[event.match] = event.score.score.shooter.classification ?? Classification.unknown;

      switch(score.shooter.powerFactor) {
        case PowerFactor.major:
          majorEntries += 1;
          break;
        case PowerFactor.minor:
          minorEntries += 1;
          break;
        default:
          otherEntries += 1;
          break;
      }
    }

    totalScore = total;

    for(var match in matches) {
      var classification = classesByMatch[match]!;
      var scores = match.getScores(shooters: match.shooters.where((element) => element.division == widget.rating.division).toList());
      competitorCounts.add(scores.length);
      var score = scores.firstWhereOrNull((element) => widget.rating.equalsShooter(element.shooter));

      // TODO: this happens in combined divisions
      // If I compete in Production first, widget.rating.division is production, even if I later compete in revolver,
      // so we don't find my scores. Do a division-by-match map above, when going through rating events.
      if(score == null) {
        throw StateError("Shooter in match doesn't have a score");
      }

      matchFinishes.add(score.total.place);
      if (score.total.place == 1) matchWins += 1;

      if (classification != Classification.unknown) {
        var scores = match.getScores(
            shooters: match.shooters.where((element) => element.division == widget.rating.division && element.classification == classification).toList());
        var score = scores.firstWhere((element) => widget.rating.equalsShooter(element.shooter));

        if(classification != Classification.U) {
          classMatchFinishes.add(score.total.place);
          if (score.total.place == 1) {
            classMatchWins += 1;
          }
        }
      }
    }

  }

  List<Widget> _buildShooterStats(BuildContext context) {
    var average = widget.rating.averageRating();
    var lifetimeAverage = widget.rating.averageRating(window: widget.rating.ratingEvents.length);

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
          Expanded(flex: 4, child: Text("Current rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${widget.rating.rating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Peak rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${lifetimeAverage.maxRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average rating (past 30 events)", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${average.averageOfIntermediates.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max rating (past 30 events)", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${average.minRating.round()}-${average.maxRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Total stages/matches", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${widget.rating.combinedRatingEvents.length}/${matches.length}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage && widget.rating.ratingEvents.length != widget.rating.combinedRatingEvents.length) Row(
        children: [
          Expanded(flex: 4, child: Text("Stages/matches with rating changes", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${widget.rating.ratingEvents.length}/${matchesWithRatingChanges.length}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage && widget.rating.ratingEvents.length != widget.rating.combinedRatingEvents.length) Divider(height: 2, thickness: 1),
      if(!byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Total matches", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${matches.length}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(!byStage) Divider(height: 2, thickness: 1),
      if(!byStage && widget.rating.ratingEvents.length != widget.rating.combinedRatingEvents.length) Row(
        children: [
          Expanded(flex: 4, child: Text("Matches with rating changes", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${matchesWithRatingChanges.length}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(!byStage && widget.rating.ratingEvents.length != widget.rating.combinedRatingEvents.length) Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Matches of level I/II/III", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${matchesByLevel[MatchLevel.I] ?? 0}/${matchesByLevel[MatchLevel.II] ?? 0}/${matchesByLevel[MatchLevel.III] ?? 0}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(classMatchFinishes.length > 0) Row(
        children: [
          Expanded(flex: 4, child: Text("Match wins/class wins", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${matchWins}/${classMatchWins}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. match finish/class finish", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${matchFinishes.isNotEmpty ? matchFinishes.average.toStringAsFixed(1) : "-"}/"
              "${classMatchFinishes.isNotEmpty ? classMatchFinishes.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. no. competitors", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${competitorCounts.average.toStringAsFixed(1)}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Stage wins/class stage wins", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${stageWins}/${classStageWins}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(byStage) Row(
        children: [
          Expanded(flex: 4, child: Text("Avg. stage finish/class stage finish", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${stageFinishes.isNotEmpty ? stageFinishes.average.toStringAsFixed(1) : "-"}/"
                  "${classStageFinishes.isNotEmpty ? classStageFinishes.average.toStringAsFixed(1) : "-"}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(byStage) Divider(height: 2, thickness: 1),
      if(powerFactorsPresent > 1 || widget.rating.division == Division.singleStack) Row(
        children: [
          Expanded(flex: 4, child: Text("Major/minor/other PF", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text(
              "${(majorEntries / totalEntries).asPercentage(decimals: 0)}%/${(minorEntries / totalEntries).asPercentage(decimals: 0)}%/${(otherEntries / totalEntries).asPercentage(decimals: 0)}%"
              , style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      if(powerFactorsPresent > 1 || widget.rating.division == Division.singleStack) Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total hits", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 4, child: Text(
              "${_separatedNumberFormat.format(totalScore!.a)}A "
                  "${_separatedNumberFormat.format(totalScore!.c)}C "
                  "${_separatedNumberFormat.format(totalScore!.d)}D "
                  "${_separatedNumberFormat.format(totalScore!.m)}M "
                  "${_separatedNumberFormat.format(totalScore!.ns)}NS "
                  "${_separatedNumberFormat.format(totalScore!.penaltyCount)}P",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 2, child: Text("Hit percentages", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 4, child: Text(
              "${(totalScore!.a / totalScore!.shots).asPercentage(decimals: 1)}% A, "
                  "${(totalScore!.c / totalScore!.shots).asPercentage(decimals: 1)}% C, "
                  "${(totalScore!.d / totalScore!.shots).asPercentage(decimals: 1)}% D, "
                  "${(totalScore!.m / totalScore!.shots).asPercentage(decimals: 1)}% M, "
                  "${(totalScore!.ns / totalScore!.shots).asPercentage(decimals: 1)}% NS ",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total time/points/hit factor", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 4, child: Text(
              "${_separatedDecimalFormat.format(totalScore!.time)} s/${_separatedNumberFormat.format(totalPoints)} pts/${(totalPoints / totalScore!.time).toStringAsFixed(4)} HF",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("DQs", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 4, child: Text(
              "${dqs.length}",
              style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
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
