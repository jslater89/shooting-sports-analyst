/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/box_and_whisker.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/url_entry_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/wager_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

var _log = SSALogger("PredictionView");

class PredictionView extends StatefulWidget {
  const PredictionView({Key? key, required this.dataSource, required this.matchId, required this.predictions}) : super(key: key);

  /// The data source that generated the predictions.
  final RatingDataSource dataSource;

  /// The match.
  final String matchId;

  /// The predictions.
  final List<AlgorithmPrediction> predictions;

  @override
  State<PredictionView> createState() => _PredictionViewState();

  static const int _padding = 2;
  static const int _rowFlex = 2;
  static const int _nameFlex = 12;
  static const int _classFlex = 4;
  static const int _ratingFlex = 4;
  static const int _95ciFlex = 5;
  static const int _whiskerPlotFlex = 40;
  static const double _whiskerPlotPadding = 20;
  static const double _rowHeight = 20;
  static const double _percentFloor = 0.25;
  static const double _percentMult = 1 - _percentFloor;
}

class _PredictionViewState extends State<PredictionView> {
  Map<AlgorithmPrediction, SimpleMatchResult> outcomes = {};
  List<AlgorithmPrediction> sortedPredictions = [];
  List<AlgorithmPrediction> searchedPredictions = [];
  String search = "";

  @override
  void initState() {
    super.initState();

    sortedPredictions = widget.predictions.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
    searchedPredictions = sortedPredictions;
  }

  @override
  Widget build(BuildContext context) {
    double minValue = 10000;
    double maxValue = -10000;

    final backgroundColor = ThemeColors.backgroundColor(context);

    var highPrediction = sortedPredictions.isEmpty ? 0.0 : (sortedPredictions[0].center + sortedPredictions[0].upperBox) / 2;

    if(sortedPredictions.isNotEmpty) {
      minValue = sortedPredictions.last.lowerWhisker;
      maxValue = sortedPredictions.first.upperWhisker;
    }

    return WillPopScope(
      onWillPop: () async {
        var confirm = await showDialog<bool>(context: context, builder: (context) =>
          ConfirmDialog(
            title: "Return to ratings?",
            content: Text("If you leave this page, you will need to recalculate predictions to view it again."),
            positiveButtonLabel: "LEAVE",
            negativeButtonLabel: "STAY",
          )
        );

        return confirm ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Predictions"),
          centerTitle: true,
          actions: [
            if(kDebugMode)
              Tooltip(
                message: "Check predictions",
                child: IconButton(
                  icon: Icon(Icons.candlestick_chart),
                  onPressed: () => _validate(highPrediction),
                ),
              ),
            // endif kDebugMode
            Tooltip(
              message: "Generate odds",
              child: IconButton(
                icon: Icon(Icons.casino),
                onPressed: () => WagerDialog.show(context, predictions: sortedPredictions, matchId: widget.matchId),
              )
            ),
            Tooltip(
              message: "Export predictions as CSV",
              child: IconButton(
                icon: Icon(Icons.save_alt),
                onPressed: () async {
                  String contents = "Name,Member Number,Class,Rating,5%,35%,Mean,65%,95%,Low Place,Mid Place,High Place,Actual Percent,Actual Place\n";

                  for(var pred in sortedPredictions) {
                    double midLow = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
                    double midHigh = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
                    double mean = (PredictionView._percentFloor + pred.center / highPrediction * PredictionView._percentMult) * 100;
                    double low = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
                    double high = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;
                    int lowPlace = pred.lowPlace;
                    int midPlace = pred.medianPlace;
                    int highPlace = pred.highPlace;
                    var outcome = outcomes[pred];

                    String line = "";
                    line += "${pred.shooter.getName(suffixes: false)},";
                    line += "${pred.shooter.originalMemberNumber},";
                    line += "${pred.shooter.lastClassification?.shortDisplayName ?? "none"},";
                    line += "${pred.shooter.rating.round()},";
                    line += "$low,$midLow,$mean,$midHigh,$high,$lowPlace,$midPlace,$highPlace";

                    if(outcome != null) {
                      line += ",${outcome.percent * 100},${outcome.place}";
                    }

                    // _log.vv(line);
                    contents += "$line\n";
                  }

                  HtmlOr.saveFile("predictions.csv", contents);
                },
              ),
            ),
          ],
        ),
        body: Container(
          color: backgroundColor,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: ThemeColors.onBackgroundColor(context)),
                  ),
                  color: ThemeColors.backgroundColor(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: _buildPredictionsHeader(),
                ),
              ),
              Expanded(
                child: ListView.builder(
                    itemCount: searchedPredictions.length,
                    itemBuilder: (context, i) {
                      return _buildPredictionsRow(searchedPredictions[i], minValue, maxValue, highPrediction, i);
                    },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _validate(double highPrediction) async {
    await MatchCache().ready;

    var matchUrl = await UrlEntryDialog.show(context, hintText: "https://practiscore.com/reports/web/");

    if(matchUrl == null) return;

    var result = await MatchCache().getMatch(matchUrl);
    if(result.isErr()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.unwrapErr().message)));
      return;
    }

    var match = result.unwrap();

    // var filters = widget.rater.filters;
    var shooters = <Shooter>[];
    // var shooters = match.filterShooters(
    //   filterMode: filters.mode,
    //   divisions: filters.activeDivisions.toList(),
    //   powerFactors: [],
    //   classes: [],
    //   allowReentries: false,
    // );
    var scores = match.getScores(
      shooters: shooters,
      scoreDQ: false,
    );

    var matchScores = <ShooterRating, RelativeMatchScore>{};
    List<ShooterRating> knownShooters = [];

    // We can only do validation for shooters with ratings and scores.
    // Give raters the whole list of shooters, and let them figure out
    // what to do with registration lists that don't match
    for(var shooter in shooters) {
      var rating = null;
      // var rating = widget.rater.ratingFor(shooter);
      if(rating != null) {
        var score = scores.firstWhereOrNull((element) => element.shooter == shooter);
        // var prediction = sortedPredictions.firstWhereOrNull((element) => element.shooter == rating);
        if(score != null) {
          matchScores[rating] = score;
          knownShooters.add(rating);
        }
      }
      else {
        _log.d("No rating for ${shooter.getName(suffixes: false)}");
      }
    }

    _log.i("Registrants: ${shooters.length} Predictions: ${shooters.length} Matched: ${knownShooters.length}");

    // var outcome = widget.rater.ratingSystem.validate(
    //     shooters: knownShooters,
    //     scores: matchScores.map((k, v) => MapEntry(k, v.total)),
    //     matchScores: matchScores,
    //     predictions: sortedPredictions
    // );
    //
    // if(outcome.mutatedInputs) {
    //   _log.i("Predictions changed");
    //   setState(() {
    //     sortedPredictions = outcome.actualResults.keys.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
    //     searchedPredictions = search.isEmpty ? sortedPredictions : sortedPredictions.where((p) =>
    //         p.shooter.getName(suffixes: false).toLowerCase().startsWith(search.toLowerCase())
    //         || p.shooter.lastName.toLowerCase().startsWith(search.toLowerCase())
    //     ).toList();
    //   });
    // }
    //
    // int correct68 = 0;
    // int correct95 = 0;
    // int total = 0;
    // for(var pred in outcome.actualResults.keys) {
    //   double boxLowPercent = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
    //   double whiskerLowPercent = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
    //   double whiskerHighPercent = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;
    //   double boxHighPercent = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
    //   double? outcomePercent;
    //
    //   if(outcome.actualResults[pred] != null) {
    //     total += 1;
    //     outcomePercent = outcome.actualResults[pred]!.percent * 100;
    //     if(outcomePercent >= whiskerLowPercent && outcomePercent <= whiskerHighPercent) correct95 += 1;
    //     if(outcomePercent >= boxLowPercent && outcomePercent <= boxHighPercent) correct68 += 1;
    //   }
    // }
    // _log.i("Pct. correct: $correct68/$correct95/$total (${(correct68 / total * 100).toStringAsFixed(1)}%/${(correct95 / total * 100).toStringAsFixed(1)}%)");
    //
    // setState(() {
    //   outcomes = outcome.actualResults;
    // });
  }

  Widget _buildPredictionsHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search"
                ),
                onChanged: (search) {
                  setState(() {
                    searchedPredictions = search.isEmpty ? sortedPredictions : sortedPredictions.where((p) =>
                    p.shooter.getName(suffixes: false).toLowerCase().startsWith(search.toLowerCase())
                        || p.shooter.lastName.toLowerCase().startsWith(search.toLowerCase())
                    ).toList();
                  });
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 15),
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              flex: PredictionView._padding,
              child: Container(),
            ),
            Expanded(
              flex: PredictionView._rowFlex,
              child: Text("Row"),
            ),
            Expanded(
              flex: PredictionView._nameFlex,
              child: Text("Name"),
            ),
            Expanded(
              flex: PredictionView._classFlex,
              child: Text("Class", textAlign: TextAlign.end),
            ),
            Expanded(
              flex: PredictionView._ratingFlex,
              child: Text("Rating", textAlign: TextAlign.end),
            ),
            Expanded(
                flex: PredictionView._95ciFlex,
                child: Tooltip(
                    message: "An estimated lower bound for a shooter's place finish, if he has a moderately bad day and everyone else has a moderately good one.",
                    child: Text("Low Place", textAlign: TextAlign.end)
                )
            ),
            Expanded(
                flex: PredictionView._95ciFlex,
                child: Tooltip(
                    message: "An estimated middle of the range for a shooter's place finish, if he performs slightly above average and everyone else performs at"
                        "\nan average level.",
                    child: Text("Med. Place", textAlign: TextAlign.end)
                )
            ),
            Expanded(
              flex: PredictionView._95ciFlex,
              child: Tooltip(
                  message: "An estimated upper bound for a shooter's place finish, if he has a good day and everyone else has a moderately bad one.",
                child: Text("High Place", textAlign: TextAlign.end)
              )
            ),
            if(outcomes.isNotEmpty) Expanded(
                flex: PredictionView._95ciFlex,
                child: Tooltip(
                  message: "The shooter's actual finish.",
                  child: Text("Actual Place", textAlign: TextAlign.end)
                )
            ),
            SizedBox(width: PredictionView._whiskerPlotPadding),
            Expanded(
              flex: PredictionView._whiskerPlotFlex,
              child: Tooltip(
                message: "Boxes show a prediction with about 65% confidence. Whiskers show a prediction with about 95% confidence.\n"
                    "Predicted performances are relative to one another. The percentage in each prediction's tooltip is an\n"
                    "approximate value, for reference only.",
                child: Text("Performance Prediction", textAlign: TextAlign.center),
              ),
            ),
            SizedBox(width: PredictionView._whiskerPlotPadding),
          ]
        ),
      ],
    );
  }

  Widget _buildPredictionsRow(AlgorithmPrediction pred, double min, double max, double highPrediction, int index) {
    double renderMin = min * 0.95;
    double renderMax = max * 1.01;

    double renderMinPercent = (PredictionView._percentFloor + renderMin / highPrediction * PredictionView._percentMult) * 100;
    double renderMaxPercent = (PredictionView._percentFloor + renderMax / highPrediction * PredictionView._percentMult) * 100;

    double boxLowPercent = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
    double boxHighPercent = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
    double meanPercent = (PredictionView._percentFloor + pred.mean / highPrediction * PredictionView._percentMult) * 100;
    double whiskerLowPercent = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
    double whiskerHighPercent = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;
    double? outcomePercent;

    List<double> referenceLines = [];
    var outcome = outcomes[pred];
    if(outcome != null) {
      if(outcome.percent > 0.2) {
        outcomePercent = outcome.percent * 100;
        referenceLines = [outcomePercent];
      }
    }

    return ClickableLink(
      onTap: () {
        var latestEvent = pred.shooter.eventsWithWindow(window: 1).firstOrNull;
        if(latestEvent != null) {
          var latestMatch = latestEvent.match;
          ShooterStatsDialog.show(context, pred.shooter, latestMatch);
        }
      },
      child: ConstrainedBox(
        key: Key(pred.shooter.memberNumber),
        constraints: BoxConstraints(
          minHeight: PredictionView._rowHeight,
        ),
        child: ScoreRow(
          color: ThemeColors.backgroundColor(context, rowIndex: index),
          child: Row(
            children: [
              Expanded(
                flex: PredictionView._padding,
                child: Container(),
              ),
              Expanded(
                flex: PredictionView._rowFlex,
                child: Text("${index + 1}"),
              ),
              Expanded(
                flex: PredictionView._nameFlex,
                child: GestureDetector(
                  onTap: () async {
                    var latestEvent = pred.shooter.eventsWithWindow(window: 1).firstOrNull;
                    if(latestEvent != null) {
                      var latestMatch = latestEvent.match;
                      ShooterStatsDialog.show(context, pred.shooter, latestMatch);
                    }
                  },
                  child: Text(pred.shooter.getName(suffixes: false)),
                ),
              ),
              Expanded(
                flex: PredictionView._classFlex,
                child: Text(pred.shooter.lastClassification?.shortDisplayName ?? "(none)", textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionView._ratingFlex,
                child: Text(pred.shooter.rating.round().toString(), textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionView._95ciFlex,
                child: Text("${pred.lowPlace}", textAlign: TextAlign.end), //Text("${whiskerLowPercent.toStringAsFixed(1)}", textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionView._95ciFlex,
                child: Text("${pred.medianPlace}", textAlign: TextAlign.end), // Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionView._95ciFlex,
                child: Text("${pred.highPlace}", textAlign: TextAlign.end), // Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
              ),
              if(outcomes.isNotEmpty) Expanded(
                flex: PredictionView._95ciFlex,
                child: Text("${outcome?.place ?? "n/a"}", textAlign: TextAlign.end), // Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
              ),
              SizedBox(width: PredictionView._whiskerPlotPadding),
              Expanded(
                flex: PredictionView._whiskerPlotFlex,
                child: Tooltip(
                  message: "68% confidence: ${boxLowPercent.toStringAsFixed(1)}-${boxHighPercent.toStringAsFixed(1)}%\n"
                      "95% confidence: ${whiskerLowPercent.toStringAsFixed(1)}-${whiskerHighPercent.toStringAsFixed(1)}%" + (
                      outcomePercent != null ? "\nOutcome: ${outcomePercent.toStringAsFixed(1)}%" : ""),
                  child: BoxAndWhiskerPlot(
                    minimum: whiskerLowPercent,
                    lowerQuartile: boxLowPercent,
                    median: meanPercent,
                    upperQuartile: boxHighPercent,
                    maximum: whiskerHighPercent,
                    direction: PlotDirection.horizontal,
                    rangeMin: renderMinPercent,
                    rangeMax: renderMaxPercent,
                    lowerBoxColor: ThemeColors.onBackgroundColor(context),
                    upperBoxColor: ThemeColors.onBackgroundColor(context),
                    whiskerColor: ThemeColors.onBackgroundColor(context),
                    fillBox: true,
                    boxSize: 12,
                    strokeWidth: 1.5,
                    referenceLines: referenceLines,
                  ),
                )
              ),
              SizedBox(width: PredictionView._whiskerPlotPadding),
            ],
          ),
        ),
      ),
    );
  }
}
