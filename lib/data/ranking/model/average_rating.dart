class AverageRating {
  final double firstRating;
  final double minRating;
  final double maxRating;
  final double averageOfIntermediates;
  final int window;

  double get averageOfMinMax => (minRating + maxRating) / 2;

  AverageRating({
    required this.firstRating,
    required this.minRating,
    required this.maxRating,
    required this.averageOfIntermediates,
    required this.window,
  });
}