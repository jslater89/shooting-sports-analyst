/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/add_comparison_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/shooter_comparison_card.dart';

class CompareShooterResultsPage extends StatefulWidget {
  CompareShooterResultsPage({Key? key, required this.scores, this.initialShooters = const []}) : super(key: key);

  final List<RelativeMatchScore> scores;
  final List<MatchEntry> initialShooters;

  @override
  State<CompareShooterResultsPage> createState() => _CompareShooterResultsPageState();
}

class _CompareShooterResultsPageState extends State<CompareShooterResultsPage> {
  Map<Shooter, RelativeMatchScore> ofInterest = {};

  @override
  void initState() {
    super.initState();
    for(var s in widget.initialShooters) {
      ofInterest[s] = widget.scores.firstWhere((element) => element.shooter == s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Shooter Comparison"),
        centerTitle: true,
      ),
      body: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: _shooterCards(),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () async {
          var score = await showDialog<RelativeMatchScore>(context: context, builder: (context) =>
              AddComparisonDialog(widget.scores)
          );
          if(score != null) {
            setState(() {
              ofInterest[score.shooter] = score;
            });
          }
        },
      ),
    );
  }

  List<Widget> _shooterCards() {
    return ofInterest.keys.map((s) => SizedBox(
      width: 350,
      child: ShooterComparisonCard(
        shooter: s,
        matchScore: ofInterest[s]!,
        onShooterRemoved: removeShooter
      ),
    )).toList();
  }

  void removeShooter(Shooter s) {
    setState(() {
      ofInterest.remove(s);
    });
  }
}
