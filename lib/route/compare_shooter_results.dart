import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/add_comparison_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/shooter_comparison_card.dart';

class CompareShooterResultsPage extends StatefulWidget {
  CompareShooterResultsPage({Key? key, required this.scores, this.initialShooters = const []}) : super(key: key);

  final List<RelativeMatchScore> scores;
  final List<Shooter> initialShooters;

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
