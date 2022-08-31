import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_stats_dialog.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

class RaterView extends StatefulWidget {
  const RaterView({Key? key, required this.rater, required this.currentMatch, this.search, this.maxAge, this.minRatings = 0}) : super(key: key);

  final String? search;
  final Duration? maxAge;
  final int minRatings;
  final Rater rater;
  final PracticalMatch currentMatch;

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
    var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length >= widget.minRatings).sorted((a, b) => b.rating.compareTo(a.rating));
    // var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length > widget.minRatings).sorted((a, b) {
    //   var bRating = b.averageRating(window: _ratingWindow);
    //   var aRating = a.averageRating(window: _ratingWindow);
    //
    //   return bRating.averageOfIntermediates.compareTo(aRating.averageOfIntermediates);
    // });

    if(widget.search != null && widget.search!.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) => r.shooter.getName(suffixes: false).toLowerCase().contains(widget.search!.toLowerCase())).toList();
    }

    if(widget.maxAge != null) {
      var cutoff = widget.currentMatch.date ?? DateTime.now();
      cutoff = cutoff.subtract(widget.maxAge!);
      sortedRatings = sortedRatings.where((r) => r.lastSeen.isAfter(cutoff)).toList();
    }

    return [
      Expanded(
        child: Scrollbar(
          thumbVisibility: true,
          child: ListView.builder(itemBuilder: (context, i) {
            return GestureDetector(
              onTap: () {
                showDialog(context: context, builder: (context) {
                  return ShooterStatsDialog(rating: sortedRatings[i], match: widget.currentMatch);
                });
              },
              child: widget.rater.ratingSystem.buildShooterRatingRow(
                context: context,
                place: i + 1,
                rating: sortedRatings[i],
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
