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
    this.referenceLines = const [],
    this.referenceLineColor = Colors.green,
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

  final List<double> referenceLines;

  final double? rangeMin;
  final double? rangeMax;
  final double? boxSize;
  final double strokeWidth;
  final Color referenceLineColor;
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
      child: Padding(
        padding: EdgeInsets.all(strokeWidth / 2),
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
            referenceLines: referenceLines,
            referenceLineColor: referenceLineColor,
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
  final List<double> referenceLines;
  final Color referenceLineColor;

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
    required this.fillBox,
    required this.referenceLines,
    required this.referenceLineColor,
  });

  double height = 0.0;
  double width = 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    height = size.height;
    width = size.width;

    Paint linePaint = Paint();
    linePaint.strokeWidth = strokeWidth;
    linePaint.color = whiskerColor;
    linePaint.strokeCap = StrokeCap.butt;

    Paint contrastingLinePaint = Paint();
    contrastingLinePaint.strokeWidth = strokeWidth;
    contrastingLinePaint.color = whiskerColor;
    contrastingLinePaint.strokeCap = StrokeCap.butt;
    if(fillBox && (whiskerColor == upperBoxColor || whiskerColor == lowerBoxColor)) {
      contrastingLinePaint.color = Colors.white;
    }

    Paint lowerBoxPaint = Paint();
    lowerBoxPaint.strokeWidth = strokeWidth;
    lowerBoxPaint.strokeCap = StrokeCap.butt;
    lowerBoxPaint.color = lowerBoxColor;
    lowerBoxPaint.style = fillBox ? PaintingStyle.fill : PaintingStyle.stroke;

    Paint upperBoxPaint = Paint();
    upperBoxPaint.strokeWidth = strokeWidth;
    lowerBoxPaint.strokeCap = StrokeCap.butt;
    upperBoxPaint.color = upperBoxColor;
    upperBoxPaint.style = fillBox ? PaintingStyle.fill : PaintingStyle.stroke;

    // We'll draw the whiskers at this height
    var crossDimension = (direction == PlotDirection.horizontal ? size.height : size.width);
    var mainDimension = (direction == PlotDirection.horizontal ? size.width : size.height);
    double halfHeight = (crossDimension / 2).roundToDouble();

    Paint referenceLinePaint = Paint();
    referenceLinePaint.strokeWidth = strokeWidth;
    referenceLinePaint.color = referenceLineColor;
    referenceLinePaint.strokeCap = StrokeCap.butt;

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
      valueToPixel = mainDimension / range;
    }
    else {
      valueToPixel = mainDimension / (maximum - minimum);
    }

    // Put center and the whisker ends directly on a pixel, for more consistent appearance
    double lowerWhiskerStart = ((minimum - leftEdge) * valueToPixel).roundToDouble();
    double lowerWhiskerEnd = ((lowerQuartile - leftEdge) * valueToPixel).roundToDouble();
    double center = ((median - leftEdge) * valueToPixel).roundToDouble();
    double upperWhiskerStart = ((upperQuartile - leftEdge) * valueToPixel).roundToDouble();
    double upperWhiskerEnd = ((maximum - leftEdge) * valueToPixel).roundToDouble();

    var lines = [];
    for(var line in referenceLines) {
      lines.add(((line - leftEdge) * valueToPixel).roundToDouble());
    }
    
    double crossStart = 0.0;
    double crossEnd = crossDimension;

    canvas.drawLine(_offsetFor(lowerWhiskerStart, crossStart), _offsetFor(lowerWhiskerStart, crossEnd), linePaint);
    canvas.drawLine(_offsetFor(lowerWhiskerStart, halfHeight), _offsetFor(lowerWhiskerEnd, halfHeight), linePaint);

    if(fillBox) {
      canvas.drawRect(Rect.fromPoints(_offsetFor(lowerWhiskerEnd, crossStart), _offsetFor(center, crossEnd)), lowerBoxPaint);
      canvas.drawRect(Rect.fromPoints(_offsetFor(center, crossStart), _offsetFor(upperWhiskerStart, crossEnd)), upperBoxPaint);
    }
    else {
      // crosspiece
      canvas.drawLine(_offsetFor(lowerWhiskerEnd, crossStart), _offsetFor(lowerWhiskerEnd, crossEnd), lowerBoxPaint);
      // box sides
      canvas.drawLine(_offsetFor(lowerWhiskerEnd - strokeWidth / 2, crossStart), _offsetFor(center, crossStart), lowerBoxPaint);
      canvas.drawLine(_offsetFor(lowerWhiskerEnd - strokeWidth / 2, crossEnd), _offsetFor(center, crossEnd), lowerBoxPaint);

      canvas.drawLine(_offsetFor(upperWhiskerStart, crossStart), _offsetFor(upperWhiskerStart, crossEnd), upperBoxPaint);
      canvas.drawLine(_offsetFor(center, crossStart), _offsetFor(upperWhiskerStart + strokeWidth / 2, crossStart), upperBoxPaint);
      canvas.drawLine(_offsetFor(center, crossEnd), _offsetFor(upperWhiskerStart + strokeWidth / 2, crossEnd), upperBoxPaint);
    }

    canvas.drawLine(_offsetFor(center, crossStart), _offsetFor(center, crossEnd), contrastingLinePaint);

    canvas.drawLine(_offsetFor(upperWhiskerEnd, crossStart), _offsetFor(upperWhiskerEnd, crossEnd), linePaint);
    canvas.drawLine(_offsetFor(upperWhiskerStart, halfHeight), _offsetFor(upperWhiskerEnd, halfHeight), linePaint);

    for(var line in lines) {
      canvas.drawLine(_offsetFor(line, crossStart), _offsetFor(line, crossEnd), referenceLinePaint);
    }
  }


  /// [main] is the value along the axis of interest. [cross] is the value
  /// across the axis of interest (the height of the box/whiskers if horizontal),
  /// [direction] is the direction of the plot.
  Offset _offsetFor(double main, double cross) {
    return Offset(
      direction == PlotDirection.horizontal ? main : cross,
      direction == PlotDirection.horizontal ? cross : height - main,
    );
  }

  @override
  bool shouldRepaint(covariant _BoxPlotPainter o) {
    return o.median != median
      || o.minimum != minimum
      || o.maximum != maximum
      || o.lowerQuartile != lowerQuartile
      || o.upperQuartile != upperQuartile
      || o.fillBox != fillBox
      || o.direction != direction
      || o.lowerBoxColor != lowerBoxColor
      || o.upperBoxColor != upperBoxColor
      || o.whiskerColor != whiskerColor
      || o.rangeMin != rangeMin
      || o.rangeMax != rangeMax
      || strokeWidth != strokeWidth
    ;
  }
  
}

enum PlotDirection {
  horizontal,
  vertical,
}