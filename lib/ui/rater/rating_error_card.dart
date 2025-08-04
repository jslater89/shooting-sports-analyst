import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

class RatingErrorCard extends StatelessWidget {
  const RatingErrorCard(this.rating, {Key? key, this.titlePrefix = ""}) : super(key: key);

  final ShooterRating rating;
  final String titlePrefix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text("$titlePrefix${rating.getName(suffixes: false)} ${rating.originalMemberNumber}"),
          ],
        ),
      ),
    );
  }
}
