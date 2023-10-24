/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/evolution/predator_prey.dart';

class PredatorPreyView<P extends Prey> extends StatelessWidget {
  const PredatorPreyView({Key? key, required this.grid, required this.nonDominated, this.highlight}) : super(key: key);

  final GridEntity<P>? highlight;
  final PredatorPreyGrid<P> grid;
  final Set<P> nonDominated;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PredatorPreyGridPainter(grid, highlight, nonDominated),
    );
  }
}

class _PredatorPreyGridPainter<P extends Prey> extends CustomPainter {
  final PredatorPreyGrid<P> grid;
  final GridEntity<P>? highlight;
  final Set<P> nonDominated;

  _PredatorPreyGridPainter(this.grid, this.highlight, this.nonDominated);

  @override
  void paint(Canvas canvas, Size size) {
    double width = size.width - 4;
    double height = size.height - 4;
    double left = 2;
    double top = 2;

    // We need gridSize lines, plus a start and end border
    double hSpacing = size.width / (grid.gridSize + 1);
    double vSpacing = size.height / (grid.gridSize + 1);

    Paint bgPaint = Paint();
    bgPaint.strokeWidth = 0;
    bgPaint.color = Colors.white;
    bgPaint.style = PaintingStyle.fill;

    Paint whiskerPaint = Paint();
    whiskerPaint.strokeWidth = 0.5;
    whiskerPaint.color = Colors.grey.shade300;
    whiskerPaint.style = PaintingStyle.stroke;

    Paint borderPaint = Paint();
    borderPaint.strokeWidth = 2;
    borderPaint.color = Colors.grey.shade800;
    borderPaint.style = PaintingStyle.stroke;

    Paint predatorPaint = Paint();
    predatorPaint.strokeWidth = 0;
    predatorPaint.color = Colors.red.shade500;

    Paint preyPaint = Paint();
    preyPaint.strokeWidth = 0;
    preyPaint.color = Colors.black;

    Paint nondominatedPreyPaint = Paint();
    nondominatedPreyPaint.strokeWidth = 0;
    nondominatedPreyPaint.color = Colors.green.shade600;

    Paint highlightPaint = Paint();
    highlightPaint.strokeWidth = 0;
    highlightPaint.color = Colors.yellow.shade600;

    canvas.drawRect(Rect.fromLTWH(left, top, width, height), bgPaint);

    for(int i = 1; i <= grid.gridSize; i++) {
      // Left-to-right line
      Offset start = Offset(left, vSpacing * i);
      Offset end = Offset(width, vSpacing * i);
      canvas.drawLine(start, end, whiskerPaint);

      // Top-to-bottom line
      start = Offset(hSpacing * i, top);
      end = Offset(hSpacing * i, height);
      canvas.drawLine(start, end, whiskerPaint);
    }

    canvas.drawRect(Rect.fromLTWH(left, top, width, height), borderPaint);

    var prey = grid.prey;
    var preds = grid.predators;

    for(var p in prey) {
      var location = p.location;
      if(location != null) {
        Offset loc = Offset((location.x + 1) * hSpacing, (location.y + 1) * vSpacing);
        var paint = nonDominated.contains(p) ? nondominatedPreyPaint : preyPaint;
        paint = (p == highlight ? highlightPaint : paint);
        canvas.drawCircle(loc, 3, paint);
      }
    }
    for(var p in preds) {
      var location = p.location;
      if(location != null) {
        Offset loc = Offset((location.x + 1) * hSpacing, (location.y + 1) * vSpacing);
        canvas.drawCircle(loc, 3, predatorPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_PredatorPreyGridPainter oldDelegate) {
    return true;
  }

}