/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart' hide IterableNumberExtension;
import 'package:data/data.dart' show IterableNumExtension, WeibullDistribution;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/math/weibull/weibull_estimator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/old_search_query_parser.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/display_settings.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';

SSALogger _log = SSALogger("RaterView");

// TODO: this will have to be (more) stateful
// Tab views get discarded after every switch. Replace
// the filter parameters with a Provider, use the Provider to prod
// the RatingDataSource, load more as needed when scrolling, etc.
//
// Alternately, provide a cached data source at the RaterView level that loads
// them all, or (sigh) switch from the array-data model to the
// typed-members-data model, at least for things we want to sort on.
class RaterView extends StatefulWidget {
  const RaterView({
    Key? key,
    required this.sport,
    required this.dataSource,
    required this.group,
    required this.currentMatch,
    this.search, this.maxAge, this.minRatings = 0,
    this.sortMode = RatingSortMode.rating,
    required this.filters,
    this.onRatingsFiltered,
    this.hiddenShooters = const [],
    this.changeSince,
  }) : super(key: key);

  final Sport sport;
  final String? search;
  final Duration? maxAge;
  final DateTime? changeSince;
  final RatingFilters filters;
  final int minRatings;
  final RatingDataSource dataSource;
  final RatingGroup group;
  final ShootingMatch currentMatch;
  final RatingSortMode sortMode;

  /// A list of shooters to hide from the results. Entries are member numbers.
  final List<String> hiddenShooters;

  final void Function(List<ShooterRating>)? onRatingsFiltered;

  @override
  State<RaterView> createState() => _RaterViewState();
}

class _RaterViewState extends State<RaterView> {
  late RatingProjectSettings settings;
  late List<RatingGroup> groups;
  late List<ShooterRating> uniqueRatings;
  List<double> allRatings = [];

  WeibullDistribution? ratingDistribution;
  ShooterRating? minRating;
  ShooterRating? maxRating;
  double? top2PercentAverage;
  double? ratingMean;
  double? ratingStdDev;

  bool initialized = false;

  @override
  Widget build(BuildContext context) {
    var cachedSource = Provider.of<ChangeNotifierRatingDataSource>(context);

    var scaler = Provider.of<RaterViewDisplayModel>(context).scaler;
    var scaleRatings = scaler != null;

    var s = cachedSource.getSettings();
    var g = cachedSource.getGroups();

    // TODO: lean on state/DB for this eventually?
    var ratings = cachedSource.getRatings(widget.group);
    if(s == null || g == null || ratings == null) {
      return _progressCircle();
    }
    else {
      if(!initialized) {
        _log.i("Loading cached ratings for ${widget.group}");
        settings = s;
        groups = g;
        if(scaleRatings) {
          _log.i("Generating scaled rating data");
          uniqueRatings = ratings.map((e) => settings.algorithm.wrapDbRating(e)).sorted((a, b) => b.rating.compareTo(a.rating));
          allRatings = uniqueRatings.map((e) => e.rating).toList();
          ratingDistribution = WeibullEstimator().estimate(allRatings);
          minRating = uniqueRatings.last;
          maxRating = uniqueRatings.first;
          var top2PercentRatings = allRatings.take(min(allRatings.length, max(5, (allRatings.length * 0.02).round()))).toList();
          top2PercentAverage = top2PercentRatings.average();
          ratingMean = allRatings.average();
          ratingStdDev = allRatings.standardDeviation();

          _log.v("Weibull parameters: k = ${ratingDistribution!.shape}, lambda = ${ratingDistribution!.scale}, P99.5 = ${ratingDistribution!.inverseCumulativeProbability(0.995)}");
          _log.v("Min rating: ${minRating!.rating}, max rating: ${maxRating!.rating}, top 2% average: $top2PercentAverage");
        }
        else {
          uniqueRatings = ratings.map((e) => settings.algorithm.wrapDbRating(e)).toList();
        }
        initialized = true;
      }
      // settings = s;
      // groups = g;
      // var wrappedRatings = [
      //   for(var r in ratings)
      //     settings.algorithm.wrapDbRating(r)
      // ];
      setState(() {
        settings = s;
        groups = g;
      });
    }

    return Column(
      children: [
        ..._buildRatingKey(),
        ..._buildRatingRows(scaler),
      ]
    );
  }

  Widget _progressCircle() {
    return Center(
      child: SizedBox(
        width: 64,
        height: 64,
        child: CircularProgressIndicator(value: null),
      ),
    );
  }

  var _scrollController = ScrollController();

  List<Widget> _buildRatingKey() {
    var screenSize = MediaQuery.of(context).size;
    return [ConstrainedBox(
      constraints: BoxConstraints(
          minWidth: 1024,
          maxWidth: max(screenSize.width, 1024)
      ),
      child: Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide()
            ),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: settings.algorithm.buildRatingKey(context, trendDate: widget.changeSince)
          )
      ),
    )];
  }

  int _ratingWindow = 12;
  List<Widget> _buildRatingRows(RatingScaler? scaler) {
    // TODO: turn this into a Provider and a model, since we need it both in the parent and here
    var hiddenShooters = [];
    for(int i = 0; i < widget.hiddenShooters.length; i++) {
      hiddenShooters.add(ShooterDeduplicator.numberProcessor(widget.sport)(widget.hiddenShooters[i]));
    }

    var sortedRatings = uniqueRatings.where((e) => e.length >= widget.minRatings);
    // var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length > widget.minRatings).sorted((a, b) {
    //   var bRating = b.averageRating(window: _ratingWindow);
    //   var aRating = a.averageRating(window: _ratingWindow);
    //
    //   return bRating.averageOfIntermediates.compareTo(aRating.averageOfIntermediates);
    // });

    if(widget.maxAge != null) {
      var cutoff = widget.currentMatch.date ?? DateTime.now();
      cutoff = cutoff.subtract(widget.maxAge!);
      sortedRatings = sortedRatings.where((r) => r.lastSeen.isAfter(cutoff));
    }

    if(widget.filters.ladyOnly) {
      sortedRatings = sortedRatings.where((r) => r.female);
    }

    if(widget.filters.activeCategories.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) =>
          r.ageCategory != null && widget.filters.activeCategories.contains(r.ageCategory));
    }

    if(widget.search != null && widget.search!.isNotEmpty) {
      if(widget.search!.startsWith('?')) {
        var queryElements = parseQuery(widget.search!.toLowerCase());

        if(queryElements != null) {
          sortedRatings = sortedRatings.where((r) =>
            queryElements.map((q) => q.matchesShooterRating(r)).reduce((a, b) => a || b)
          ).toList();
        }
      }
      else {
        sortedRatings = sortedRatings.where((r) =>
        r.getName(suffixes: false).toLowerCase().contains(widget.search!.toLowerCase())
            || r.memberNumber.toLowerCase().endsWith(widget.search!.toLowerCase())
            || r.originalMemberNumber.toLowerCase().endsWith(widget.search!.toLowerCase())
            || r.knownMemberNumbers.any((n) => n.toLowerCase().endsWith(widget.search!.toLowerCase()))
        ).toList();
      }
    }

    if(widget.hiddenShooters.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) => !hiddenShooters.contains(r.memberNumber));
    }

    var comparator = settings.algorithm.comparatorFor(widget.sortMode, changeSince: widget.changeSince)
        ?? widget.sortMode.comparator(changeSince: widget.changeSince);
    var asList = sortedRatings.sorted(comparator);

    widget.onRatingsFiltered?.call(asList);

    RatingScalerInfo? info;
    if(scaler != null) {
      info = RatingScalerInfo(
        minRating: minRating!.rating,
        maxRating: maxRating!.rating,
        top2PercentAverage: top2PercentAverage!,
        ratingDistribution: ratingDistribution!,
        ratingMean: ratingMean!,
        ratingStdDev: ratingStdDev!,
      );
      scaler.info = info;
    }

    return [
      Expanded(
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            itemBuilder: (context, i) {
              var rating = asList[i];
              return GestureDetector(
                key: Key(rating.memberNumber),
                onTap: () {
                  showDialog(context: context, builder: (context) {
                    return ShooterStatsDialog(rating: rating, match: widget.currentMatch, ratings: widget.dataSource, showDivisions: widget.group.divisions.length > 1);
                  });
                },
                child: settings.algorithm.buildRatingRow(
                  context: context,
                  place: i + 1,
                  rating: rating,
                  trendDate: widget.changeSince,
                  scaler: scaler,
                )
              );
            },
            itemCount: sortedRatings.length,
            controller: _scrollController,
          ),
        ),
      )
    ];
  }
}

enum RatingSortMode {
  rating,
  classification,
  firstName,
  lastName,
  error,
  lastChange,
  trend,
  direction,
  stages,
  pointsPerMatch,
}

extension RatingSortModeNames on RatingSortMode {
  String get uiLabel {
    switch(this) {
      case RatingSortMode.rating:
        return "Rating";
      case RatingSortMode.classification:
        return "Class";
      case RatingSortMode.error:
        return "Error";
      case RatingSortMode.lastChange:
        return "Last ±";
      case RatingSortMode.trend:
        return "Trend";
      case RatingSortMode.stages:
        return "History";
      case RatingSortMode.firstName:
        return "First Name";
      case RatingSortMode.lastName:
        return "Last Name";
      case RatingSortMode.pointsPerMatch:
        return "Points/Match";
      case RatingSortMode.direction:
        return "Direction";
    }
  }
}

extension SortFunctions on RatingSortMode {
  Comparator<ShooterRating> comparator({DateTime? changeSince}) {
    switch(this) {
      case RatingSortMode.rating:
        return (a, b) => b.rating.compareTo(a.rating);
      case RatingSortMode.classification:
        return (a, b) {
          if(a.lastClassification != null && b.lastClassification != null && a.lastClassification != b.lastClassification) {
            return a.lastClassification!.index.compareTo(b.lastClassification!.index);
          }
          else {
            return b.rating.compareTo(a.rating);
          }
        };
      case RatingSortMode.error:
          return (a, b) {
            if(a is EloShooterRating && b is EloShooterRating) {
              double aError;
              double bError;

              if(MultiplayerPercentEloRater.doBackRating) {
                aError = a.backRatingError;
                bError = b.backRatingError;
              }
              else {
                aError = a.standardError;
                bError = b.standardError;
              }
              return aError.compareTo(bError);
            }
            else throw ArgumentError();
          };
      case RatingSortMode.lastChange:
        return (a, b) {
          if(a is EloShooterRating && b is EloShooterRating) {
            double aLastMatchChange = a.lastMatchChange;
            double bLastMatchChange = b.lastMatchChange;
            return bLastMatchChange.compareTo(aLastMatchChange);
          }
          throw ArgumentError();
        };
      case RatingSortMode.direction:
        return (a, b) {
          if(a is EloShooterRating && b is EloShooterRating) {
            double aLastMatchChange = a.direction;
            double bLastMatchChange = b.direction;

            return bLastMatchChange.compareTo(aLastMatchChange);
          }
          throw ArgumentError();
        };
      case RatingSortMode.trend:
        if(changeSince != null) {
          return (a, b) {
            double aChange = a.rating - a.ratingForDate(changeSince);
            double bChange = b.rating - b.ratingForDate(changeSince);
            return bChange.compareTo(aChange);
          };
        }
        else {
          return (a, b) {
            var aTrend = a.trend;
            var bTrend = b.trend;
            return bTrend.compareTo(aTrend);
          };
        }
      case RatingSortMode.stages:
        return (a, b) => b.length.compareTo(a.length);
      case RatingSortMode.firstName:
        return (a, b) => a.firstName.compareTo(b.firstName);
      case RatingSortMode.lastName:
        return (a, b) => a.lastName.compareTo(b.lastName);
      case RatingSortMode.pointsPerMatch:
        return (a, b) {
          if(a is PointsRating && b is PointsRating) {
            var aPpm = a.rating / a.usedEvents().length;
            var bPpm = b.rating / b.usedEvents().length;
            return bPpm.compareTo(aPpm);
          }
          else {
            return b.rating.compareTo(a.rating);
          }
        };
    }
  }
}
