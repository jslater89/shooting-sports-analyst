import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_stats_dialog.dart';

class RaterView extends StatefulWidget {
  const RaterView({
    Key? key, required this.rater, required this.currentMatch, this.search, this.maxAge, this.minRatings = 0,
    this.sortMode = RatingSortMode.rating,
    this.onRatingsFiltered,
  }) : super(key: key);

  final String? search;
  final Duration? maxAge;
  final int minRatings;
  final Rater rater;
  final PracticalMatch currentMatch;
  final RatingSortMode sortMode;
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
            child: widget.rater.ratingSystem.buildRatingKey(context)
          )
      ),
    )];
  }

  int _ratingWindow = 12;
  List<Widget> _buildRatingRows() {
    var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length >= widget.minRatings);
    // var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length > widget.minRatings).sorted((a, b) {
    //   var bRating = b.averageRating(window: _ratingWindow);
    //   var aRating = a.averageRating(window: _ratingWindow);
    //
    //   return bRating.averageOfIntermediates.compareTo(aRating.averageOfIntermediates);
    // });

    if(widget.search != null && widget.search!.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) => r.getName(suffixes: false).toLowerCase().contains(widget.search!.toLowerCase())).toList();
    }

    if(widget.maxAge != null) {
      var cutoff = widget.currentMatch.date ?? DateTime.now();
      cutoff = cutoff.subtract(widget.maxAge!);
      sortedRatings = sortedRatings.where((r) => r.lastSeen.isAfter(cutoff));
    }

    var comparator = widget.rater.ratingSystem.comparatorFor(widget.sortMode) ?? widget.sortMode.comparator();
    var asList = sortedRatings.sorted(comparator);
    
    widget.onRatingsFiltered?.call(asList);

    return [
      Expanded(
        child: Scrollbar(
          thumbVisibility: true,
          child: ListView.builder(itemBuilder: (context, i) {
            return GestureDetector(
              key: Key(asList[i].memberNumber),
              onTap: () {
                showDialog(context: context, builder: (context) {
                  return ShooterStatsDialog(rating: asList[i], match: widget.currentMatch);
                });
              },
              child: widget.rater.ratingSystem.buildRatingRow(
                context: context,
                place: i + 1,
                rating: asList[i],
              )
            );
          },
          itemCount: sortedRatings.length,
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
  stages,
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
    }
  }
}

extension _SortFunctions on RatingSortMode {
  Comparator<ShooterRating> comparator() {
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
              var aError = a.standardError;
              var bError = b.standardError;
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
      case RatingSortMode.trend:
        return (a, b) {
          var aTrend = a.trend;
          var bTrend = b.trend;
          return bTrend.compareTo(aTrend);
        };
      case RatingSortMode.stages:
        return (a, b) => b.ratingEvents.length.compareTo(a.ratingEvents.length);
      case RatingSortMode.firstName:
        return (a, b) => a.firstName.compareTo(b.firstName);
      case RatingSortMode.lastName:
        return (a, b) => a.lastName.compareTo(b.lastName);
    }
  }
}