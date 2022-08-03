import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_change_dialog.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

class RaterView extends StatefulWidget {
  const RaterView({Key? key, required this.rater, required this.currentMatch}) : super(key: key);

  final Rater rater;
  final PracticalMatch currentMatch;

  @override
  State<RaterView> createState() => _RaterViewState();
}

class _RaterViewState extends State<RaterView> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          ..._buildRatingKey(),
          ..._buildRatingRows(),
        ]
      ),
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
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(flex: 3, child: Text("")),
                Expanded(flex: 2, child: Text("Member #")),
                Expanded(flex: 3, child: Text("Name")),
                Expanded(flex: 1, child: Text("Rating")),
                Expanded(flex: 1, child: Text("Variance")),
                Expanded(flex: 1, child: Text("Trend")),
                Expanded(flex: 1, child: Text("Stages")),
                Expanded(flex: 3, child: Text("")),
              ],
            ),
          )
      ),
    )];
  }

  List<Widget> _buildRatingRows() {
    var sortedRatings = widget.rater.knownShooters.values.sorted((a, b) => b.rating.compareTo(a.rating));

    List<Widget> widgets = [];
    for(int i = 0; i < sortedRatings.length; i++) {
      widgets.add(GestureDetector(
        onTap: () {
          showDialog(context: context, builder: (context) {
            return ShooterRatingChangeDialog(rating: sortedRatings[i], match: widget.currentMatch);
          });
        },
        child: ScoreRow(
          color: i % 2 == 1 ? Colors.grey[200] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text("")),
                Expanded(flex: 2, child: Text(Rater.processMemberNumber(sortedRatings[i].shooter.memberNumber))),
                Expanded(flex: 3, child: Text(sortedRatings[i].shooter.getName(suffixes: false))),
                Expanded(flex: 1, child: Text("${sortedRatings[i].rating.round()}")),
                Expanded(flex: 1, child: Text("${sortedRatings[i].variance.toStringAsFixed(2)}")),
                Expanded(flex: 1, child: Text("${sortedRatings[i].trend.toStringAsFixed(2)}")),
                Expanded(flex: 1, child: Text("${sortedRatings[i].ratingEvents.length}")),
                Expanded(flex: 3, child: Text("")),
              ],
            )
          ),
        ),
      ));
    }
    return widgets;
  }
}
