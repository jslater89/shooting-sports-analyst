/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:data/stats.dart' show ContinuousDistribution;
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/distribution_tools.dart';
import 'package:shooting_sports_analyst/data/math/gamma/gamma_estimator.dart';
import 'package:shooting_sports_analyst/data/math/lognormal/lognormal_estimator.dart';
import 'package:shooting_sports_analyst/data/math/weibull/weibull_estimator.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RaterStatistics");

class RaterStatistics {
  int shooters;
  double averageRating;
  double minRating;
  double maxRating;
  double medianRating;
  double averageHistory;
  int medianHistory;

  int histogramBucketSize;

  /// Map of bucket-start to count.
  Map<int, int> histogram;

  Map<Classification, int> countByClass;
  Map<Classification, double> averageByClass;
  Map<Classification, double> minByClass;
  Map<Classification, double> maxByClass;

  /// Map of classifications to a map of bucket-start to count.
  Map<Classification, Map<int, int>> histogramsByClass;

  /// Map of classifications to a list of ratings.
  Map<Classification, List<double>> ratingsByClass;

  Map<int, int> yearOfEntryHistogram;

  ContinuousDistribution ratingDistribution;

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
    required this.ratingDistribution,
  });
}

// Map<int, RaterStatistics> _cachedStats = {};

RaterStatistics getRatingStatistics({
  required Sport sport,
  required RatingSystem algorithm,
  required RatingGroup group,
  required List<ShooterRating> ratings,
  ContinuousDistributionEstimator? estimator,
}) {
  var e = estimator ?? GammaEstimator();
  return _calculateStats(sport, algorithm, group, ratings, e);
}

RaterStatistics _calculateStats(Sport sport, RatingSystem algorithm, RatingGroup group, List<ShooterRating> ratings, ContinuousDistributionEstimator estimator) {
  var count = ratings.length;
  var allRatings = ratings.map((r) => r.rating).toList()..sort();

  var ratingDistribution = estimator.estimate(allRatings);
  _log.v("${estimator.runtimeType}: $ratingDistribution");

  _log.v("Fit tests:");
  _log.v("\tLog likelihood: ${ratingDistribution.logLikelihood(allRatings)}");
  _log.v("\tKolmogorov-Smirnov: ${ratingDistribution.kolmogorovSmirnovTest(allRatings)}");
  _log.v("\tChi-square: ${ratingDistribution.chiSquareTest(allRatings)}");
  _log.v("\tAnderson-Darling: ${ratingDistribution.andersonDarlingTest(allRatings)}");

  var allHistoryLengths = ratings.map((r) => r.length).toList()..sort(
    (a, b) => a.compareTo(b)
  );

  var ratingBucketSize = algorithm.histogramBucketSize(
    shooterCount: count,
    matchCount: allHistoryLengths.last, // the longest history works for this case
    minRating: allRatings.first,
    maxRating: allRatings.last,
  );

  var histogram = <int, int>{};
  var yearOfEntryHistogram = <int, int>{};

  for(var rating in ratings) {
    // Buckets 100 wide
    var bucket = (0 + (rating.rating / ratingBucketSize).floor());

    histogram.increment(bucket);

    var firstEvent = rating.firstSeen;
    yearOfEntryHistogram.increment(firstEvent.year);
  }

  var averagesByClass = <Classification, double>{};
  var minsByClass = <Classification, double>{};
  var maxesByClass = <Classification, double>{};
  var countsByClass = <Classification, int>{};
  Map<Classification, Map<int, int>> histogramsByClass = {};
  Map<Classification, List<double>> ratingsByClass = {};

  for(var classification in sport.classifications.values) {
    var shootersInClass = ratings.where((r) => r.lastClassification == classification);
    var ratingsInClass = shootersInClass.map((r) => r.rating);

    ratingsByClass[classification] = ratingsInClass.sorted((a, b) => a.compareTo(b));
    averagesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.average : 0;
    minsByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.min : 0;
    maxesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.max : 0;
    countsByClass[classification] = ratingsInClass.length;

    histogramsByClass[classification] = {};
    for(var rating in ratingsInClass) {
      // Buckets 100 wide
      var bucket = (0 + (rating / ratingBucketSize).floor());

      histogramsByClass[classification]!.increment(bucket);
    }
  }

  return RaterStatistics(
    shooters: count,
    averageRating: allRatings.average,
    medianRating: allRatings.median,
    minRating: allRatings.min,
    maxRating: allRatings.max,
    averageHistory: allHistoryLengths.average,
    medianHistory: allHistoryLengths.median,
    histogram: histogram,
    countByClass: countsByClass,
    averageByClass: averagesByClass,
    minByClass: minsByClass,
    maxByClass: maxesByClass,
    histogramsByClass: histogramsByClass,
    histogramBucketSize: ratingBucketSize,
    ratingsByClass: ratingsByClass,
    yearOfEntryHistogram: yearOfEntryHistogram,
    ratingDistribution: ratingDistribution,
  );
}
