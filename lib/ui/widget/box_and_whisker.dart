import 'package:flutter/material.dart';

class BoxAndWhiskerPlot extends StatelessWidget {
  const BoxAndWhiskerPlot({
    Key? key,
    required this.minimum,
    required this.lowerQuartile,
    required this.median,
    required this.upperQuartile,
    required this.maximum,
    this.direction = PlotDirection.horizontal,
    this.rangeMin,
    this.rangeMax,
    this.boxSize,
    this.whiskerColor = Colors.black,
    this.lowerBoxColor = Colors.black,
    this.upperBoxColor = Colors.black,
    this.strokeWidth = 1.0,
    this.fillBox = false,
  }) : super(key: key);

  final double minimum;
  final double lowerQuartile;
  final double median;
  final double upperQuartile;
  final double maximum;

  final PlotDirection direction;

  final double? rangeMin;
  final double? rangeMax;
  final double? boxSize;
  final double strokeWidth;
  final Color whiskerColor;
  final Color lowerBoxColor;
  final Color upperBoxColor;
  final bool fillBox;

  @override
  Widget build(BuildContext context) {
    var ownSize = MediaQuery.of(context).size;

    var height = boxSize ?? ownSize.height;
    var width = ownSize.width;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: CustomPaint(
          size: Size(width, height),
          painter: _BoxPlotPainter(
            direction: direction,
            fillBox: fillBox,
            lowerBoxColor: lowerBoxColor,
            lowerQuartile: lowerQuartile,
            maximum: maximum,
            median: median,
            minimum: minimum,
            rangeMax: rangeMax,
            rangeMin: rangeMin,
            strokeWidth: strokeWidth,
            upperBoxColor: upperBoxColor,
            upperQuartile: upperQuartile,
            whiskerColor: whiskerColor,
          ),
        ),
      ),
    );
  }
}

class _BoxPlotPainter extends CustomPainter {

  final double minimum;
  final double lowerQuartile;
  final double median;
  final double upperQuartile;
  final double maximum;

  final PlotDirection direction;

  final double? rangeMin;
  final double? rangeMax;
  final double strokeWidth;
  final Color whiskerColor;
  final Color lowerBoxColor;
  final Color upperBoxColor;
  final bool fillBox;

  _BoxPlotPainter({
    required this.minimum,
    required this.lowerQuartile,
    required this.median,
    required this.upperQuartile,
    required this.maximum,
    required this.direction,
    required this.rangeMin,
    required this.rangeMax,
    required this.strokeWidth,
    required this.whiskerColor,
    required this.lowerBoxColor,
    required this.upperBoxColor,
    required this.fillBox
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if(direction == PlotDirection.horizontal) {
      Paint linePaint = Paint();
      linePaint.strokeWidth = strokeWidth;
      linePaint.color = whiskerColor;

      Paint contrastingLinePaint = Paint();
      contrastingLinePaint.strokeWidth = strokeWidth;
      contrastingLinePaint.color = whiskerColor;
      if(fillBox && whiskerColor == upperBoxColor || whiskerColor == lowerBoxColor) {
        contrastingLinePaint.color = Colors.white;
      }

      Paint lowerBoxPaint = Paint();
      lowerBoxPaint.strokeWidth = strokeWidth;
      lowerBoxPaint.color = lowerBoxColor;
      lowerBoxPaint.style = fillBox ? PaintingStyle.fill : PaintingStyle.stroke;

      Paint upperBoxPaint = Paint();
      upperBoxPaint.strokeWidth = strokeWidth;
      upperBoxPaint.color = upperBoxColor;
      upperBoxPaint.style = fillBox ? PaintingStyle.fill : PaintingStyle.stroke;

      // We'll draw the whiskers at this height
      double halfHeight = size.height / 2;

      // The ratio of values to pixels
      double valueToPixel = 0.0;

      double range;
      if(rangeMin != null) {
        if(rangeMax == null) {
          throw ArgumentError("If rangeMin is provided, rangeMax must not be null");
        }
        if(rangeMax! < rangeMin!) {
          throw ArgumentError("rangeMax must be greater than rangeMin");
        }
        range = rangeMax! - rangeMin!;
      }
      else {
        range = maximum - minimum;
      }

      var leftEdge = rangeMin ?? 0.0;

      if(rangeMax != null && rangeMin != null && rangeMax! > rangeMin!) {
        valueToPixel = size.width / range;
      }
      else {
        valueToPixel = size.width / (maximum - minimum);
      }

      // Put center and the whisker ends directly on a pixel, for more consistent appearance
      double lowerWhiskerStart = ((minimum - leftEdge) * valueToPixel).roundToDouble();
      double lowerWhiskerEnd = (lowerQuartile - leftEdge) * valueToPixel;
      double center = ((median - leftEdge) * valueToPixel).roundToDouble();
      double upperWhiskerStart = (upperQuartile - leftEdge) * valueToPixel;
      double upperWhiskerEnd = ((maximum - leftEdge) * valueToPixel).roundToDouble();

      canvas.drawLine(Offset(lowerWhiskerStart, 0), Offset(lowerWhiskerStart, size.height), linePaint);
      canvas.drawLine(Offset(lowerWhiskerStart, halfHeight), Offset(lowerWhiskerEnd, halfHeight), linePaint);
      canvas.drawRect(Rect.fromPoints(Offset(lowerWhiskerEnd, 0), Offset(center, size.height)), lowerBoxPaint);
      canvas.drawRect(Rect.fromPoints(Offset(center, 0), Offset(upperWhiskerStart, size.height)), upperBoxPaint);
      canvas.drawLine(Offset(center, 0), Offset(center, size.height), contrastingLinePaint);
      canvas.drawLine(Offset(upperWhiskerEnd, 0), Offset(upperWhiskerEnd, size.height), linePaint);
      canvas.drawLine(Offset(upperWhiskerStart, halfHeight), Offset(upperWhiskerEnd, halfHeight), linePaint);
    }
    else {
      throw UnimplementedError();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
  
}

enum PlotDirection {
  horizontal,
  vertical,
}