import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uspsa_result_viewer/data/ranking/prediction/match_prediction.dart';
import 'package:uspsa_result_viewer/ui/widget/box_and_whisker.dart';

class PredictionView extends StatelessWidget {
  const PredictionView({Key? key, required this.predictions}) : super(key: key);

  final List<ShooterPrediction> predictions;

  @override
  Widget build(BuildContext context) {
    double minValue = 10000;
    double maxValue = -10000;

    for(var prediction in predictions) {
      var predMax = prediction.upperWhisker;
      var predMin = prediction.lowerWhisker;
      if(predMax > maxValue) maxValue = predMax;
      if(predMax < minValue) minValue = predMin;
    }

    maxValue *= 1.01;
    minValue *= 0.99;

    final backgroundColor = Colors.white;

    var sortedPredictions = predictions.sorted((a, b) => b.ordinal.compareTo(a.ordinal));
    var windows = MediaQuery.of(context).size.width ~/ 8.6;
    var rangePerWindow = (maxValue - minValue) / windows;

    return Scaffold(
      appBar: AppBar(
        title: Text("Predictions"),
        centerTitle: true,
      ),
      body: Container(
        color: backgroundColor,
        child: Column(
          children: [
            // header
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: ListView.separated(
                  itemCount: predictions.length,
                  itemBuilder: (context, i) {
                    return _buildPredictionsRow(sortedPredictions[i], windows, rangePerWindow, minValue, maxValue);
                  },
                  separatorBuilder: (context, _i) {
                    return Divider();
                  }
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  static const int _nameFlex = 1;
  static const int _whiskerPlotFlex = 5;

  Widget _buildPredictionsRow(ShooterPrediction pred, int windows, double rangePerWindow, double min, double max) {
    return Row(
      children: [
        Expanded(
          flex: _nameFlex,
          child: Text(pred.shooter.shooter.getName(suffixes: false)),
        ),
        Expanded(
          // Text(_whiskerPlot(pred, windows, rangePerWindow, min), style: GoogleFonts.inconsolata())
          flex: _whiskerPlotFlex,
          child: BoxAndWhiskerPlot(
            minimum: pred.lowerWhisker,
            lowerQuartile: pred.lowerBox,
            median: pred.center,
            upperQuartile: pred.upperBox,
            maximum: pred.upperWhisker,
            direction: PlotDirection.horizontal,
            rangeMin: min,
            rangeMax: max,
            fillBox: true,
            boxSize: 12,
          )
        )
      ],
    );
  }

  String _whiskerPlot(ShooterPrediction pred, int windows, double rangePerWindow, double min) {
    double currentPosition = min;
    int windowsVisited = 0;
    String plot = "";

    while(windowsVisited <= windows) {
      double windowHigh = currentPosition;
      double windowLow = currentPosition - rangePerWindow;

      if(pred.center.between(windowLow, windowHigh) || pred.upperWhisker.between(windowLow, windowHigh) || pred.lowerWhisker.between(windowLow, windowHigh)) {
        plot += "|";
      }
      else if(pred.lowerWhisker <= 0.0 && (0.0).between(windowLow, windowHigh)) {
        plot += "|";
      }
      else if (pred.upperBox.between(windowLow, windowHigh) || pred.lowerBox.between(windowLow, windowHigh)) {
        plot += "=";
      }
      else if(windowHigh <= pred.upperWhisker && windowLow >= pred.upperBox) {
        plot += "-";
      }
      else if(windowHigh <= pred.upperBox && windowLow >= pred.lowerBox) {
        plot += "=";
      }
      else if(windowHigh <= pred.lowerBox && windowLow >= pred.lowerWhisker) {
        plot += "-";
      }
      else {
        plot += " ";
      }

      windowsVisited += 1;
      currentPosition += rangePerWindow;
    }

    return plot;
  }
}

extension _Between on double {
  bool between(double min, double max) {
    return this <= max && this >= min;
  }
}

extension _PredictionMaths on ShooterPrediction {
  double get center => mean;
  double get upperBox => mean + oneSigma + shift;
  double get lowerBox => mean - oneSigma + shift;
  double get upperWhisker => mean + twoSigma + shift;
  double get lowerWhisker => mean - twoSigma + shift;
}