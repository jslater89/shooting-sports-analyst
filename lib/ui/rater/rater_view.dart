/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart' hide IterableNumberExtension;
import 'package:data/data.dart' show IterableNumExtension, ContinuousDistribution;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/data/old_search_query_parser.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/display_settings.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_filter_dialog.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_system_ui.dart';
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

  /// All numerical rating values.
  List<double> allRatings = [];

  ContinuousDistribution? ratingDistribution;
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
    var estimator = Provider.of<RaterViewDisplayModel>(context).estimator;
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
          uniqueRatings = ratings.map((e) => settings.algorithm.wrapDbRating(e)).sorted((a, b) => b.rating.compareTo(a.rating));
        }
        else {
          uniqueRatings = ratings.map((e) => settings.algorithm.wrapDbRating(e)).toList();
        }
        initialized = true;
      }

      if(scaleRatings && minRating == null) {
        allRatings = uniqueRatings.map((e) => e.rating).sorted((a, b) => a.compareTo(b));
        ratingDistribution = estimator.estimate(allRatings);
        _log.i("Generating scaled rating data");
        minRating = uniqueRatings.last;
        maxRating = uniqueRatings.first;
        var top2PercentRatings = allRatings.reversed.take(min(allRatings.length, max(5, (allRatings.length * 0.02).round()))).toList();
        top2PercentAverage = top2PercentRatings.average();
        ratingMean = allRatings.average();
        ratingStdDev = allRatings.standardDeviation();

        _log.v("$ratingDistribution");
        _log.v("Min rating: ${minRating!.rating}, max rating: ${maxRating!.rating}, top 2% average: $top2PercentAverage");
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
                bottom: BorderSide(color: ThemeColors.onBackgroundColor(context))
            ),
            color: ThemeColors.backgroundColor(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: RatingSystemUiBuilder.buildRatingKey(settings.algorithm, context, trendDate: widget.changeSince)
          )
      ),
    )];
  }

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
      var cutoff = widget.currentMatch.date;
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
    if(initialized && scaler != null) {
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
                  if(rating.length == 0) return;

                  showDialog(context: context, builder: (context) {
                    return ShooterStatsDialog(rating: rating, match: widget.currentMatch, ratings: widget.dataSource, showDivisions: widget.group.divisions.length > 1);
                  });
                },
                child: RatingSystemUiBuilder.buildRatingRow(
                  settings.algorithm,
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
