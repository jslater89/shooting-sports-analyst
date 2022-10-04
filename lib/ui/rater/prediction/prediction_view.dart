import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/ranking/prediction/match_prediction.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/route/match_select.dart';
import 'package:uspsa_result_viewer/ui/widget/box_and_whisker.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';

class PredictionView extends StatefulWidget {
  const PredictionView({Key? key, required this.rater, required this.predictions}) : super(key: key);

  /// The rater that generated the predictions.
  final Rater rater;

  /// The predictions.
  final List<ShooterPrediction> predictions;

  @override
  State<PredictionView> createState() => _PredictionViewState();

  static const int _padding = 2;
  static const int _nameFlex = 8;
  static const int _classFlex = 2;
  static const int _ratingFlex = 2;
  static const int _95ciFlex = 3;
  static const int _whiskerPlotFlex = 20;
  static const double _whiskerPlotPadding = 20;
  static const double _rowHeight = 20;
  static const double _percentFloor = 0.25;
  static const double _percentMult = 1 - _percentFloor;
}

class _PredictionViewState extends State<PredictionView> {
  Map<ShooterPrediction, SimpleMatchResult> outcomes = {};

  @override
  Widget build(BuildContext context) {
    double minValue = 10000;
    double maxValue = -10000;

    final backgroundColor = Colors.white;

    var sortedPredictions = widget.predictions.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
    var highPrediction = sortedPredictions.isEmpty ? 0.0 : (sortedPredictions[0].center + sortedPredictions[0].upperBox) / 2;

    if(sortedPredictions.isNotEmpty) {
      minValue = sortedPredictions.last.lowerWhisker;
      maxValue = sortedPredictions.first.upperWhisker;
    }

    return Scaffold(
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
            message: "Download predictions as CSV",
            child: IconButton(
              icon: Icon(Icons.save_alt),
              onPressed: () async {
                String contents = "Name,Member Number,Class,5%,35%,Mean,65%,95%\n";

                for(var pred in sortedPredictions) {
                  double midLow = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
                  double midHigh = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
                  double mean = (PredictionView._percentFloor + pred.center / highPrediction * PredictionView._percentMult) * 100;
                  double low = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
                  double high = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;

                  contents += "${pred.shooter.shooter.getName(suffixes: false)},";
                  contents += "${pred.shooter.shooter.memberNumber},";
                  contents += "${pred.shooter.lastClassification.name},";
                  contents += "$low,$midLow,$mean,$midHigh,$high\n";
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
                  bottom: BorderSide(),
                ),
                color: Colors.white,
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: _buildPredictionsHeader(),
              ),
            ),
            Expanded(
              child: ListView.builder(
                  itemCount: widget.predictions.length,
                  itemBuilder: (context, i) {
                    return _buildPredictionsRow(sortedPredictions[i], minValue, maxValue, highPrediction, i);
                  },
              ),
            )
          ],
        ),
      ),
    );
  }

  void _validate(double highPrediction) async {
    await MatchCache().ready;

    var matchUrl = await getMatchUrl(context);

    if(matchUrl == null) return;

    var match = await MatchCache().getMatch(matchUrl);
    if(match == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to retrieve match")));
      return;
    }

    var filters = widget.rater.filters!;
    var shooters = match.filterShooters(
      filterMode: filters.mode,
      divisions: filters.activeDivisions.toList(),
      powerFactors: [],
      classes: [],
      allowReentries: false,
    );
    var scores = match.getScores(
      shooters: shooters,
      scoreDQ: false,
    );

    var matchScores = <ShooterRating, RelativeScore>{};
    List<ShooterRating> knownShooters = [];

    // Some raters may demand the same number of predictions
    // and shooters to get the expected/actual score calculation
    // correct. Only add shooters for which we have ratings,
    // predictions, and scores.
    for(var shooter in shooters) {
      var rating = widget.rater.ratingFor(shooter);
      if(rating != null) {
        var score = scores.firstWhereOrNull((element) => element.shooter == shooter);
        var prediction = widget.predictions.firstWhereOrNull((element) => element.shooter == rating);
        if(score != null && prediction != null) {
          matchScores[rating] = score.total;
          knownShooters.add(rating);
        }
      }
      else {
        print("No rating for ${shooter.getName(suffixes: false)}");
      }
    }

    print("Registrants: ${shooters.length} Predictions: ${shooters.length} Matched: ${knownShooters.length}");

    var outcome = widget.rater.ratingSystem.validate(
        shooters: knownShooters,
        scores: matchScores,
        matchScores: matchScores,
        predictions: widget.predictions
    );

    int correct68 = 0;
    int correct95 = 0;
    int total = 0;
    for(var pred in widget.predictions) {
      double boxLowPercent = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
      double whiskerLowPercent = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
      double whiskerHighPercent = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;
      double boxHighPercent = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
      double? outcomePercent;

      if(outcome.actualResults[pred] != null) {
        total += 1;
        outcomePercent = outcome.actualResults[pred]!.percent * 100;
        if(outcomePercent >= whiskerLowPercent && outcomePercent <= whiskerHighPercent) correct95 += 1;
        if(outcomePercent >= boxLowPercent && outcomePercent <= boxHighPercent) correct68 += 1;
      }
    }
    print("Pct. correct: $correct68/$correct95/$total (${(correct68 / total * 100).toStringAsFixed(1)}%/${(correct95 / total * 100).toStringAsFixed(1)}%)");

    setState(() {
      outcomes = outcome.actualResults;
    });
  }

  Widget _buildPredictionsHeader() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          flex: PredictionView._padding,
          child: Container(),
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
                message: "The approximate percentage corresponding to the lower bound of the algorithm's 95% confidence interval.",
                child: Text("5% CI", textAlign: TextAlign.end)
            )
        ),
        Expanded(
          flex: PredictionView._95ciFlex,
          child: Tooltip(
              message: "The approximate percentage corresponding to the upper bound of the algorithm's 95% confidence interval.",
            child: Text("95% CI", textAlign: TextAlign.end)
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
    );
  }

  Widget _buildPredictionsRow(ShooterPrediction pred, double min, double max, double highPrediction, int index) {
    double renderMin = min * 0.95;
    double renderMax = max * 1.01;

    double boxLowPercent = (PredictionView._percentFloor + pred.lowerBox / highPrediction * PredictionView._percentMult) * 100;
    double boxHighPercent = (PredictionView._percentFloor + pred.upperBox / highPrediction * PredictionView._percentMult) * 100;
    double meanPercent = (PredictionView._percentFloor + pred.mean / highPrediction * PredictionView._percentMult) * 100;
    double whiskerLowPercent = (PredictionView._percentFloor + pred.lowerWhisker / highPrediction * PredictionView._percentMult) * 100;
    double whiskerHighPercent = (PredictionView._percentFloor + pred.upperWhisker / highPrediction * PredictionView._percentMult) * 100;
    double? outcomePercent;

    List<double> referenceLines = [];
    var outcome = outcomes[pred];
    if(outcome != null && outcome.percent > 0.2) {
      outcomePercent = outcome.percent * 100;
      referenceLines = [outcome.raterScore];
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: PredictionView._rowHeight,
      ),
      child: ScoreRow(
        color: (index - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
        child: Row(
          children: [
            Expanded(
              flex: PredictionView._padding,
              child: Container(),
            ),
            Expanded(
              flex: PredictionView._nameFlex,
              child: Text(pred.shooter.shooter.getName(suffixes: false)),
            ),
            Expanded(
              flex: PredictionView._classFlex,
              child: Text(pred.shooter.lastClassification.name, textAlign: TextAlign.end),
            ),
            Expanded(
              flex: PredictionView._ratingFlex,
              child: Text(pred.shooter.rating.round().toString(), textAlign: TextAlign.end),
            ),
            Expanded(
              flex: PredictionView._95ciFlex,
              child: Text("${whiskerLowPercent.toStringAsFixed(1)}", textAlign: TextAlign.end),
            ),
            Expanded(
              flex: PredictionView._95ciFlex,
              child: Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
            ),
            SizedBox(width: PredictionView._whiskerPlotPadding),
            Expanded(
              flex: PredictionView._whiskerPlotFlex,
              child: Tooltip(
                message: "68% confidence: ${boxLowPercent.toStringAsFixed(1)}-${boxHighPercent.toStringAsFixed(1)}%\n"
                    "95% confidence: ${whiskerLowPercent.toStringAsFixed(1)}-${whiskerHighPercent.toStringAsFixed(1)}%" + (
                    outcomePercent != null ? "\nOutcome: ${outcomePercent.toStringAsFixed(1)}%" : ""),
                child: BoxAndWhiskerPlot(
                  minimum: pred.lowerWhisker,
                  lowerQuartile: pred.lowerBox,
                  median: pred.mean,
                  upperQuartile: pred.upperBox,
                  maximum: pred.upperWhisker,
                  direction: PlotDirection.horizontal,
                  rangeMin: renderMin,
                  rangeMax: renderMax,
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
    );
  }
}

extension _PredictionMaths on ShooterPrediction {
  double get center => mean;
  double get upperBox => mean + oneSigma + shift;
  double get lowerBox => mean - oneSigma + shift;
  double get upperWhisker => mean + twoSigma + shift;
  double get lowerWhisker => mean - twoSigma + shift;
}