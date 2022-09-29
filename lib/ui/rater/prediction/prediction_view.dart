import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uspsa_result_viewer/data/ranking/prediction/match_prediction.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/widget/box_and_whisker.dart';
import 'package:uspsa_result_viewer/ui/widget/score_row.dart';

class PredictionView extends StatelessWidget {
  const PredictionView({Key? key, required this.predictions}) : super(key: key);

  final List<ShooterPrediction> predictions;

  @override
  Widget build(BuildContext context) {
    double minValue = 10000;
    double maxValue = -10000;

    final backgroundColor = Colors.white;

    var sortedPredictions = predictions.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
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
          Tooltip(
            message: "Download predictions as CSV",
            child: IconButton(
              icon: Icon(Icons.save_alt),
              onPressed: () async {
                String contents = "Name,Member Number,Class,5%,35%,Mean,65%,95%\n";

                for(var pred in sortedPredictions) {
                  double midLow = (_percentFloor + pred.lowerBox / highPrediction * _percentMult) * 100;
                  double midHigh = (_percentFloor + pred.upperBox / highPrediction * _percentMult) * 100;
                  double mean = (_percentFloor + pred.center / highPrediction * _percentMult) * 100;
                  double low = (_percentFloor + pred.lowerWhisker / highPrediction * _percentMult) * 100;
                  double high = (_percentFloor + pred.upperWhisker / highPrediction * _percentMult) * 100;

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
                  itemCount: predictions.length,
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

  Widget _buildPredictionsHeader() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          flex: _padding,
          child: Container(),
        ),
        Expanded(
          flex: _nameFlex,
          child: Text("Name"),
        ),
        Expanded(
          flex: _classFlex,
          child: Text("Class", textAlign: TextAlign.end),
        ),
        Expanded(
          flex: _ratingFlex,
          child: Text("Rating", textAlign: TextAlign.end),
        ),
        Expanded(
            flex: _95ciFlex,
            child: Tooltip(
                message: "The approximate percentage corresponding to the lower bound of the algorithm's 95% confidence interval.",
                child: Text("5% CI", textAlign: TextAlign.end)
            )
        ),
        Expanded(
          flex: _95ciFlex,
          child: Tooltip(
              message: "The approximate percentage corresponding to the upper bound of the algorithm's 95% confidence interval.",
            child: Text("95% CI", textAlign: TextAlign.end)
          )
        ),
        SizedBox(width: _whiskerPlotPadding),
        Expanded(
          flex: _whiskerPlotFlex,
          child: Tooltip(
            message: "Boxes show a prediction with about 65% confidence. Whiskers show a prediction with about 95% confidence.\n"
                "Predicted performances are relative to one another. The percentage in each prediction's tooltip is an\n"
                "approximate value, for reference only.",
            child: Text("Performance Prediction", textAlign: TextAlign.center),
          ),
        ),
        SizedBox(width: _whiskerPlotPadding),
      ]
    );
  }

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

  Widget _buildPredictionsRow(ShooterPrediction pred, double min, double max, double highPrediction, int index) {
    double renderMin = min * 0.95;
    double renderMax = max * 1.01;

    double boxLowPercent = (_percentFloor + pred.lowerBox / highPrediction * _percentMult) * 100;
    double boxHighPercent = (_percentFloor + pred.upperBox / highPrediction * _percentMult) * 100;
    double whiskerLowPercent = (_percentFloor + pred.lowerWhisker / highPrediction * _percentMult) * 100;
    double whiskerHighPercent = (_percentFloor + pred.upperWhisker / highPrediction * _percentMult) * 100;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: _rowHeight,
      ),
      child: ScoreRow(
        color: (index - 1) % 2 == 1 ? Colors.grey[200] : Colors.white,
        child: Row(
          children: [
            Expanded(
              flex: _padding,
              child: Container(),
            ),
            Expanded(
              flex: _nameFlex,
              child: Text(pred.shooter.shooter.getName(suffixes: false)),
            ),
            Expanded(
              flex: _classFlex,
              child: Text(pred.shooter.lastClassification.name, textAlign: TextAlign.end),
            ),
            Expanded(
              flex: _ratingFlex,
              child: Text(pred.shooter.rating.round().toString(), textAlign: TextAlign.end),
            ),
            Expanded(
              flex: _95ciFlex,
              child: Text("${whiskerLowPercent.toStringAsFixed(1)}", textAlign: TextAlign.end),
            ),
            Expanded(
              flex: _95ciFlex,
              child: Text("${whiskerHighPercent.toStringAsFixed(1)}%", textAlign: TextAlign.end),
            ),
            SizedBox(width: _whiskerPlotPadding),
            Expanded(
              flex: _whiskerPlotFlex,
              child: Tooltip(
                message: "68% confidence: ${boxLowPercent.toStringAsFixed(1)}-${boxHighPercent.toStringAsFixed(1)}%\n"
                    "95% confidence: ${whiskerLowPercent.toStringAsFixed(1)}-${whiskerHighPercent.toStringAsFixed(1)}%",
                child: BoxAndWhiskerPlot(
                  minimum: pred.lowerWhisker,
                  lowerQuartile: pred.lowerBox,
                  median: pred.center,
                  upperQuartile: pred.upperBox,
                  maximum: pred.upperWhisker,
                  direction: PlotDirection.horizontal,
                  rangeMin: renderMin,
                  rangeMax: renderMax,
                  fillBox: true,
                  boxSize: 12,
                  strokeWidth: 1.5,
                ),
              )
            ),
            SizedBox(width: _whiskerPlotPadding),
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