import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class ShooterComparisonCard extends StatelessWidget {
  const ShooterComparisonCard({Key? key, required this.shooter, required this.matchScore}) : super(key: key);

  final Shooter shooter;
  final RelativeMatchScore matchScore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(shooter.getName(suffixes: false), style: Theme.of(context).textTheme.headlineSmall)
          ],
        ),
      ),
    );
  }
}
