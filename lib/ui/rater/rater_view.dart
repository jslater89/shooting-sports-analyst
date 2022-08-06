import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_change_dialog.dart';
import 'package:uspsa_result_viewer/ui/score_row.dart';

class RaterView extends StatefulWidget {
  const RaterView({Key? key, required this.rater, required this.currentMatch, this.search, this.minRatings = 0}) : super(key: key);

  final String? search;
  final int minRatings;
  final Rater rater;
  final PracticalMatch currentMatch;

  @override
  State<RaterView> createState() => _RaterViewState();
}

class _RaterViewState extends State<RaterView> {
  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        child: Column(
          children: [
            ..._buildRatingKey(),
            ..._buildRatingRows(),
          ]
        ),
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
                Expanded(flex: 1, child: Text(widget.rater.byStage ? "Stages" : "Matches")),
                Expanded(flex: 3, child: Text("")),
              ],
            ),
          )
      ),
    )];
  }

  List<Widget> _buildRatingRows() {
    var sortedRatings = widget.rater.uniqueShooters.where((e) => e.ratingEvents.length > widget.minRatings).sorted((a, b) => b.rating.compareTo(a.rating));

    if(widget.search != null && widget.search!.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) => r.shooter.getName(suffixes: false).toLowerCase().contains(widget.search!.toLowerCase())).toList();
    }

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
