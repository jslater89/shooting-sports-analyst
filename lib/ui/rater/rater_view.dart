/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/old_search_query_parser.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';

class RaterView extends StatefulWidget {
  const RaterView({
    Key? key,
    required this.history,
    required this.rater,
    required this.currentMatch,
    this.search, this.maxAge, this.minRatings = 0,
    this.sortMode = RatingSortMode.rating,
    required this.filters,
    this.onRatingsFiltered,
    this.hiddenShooters = const [],
    this.changeSince,
  }) : super(key: key);

  final String? search;
  final Duration? maxAge;
  final DateTime? changeSince;
  final RatingFilters filters;
  final int minRatings;
  final RatingHistory history;
  final Rater rater;
  final PracticalMatch currentMatch;
  final RatingSortMode sortMode;

  /// A list of shooters to hide from the results. Entries are member numbers.
  final List<String> hiddenShooters;

  final void Function(List<ShooterRating>)? onRatingsFiltered;

  @override
  State<RaterView> createState() => _RaterViewState();
}

class _RaterViewState extends State<RaterView> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ..._buildRatingKey(),
        ..._buildRatingRows(),
      ]
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
            child: widget.rater.ratingSystem.buildRatingKey(context, trendDate: widget.changeSince)
          )
      ),
    )];
  }

  int _ratingWindow = 12;
  List<Widget> _buildRatingRows() {
    // TODO: turn this into a Provider and a model, since we need it both in the parent and here
    var hiddenShooters = [];
    for(int i = 0; i < widget.hiddenShooters.length; i++) {
      hiddenShooters.add(Rater.processMemberNumber(widget.hiddenShooters[i]));
    }

    var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length >= widget.minRatings);
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
          r.categories.any((c) => widget.filters.activeCategories.contains(c)));
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
            || r.alternateMemberNumbers.any((n) => n.toLowerCase().endsWith(widget.search!.toLowerCase()))
        ).toList();
      }
    }

    if(widget.hiddenShooters.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) => !hiddenShooters.contains(r.memberNumber));
    }

    var comparator = widget.rater.ratingSystem.comparatorFor(widget.sortMode, changeSince: widget.changeSince) ?? widget.sortMode.comparator(changeSince: widget.changeSince);
    var asList = sortedRatings.sorted(comparator);
    
    widget.onRatingsFiltered?.call(asList);

    return [
      Expanded(
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            itemBuilder: (context, i) {
              return GestureDetector(
                key: Key(asList[i].memberNumber),
                onTap: () {
                  var ratings = <RaterGroup, Rater>{};
                  for(var group in widget.history.groups) {
                    ratings[group] = widget.history.latestRaterFor(group);
                  }
                  showDialog(context: context, builder: (context) {
                    return ShooterStatsDialog(rating: asList[i], match: widget.currentMatch, ratings: ratings, showDivisions: widget.rater.group.divisions.length > 1);
                  });
                },
                child: widget.rater.ratingSystem.buildRatingRow(
                  context: context,
                  place: i + 1,
                  rating: asList[i],
                  trendDate: widget.changeSince,
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
          if(a.lastClassification != b.lastClassification) {
            return a.lastClassification.index.compareTo(b.lastClassification.index);
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
        return (a, b) => b.ratingEvents.length.compareTo(a.ratingEvents.length);
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