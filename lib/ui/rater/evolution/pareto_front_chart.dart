/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/elo_evaluation.dart';
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

    double fXCenter = fXMax / 2;
    double fYCenter = fYMax / 2;

    double width = size.width - 10;
    double height = size.height - 25;
    double left = 25;
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

    p1 = Offset(left, yCenter);
    p2 = Offset(width, yCenter);
    canvas.drawLine(p1, p2, linePaint);

    p1 = Offset(xCenter, top);
    p2 = Offset(xCenter, height);
    canvas.drawLine(p1, p2, linePaint);

    var xMaxText = fXMax < 1 ? fXMax.toStringAsPrecision(2) : fXMax.toStringAsFixed(2);
    var xCenterText = fXCenter < 1 ? fXCenter.toStringAsPrecision(2) : fXCenter.toStringAsFixed(2);
    var yMaxText = fYMax < 1 ? fYMax.toStringAsPrecision(2) : fYMax.toStringAsFixed(2);
    var yCenterText = fYCenter < 1 ? fYCenter.toStringAsPrecision(2) : fYCenter.toStringAsFixed(2);

    TextPainter tp = TextPainter(
      text: TextSpan(text: xMaxText, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(width - tp.width, height + 4));

    tp = TextPainter(
      text: TextSpan(text: xCenterText, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(xCenter - tp.width / 2, height + 4));

    canvas.save();
    canvas.translate(left - 4, top);

    tp = TextPainter(
      text: TextSpan(text: yMaxText, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    canvas.translate(-tp.height, tp.width);
    canvas.rotate(-90 * pi/180);

    tp.paint(canvas, Offset(0, 0));
    canvas.restore();

    canvas.save();
    canvas.translate(left - 2, yCenter);

    tp = TextPainter(
      text: TextSpan(text: yCenterText, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    canvas.translate(-tp.height, tp.width / 2);
    canvas.rotate(-90 * pi/180);

    tp.paint(canvas, Offset(0, 0));
    canvas.restore();

    Paint preyPaint = Paint();
    preyPaint.strokeWidth = 0;
    preyPaint.color = Colors.black;

    Paint nondominatedPreyPaint = Paint();
    nondominatedPreyPaint.strokeWidth = 0;
    nondominatedPreyPaint.color = Colors.green.shade600;

    Paint highlightPaint = Paint();
    highlightPaint.strokeWidth = 0;
    highlightPaint.color = Colors.yellow.shade600;

    EloEvaluator? foundHighlight;
    for(var e in dominated) {
      if(e == highlight) {
        foundHighlight = e;
        continue;
      }
      var x = e.evaluations[fX]! * xConversion;
      var y = height - e.evaluations[fY]! * yConversion;

      canvas.drawCircle(Offset(left + x, y - top), 2.5, preyPaint);
    }
    for(var e in nondominated) {
      if(e == highlight) {
        foundHighlight = e;
        continue;
      }
      var x = e.evaluations[fX]! * xConversion;
      var y = height - e.evaluations[fY]! * yConversion;

      canvas.drawCircle(Offset(left + x, y - top), 2.5, nondominatedPreyPaint);
    }

    if(foundHighlight != null) {
      var x = foundHighlight.evaluations[fX]! * xConversion;
      var y = height - foundHighlight.evaluations[fY]! * yConversion;

      canvas.drawCircle(Offset(left + x, y - top), 2.5, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}