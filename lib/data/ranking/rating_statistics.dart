import 'package:shooting_sports_analyst/data/sport/model.dart';

class RaterStatistics {
  int shooters;
  double averageRating;
  double minRating;
  double maxRating;
  double medianRating;
  double averageHistory;
  int medianHistory;

  int histogramBucketSize;
  Map<int, int> histogram;

  Map<Classification, int> countByClass;
  Map<Classification, double> averageByClass;
  Map<Classification, double> minByClass;
  Map<Classification, double> maxByClass;

  Map<Classification, Map<int, int>> histogramsByClass;
  Map<Classification, List<double>> ratingsByClass;

  Map<int, int> yearOfEntryHistogram;

  RaterStatistics({
    required this.shooters,
    required this.averageRating,
    required this.minRating,
    required this.maxRating,
    required this.medianRating,
    required this.averageHistory,
    required this.medianHistory,
    required this.countByClass,
    required this.averageByClass,
    required this.minByClass,
    required this.maxByClass,
    required this.histogramBucketSize,
    required this.histogram,
    required this.histogramsByClass,
    required this.ratingsByClass,
    required this.yearOfEntryHistogram,
  });
}