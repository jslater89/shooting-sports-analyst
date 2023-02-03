import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/predator_prey.dart';

class ParetoFrontChart extends StatelessWidget {
  const ParetoFrontChart({Key? key, required this.tuner, required this.fX, required this.fY, this.highlight}) : super(key: key);

  final EloTuner tuner;
  final EloEvalFunction fX;
  final EloEvalFunction fY;
  final EloEvaluator? highlight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ParetoFrontPainter(tuner, fX, fY, highlight),
    );
  }
}

class _ParetoFrontPainter extends CustomPainter {
  final EloTuner tuner;
  final EloEvalFunction fX;
  final EloEvalFunction fY;
  final EloEvaluator? highlight;

  _ParetoFrontPainter(this.tuner, this.fX, this.fY, this.highlight);

  @override
  void paint(Canvas canvas, Size size) {
    var evaluated = tuner.evaluatedPopulation;
    List<EloEvaluator> nondominated = [];
    List<EloEvaluator> dominated = [];

    double fXMax = 0;
    double fYMax = 0;

    for(var e in evaluated) {
      if(tuner.nonDominated.contains(e)) {
        nondominated.add(e);
      }
      else {
        dominated.add(e);
      }

      if(e.evaluations[fX]! > fXMax) fXMax = e.evaluations[fX]!;
      if(e.evaluations[fY]! > fYMax) fYMax = e.evaluations[fY]!;
    }

    fXMax *= 1.05;
    fYMax *= 1.1;

    double width = size.width - 10;
    double height = size.height - 10;
    double left = 10;
    double top = 10;

    double xRange = width - left;
    double yRange = height - top;

    double xCenter = left + xRange / 2;
    double yCenter = top + yRange / 2;

    double xConversion = xRange / fXMax;
    double yConversion = yRange / fYMax;

    Paint linePaint = Paint();
    linePaint.strokeWidth = 1;
    linePaint.color = Colors.grey.shade500;
    linePaint.style = PaintingStyle.stroke;

    Offset p1 = Offset(left, top);
    Offset p2 = Offset(left, height);
    canvas.drawLine(p1, p2, linePaint);

    p1 = Offset(left, height);
    p2 = Offset(width, height);
    canvas.drawLine(p1, p2, linePaint);

    Paint preyPaint = Paint();
    preyPaint.strokeWidth = 0;
    preyPaint.color = Colors.black;

    Paint nondominatedPreyPaint = Paint();
    nondominatedPreyPaint.strokeWidth = 0;
    nondominatedPreyPaint.color = Colors.green.shade600;

    Paint highlightPaint = Paint();
    highlightPaint.strokeWidth = 0;
    highlightPaint.color = Colors.yellow.shade600;

    for(var e in dominated) {
      var x = e.evaluations[fX]! * xConversion;
      var y = height - e.evaluations[fY]! * yConversion;

      var paint = (e == highlight) ? highlightPaint : preyPaint;
      canvas.drawCircle(Offset(x, y), 2.5, paint);
    }
    for(var e in nondominated) {
      var x = e.evaluations[fX]! * xConversion;
      var y = height - e.evaluations[fY]! * yConversion;

      var paint = (e == highlight) ? highlightPaint : nondominatedPreyPaint;
      canvas.drawCircle(Offset(x, y), 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}