/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/box_and_whisker.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_database_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/wager_dialog.dart';

var _log = SSALogger("PredictionView");

class PredictionListViewScreen extends StatefulWidget {
  const PredictionListViewScreen({Key? key, required this.dataSource, required this.matchId, required this.group, required this.predictions}) : super(key: key);

  /// The data source that generated the predictions.
  final RatingDataSource dataSource;

  /// The match.
  final String matchId;
  /// The rating group that the predictions were generated for.
  final RatingGroup group;

  /// The predictions.
  final List<AlgorithmPrediction> predictions;

  @override
  State<PredictionListViewScreen> createState() => _PredictionListViewScreenState();

  static const int _padding = 2;
  static const int _rowFlex = 2;
  static const int _nameFlex = 12;
  static const int _classFlex = 4;
  static const int _ratingFlex = 4;
  static const int _95ciFlex = 5;
  static const int _whiskerPlotFlex = 40;
  static const double _whiskerPlotPadding = 20;
  static const double _rowHeight = 20;
}

class _PredictionListViewScreenState extends State<PredictionListViewScreen> {
  final predictionViewModel = PredictionViewModel();

  @override
  void initState() {
    super.initState();

    predictionViewModel.setPredictions(widget.predictions, notify: false);
  }

  @override
  Widget build(BuildContext context) {
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
      child: ChangeNotifierProvider<PredictionViewModel>.value(
        value: predictionViewModel,
        child: Consumer<PredictionViewModel>(
          builder: (context, model, child) => Scaffold(
            appBar: AppBar(
              title: Text("Predictions"),
              centerTitle: true,
              actions: [
                if(kDebugMode)
                  Tooltip(
                    message: "Check predictions",
                    child: IconButton(
                      icon: Icon(Icons.candlestick_chart),
                      onPressed: () => _validate(model),
                    ),
                  ),
                // endif kDebugMode
                Tooltip(
                  message: "Generate odds",
                  child: IconButton(
                    icon: Icon(Icons.casino),
                    onPressed: () => WagerDialog.show(context, predictions: model.predictions, matchId: widget.matchId),
                  )
                ),
                Tooltip(
                  message: "Export predictions as CSV",
                  child: IconButton(
                    icon: Icon(Icons.save_alt),
                    onPressed: () async {
                      String contents = "Name,Member Number,Class,Rating,5%,35%,Mean,65%,95%,Low Place,Mid Place,High Place,Actual Percent,Actual Place\n";

                      if(model.predictions.isNotEmpty) {
                        var rater = model.predictions.first.algorithm;
                        var settings = model.predictions.first.settings;

                        double percentFloor = RatingSystem.defaultRatioFloor;
                        double percentMult = RatingSystem.defaultRatioMult;
                        if(rater.supportsRatioFloor) {
                          var sortedByRating = model.predictions.sorted((a, b) => b.shooter.rating.compareTo(a.shooter.rating));
                          var bestRating = sortedByRating.first.shooter.rating;
                          var worstRating = sortedByRating.last.shooter.rating;
                          var ratingDelta = bestRating - worstRating;
                          percentFloor = 1.0 - rater.estimateRatioFloor(ratingDelta, settings: settings);
                          percentMult = 1.0 - percentFloor;
                        }

                        for(var pred in model.predictions) {
                          double midLow = (percentFloor + pred.lowerBox / model.highPrediction * percentMult) * 100;
                          double midHigh = (percentFloor + pred.upperBox / model.highPrediction * percentMult) * 100;
                          double mean = (percentFloor + pred.center / model.highPrediction * percentMult) * 100;
                          double low = (percentFloor + pred.lowerWhisker / model.highPrediction * percentMult) * 100;
                          double high = (percentFloor + pred.upperWhisker / model.highPrediction * percentMult) * 100;
                          int lowPlace = pred.lowPlace;
                          int midPlace = pred.medianPlace;
                          int highPlace = pred.highPlace;
                          var outcome = model.outcomes[pred];

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
                      }

                      HtmlOr.saveFile("predictions.csv", contents);
                    },
                  ),
                ),
              ],
            ),
            body: PredictionListView(),
          ),
        ),
      ),
    );
  }

  void _validate(PredictionViewModel model) async {
    var dbMatch = await MatchDatabaseChooserDialog.showSingle(
      context: context,
    );
    if(dbMatch == null) return;

    var matchRes = dbMatch.hydrate(useCache: true);

    if(matchRes.isErr()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(matchRes.unwrapErr().message)));
      return;
    }
    var match = matchRes.unwrap();

    var filters = widget.group.filters;
    var shooters = match.filterShooters(
      filterMode: FilterMode.and,
      divisions: filters.activeDivisions.toList(),
      allowReentries: false,
    );
    var scores = match.getScores(
      shooters: shooters,
      scoreDQ: false,
    );

    var matchScores = <ShooterRating, RelativeMatchScore>{};
    List<ShooterRating> knownShooters = [];
    Map<AlgorithmPrediction, SimpleMatchResult> actualResults = {};

    // We can only do validation for shooters with ratings and scores.
    // Give raters the whole list of shooters, and let them figure out
    // what to do with registration lists that don't match
    for(var shooter in shooters) {
      var ratingRes = await widget.dataSource.lookupRating(widget.group, shooter.memberNumber);
      if(ratingRes.isErr()) {
        _log.e("Error looking up rating for ${shooter.getName(suffixes: false)}: ${ratingRes.unwrapErr().message}");
        continue;
      }
      var rating = ratingRes.unwrap();
      if(rating != null) {
        var shooterRating = (await widget.dataSource.wrapDbRating(rating)).unwrap();
        var score = scores[shooter];
        var prediction = model.predictions.firstWhereOrNull((element) => rating.allPossibleMemberNumbers.contains(element.shooter.memberNumber));
        if(prediction != null) {
          actualResults[prediction] = SimpleMatchResult(raterScore: prediction.mean, percent: score?.ratio ?? 0, place: score?.place ?? 0);
        }
        if(score != null) {
          matchScores[shooterRating] = score;
          knownShooters.add(shooterRating);
        }
      }
      else {
        _log.d("No rating for ${shooter.getName(suffixes: false)}");
      }
    }

    _log.i("Registrants: ${shooters.length} Predictions: ${shooters.length} Matched: ${knownShooters.length}");

    PredictionOutcome outcome;
    // if(widget.dataSource.supportsValidation) {
      // var outcome = widget.rater.ratingSystem.validate(
      //     shooters: knownShooters,
      //     scores: matchScores.map((k, v) => MapEntry(k, v.total)),
      //     matchScores: matchScores,
      //     predictions: sortedPredictions
      // );

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

    // } else {
    outcome = PredictionOutcome(error: 0, actualResults: actualResults, mutatedInputs: false);
    model.setOutcomes(outcome.actualResults);

    List<double> percentErrors = [];
    List<int> placeErrors = [];
    for(var pred in outcome.actualResults.keys) {
      double percentError = (pred.mean - outcome.actualResults[pred]!.percent);
      percentErrors.add(percentError);
      int placeError = (pred.medianPlace - outcome.actualResults[pred]!.place);
      placeErrors.add(placeError);
    }

    double percentRmsError = sqrt(percentErrors.map((e) => e * e).average);
    double placeRmsError = sqrt(placeErrors.map((e) => e * e).average);
    double percentMeanAbsoluteError = percentErrors.map((e) => e.abs()).average;
    double placeMeanAbsoluteError = placeErrors.map((e) => e.abs()).average;
    double percentMeanSignedError = percentErrors.average;
    double placeMeanSignedError = placeErrors.average;
    _log.i("Percent RMSE: ${(percentRmsError * 100).toStringAsPrecision(3)}% Place RMSE: ${(placeRmsError).toStringAsPrecision(3)}");
    _log.i("Percent MAE: ${(percentMeanAbsoluteError * 100).toStringAsPrecision(3)}% Place MAE: ${(placeMeanAbsoluteError).toStringAsPrecision(3)}");
    _log.i("Percent MSignedE: ${(percentMeanSignedError * 100).toStringAsPrecision(3)}% Place MSignedE: ${(placeMeanSignedError).toStringAsPrecision(3)}");
    // }

  //   int correct68 = 0;
  //   int correct95 = 0;
  //   int total = 0;
  //   for(var pred in outcome.actualResults.keys) {
  //     double boxLowPercent = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
  //     double whiskerLowPercent = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
  //     double whiskerHighPercent = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;
  //     double boxHighPercent = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
  //     double? outcomePercent;

  //     if(outcome.actualResults[pred] != null) {
  //       total += 1;
  //       outcomePercent = outcome.actualResults[pred]!.percent * 100;
  //       if(outcomePercent >= whiskerLowPercent && outcomePercent <= whiskerHighPercent) correct95 += 1;
  //       if(outcomePercent >= boxLowPercent && outcomePercent <= boxHighPercent) correct68 += 1;
  //     }
  //   }
  //   _log.i("Pct. correct: $correct68/$correct95/$total (${(correct68 / total * 100).toStringAsFixed(1)}%/${(correct95 / total * 100).toStringAsFixed(1)}%)");

  //   setState(() {
  //     outcomes = outcome.actualResults;
  //   });
  }
}

class PredictionViewModel extends ChangeNotifier {

  PredictionViewModel({List<AlgorithmPrediction>? initialPredictions}) {
    if(initialPredictions != null) {
      setPredictions(initialPredictions, notify: false);
    }
  }
  List<AlgorithmPrediction> predictions = [];
  bool get hasOutcomes => outcomes.isNotEmpty;
  Map<AlgorithmPrediction, SimpleMatchResult> outcomes = {};
  List<AlgorithmPrediction> searchedPredictions = [];
  String searchTerm = "";

  double highPrediction = 0.0;
  double minValue = 10000;
  double maxValue = -10000;
  double percentFloor = RatingSystem.defaultRatioFloor;
  double percentMult = RatingSystem.defaultRatioMult;
  double minRating = double.infinity;
  double maxRating = double.negativeInfinity;

  void search(String search) {
    searchTerm = search;
    searchedPredictions = predictions.where((p) =>
      p.shooter.getName(suffixes: false).toLowerCase().startsWith(searchTerm.toLowerCase())
      || p.shooter.lastName.toLowerCase().startsWith(searchTerm.toLowerCase())
    ).toList();
    notifyListeners();
  }

  void setPredictions(List<AlgorithmPrediction> predictions, {bool notify = true}) {
    this.predictions = [...predictions];
    this.predictions.sort((a, b) => b.ordinal.compareTo(a.ordinal));
    searchedPredictions = this.predictions;
    minValue = 10000;
    maxValue = -10000;
    percentFloor = RatingSystem.defaultRatioFloor;
    percentMult = RatingSystem.defaultRatioMult;
    minRating = double.infinity;
    maxRating = double.negativeInfinity;

    highPrediction = this.predictions.isEmpty ? 0.0 : (this.predictions[0].center + this.predictions[0].upperBox) / 2;

    for(var p in this.predictions) {
      minValue = min(minValue, p.lowerWhisker);
      maxValue = max(maxValue, p.upperWhisker);
      minRating = min(minRating, p.shooter.rating);
      maxRating = max(maxRating, p.shooter.rating);
    }

    if(this.predictions.isNotEmpty && this.predictions.first.algorithm.supportsRatioFloor) {
      var ratingDelta = maxRating - minRating;
      percentFloor = this.predictions.first.algorithm.estimateRatioFloor(ratingDelta, settings: this.predictions.first.settings);
      percentMult = 1.0 - percentFloor;
    }
    if(notify) notifyListeners();
  }

  void setOutcomes(Map<AlgorithmPrediction, SimpleMatchResult> outcomes, {bool notify = true}) {
    this.outcomes = outcomes;
    if(notify) notifyListeners();
  }
}

class PredictionListHeader extends StatelessWidget {
  PredictionListHeader({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionViewModel>(context);
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 250 * uiScaleFactor,
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search"
                ),
                onChanged: (search) {
                  model.search(search);
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 15 * uiScaleFactor),
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              flex: PredictionListViewScreen._padding,
              child: Container(),
            ),
            Expanded(
              flex: PredictionListViewScreen._rowFlex,
              child: Text("Row"),
            ),
            Expanded(
              flex: PredictionListViewScreen._nameFlex,
              child: Text("Name"),
            ),
            Expanded(
              flex: PredictionListViewScreen._classFlex,
              child: Text("Class", textAlign: TextAlign.end),
            ),
            Expanded(
              flex: PredictionListViewScreen._ratingFlex,
              child: Text("Rating", textAlign: TextAlign.end),
            ),
            Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Tooltip(
                    message: "An estimated lower bound for a shooter's place finish, if he has a moderately bad day and everyone else has a moderately good one.",
                    child: Text("Low Place", textAlign: TextAlign.end)
                )
            ),
            Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Tooltip(
                    message: "An estimated middle of the range for a shooter's place finish, if he performs slightly above average and everyone else performs at"
                        "\nan average level.",
                    child: Text("Med. Place", textAlign: TextAlign.end)
                )
            ),
            Expanded(
              flex: PredictionListViewScreen._95ciFlex,
              child: Tooltip(
                  message: "An estimated upper bound for a shooter's place finish, if he has a good day and everyone else has a moderately bad one.",
                child: Text("High Place", textAlign: TextAlign.end)
              )
            ),
            if(model.hasOutcomes) Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Tooltip(
                  message: "The shooter's actual finish.",
                  child: Text("Actual Place", textAlign: TextAlign.end)
                )
            ),
            SizedBox(width: PredictionListViewScreen._whiskerPlotPadding),
            Expanded(
              flex: PredictionListViewScreen._whiskerPlotFlex,
              child: Tooltip(
                message: "Boxes show a prediction with about 65% confidence. Whiskers show a prediction with about 95% confidence.\n"
                    "Predicted performances are relative to one another. The percentage in each prediction's tooltip is an\n"
                    "approximate value, for reference only.",
                child: Text("Performance Prediction", textAlign: TextAlign.center),
              ),
            ),
            SizedBox(width: PredictionListViewScreen._whiskerPlotPadding),
          ]
        ),
      ],
    );
  }
}

class PredictionListRow extends StatelessWidget {
  PredictionListRow({super.key, required this.prediction, required this.index});
  final int index;
  final AlgorithmPrediction prediction;

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionViewModel>(context);
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    double renderMin = model.minValue * 0.95;
    double renderMax = model.maxValue * 1.01;

    double renderMinPercent = (model.percentFloor + renderMin / model.highPrediction * model.percentMult) * 100;
    double renderMaxPercent = (model.percentFloor + renderMax / model.highPrediction * model.percentMult) * 100;

    double boxLowPercent = (model.percentFloor + prediction.lowerBox / model.highPrediction * model.percentMult) * 100;
    double boxHighPercent = (model.percentFloor + prediction.upperBox / model.highPrediction * model.percentMult) * 100;
    double meanPercent = (model.percentFloor + prediction.mean / model.highPrediction * model.percentMult) * 100;
    double whiskerLowPercent = (model.percentFloor + prediction.lowerWhisker / model.highPrediction * model.percentMult) * 100;
    double whiskerHighPercent = (model.percentFloor + prediction.upperWhisker / model.highPrediction * model.percentMult) * 100;
    double? outcomePercent;

    List<double> referenceLines = [];
    var outcome = model.outcomes[prediction];
    if(outcome != null) {
      if(outcome.percent > 0.2) {
        outcomePercent = outcome.percent * 100;
        referenceLines = [outcomePercent];
      }
    }

    return ClickableLink(
      color: Theme.of(context).colorScheme.onSurface,
      underline: false,
      onTap: () {
        var latestEvent = prediction.shooter.eventsWithWindow(window: 1).firstOrNull;
        if(latestEvent != null) {
          var latestMatch = latestEvent.match;
          ShooterStatsDialog.show(context, prediction.shooter, match: latestMatch);
        }
      },
      child: ConstrainedBox(
        key: Key(prediction.shooter.memberNumber),
        constraints: BoxConstraints(
          minHeight: PredictionListViewScreen._rowHeight,
        ),
        child: ScoreRow(
          color: ThemeColors.backgroundColor(context, rowIndex: index),
          child: Row(
            children: [
              Expanded(
                flex: PredictionListViewScreen._padding,
                child: Container(),
              ),
              Expanded(
                flex: PredictionListViewScreen._rowFlex,
                child: Text("${index + 1}"),
              ),
              Expanded(
                flex: PredictionListViewScreen._nameFlex,
                child: GestureDetector(
                  onTap: () async {
                    var latestEvent = prediction.shooter.eventsWithWindow(window: 1).firstOrNull;
                    if(latestEvent != null) {
                      var latestMatch = latestEvent.match;
                      ShooterStatsDialog.show(context, prediction.shooter, match: latestMatch);
                    }
                  },
                  child: Text(prediction.shooter.getName(suffixes: false)),
                ),
              ),
              Expanded(
                flex: PredictionListViewScreen._classFlex,
                child: Text(prediction.shooter.lastClassification?.shortDisplayName ?? "(none)", textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionListViewScreen._ratingFlex,
                child: Text(prediction.shooter.rating.round().toString(), textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Text("${prediction.lowPlace}", textAlign: TextAlign.end), //Text("${whiskerLowPercent.toStringAsFixed(1)}", textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Text("${prediction.medianPlace}", textAlign: TextAlign.end), // Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
              ),
              Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Text("${prediction.highPlace}", textAlign: TextAlign.end), // Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
              ),
              if(model.hasOutcomes) Expanded(
                flex: PredictionListViewScreen._95ciFlex,
                child: Text("${outcome?.place ?? "n/a"}", textAlign: TextAlign.end), // Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
              ),
              SizedBox(width: PredictionListViewScreen._whiskerPlotPadding),
              Expanded(
                flex: PredictionListViewScreen._whiskerPlotFlex,
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
                    boxSize: 12 * uiScaleFactor,
                    strokeWidth: 1.5,
                    referenceLines: referenceLines,
                  ),
                )
              ),
              SizedBox(width: PredictionListViewScreen._whiskerPlotPadding),
            ],
          ),
        ),
      ),
    );
  }
}

class PredictionListView extends StatelessWidget {
  PredictionListView({super.key});

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<PredictionViewModel>(context);
    return Container(
      color: ThemeColors.backgroundColor(context),
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
              child: PredictionListHeader(),
            ),
          ),
          Expanded(
            child: ListView.builder(
                itemCount: model.searchedPredictions.length,
                itemBuilder: (context, i) {
                  return PredictionListRow(prediction: model.searchedPredictions[i], index: i);
                },
            ),
          )
        ],
      ),
    );
  }
}