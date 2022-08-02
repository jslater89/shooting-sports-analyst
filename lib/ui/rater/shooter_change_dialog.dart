import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';

/// ShooterRatingChangeDialog displays per-stage changes for a shooter.
class ShooterRatingChangeDialog extends StatelessWidget {
  const ShooterRatingChangeDialog({Key? key, required this.rating, required this.match}) : super(key: key);

  final ShooterRating rating;
  final PracticalMatch match;

  @override
  Widget build(BuildContext context) {
    List<RatingEvent> events = rating.ratingEvents.where((r) => match.stages.contains(r.score.stage)).toList();

    return AlertDialog(
      title: Text("Ratings for ${rating.shooter.getName(suffixes: false)}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: events.map((e) =>
          Text("${e.eventName}: ${e.ratingChange.toStringAsFixed(2)}")
        ).toList(),
      ),
    );
  }
}
