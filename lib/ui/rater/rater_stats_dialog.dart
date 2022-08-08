import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';

class RaterStatsDialog extends StatelessWidget {
  const RaterStatsDialog(this.statistics, {Key? key}) : super(key: key);

  final RaterStatistics statistics;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Statistics"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildStatsRows(context),
      ),
    );
  }

  List<Widget> _buildStatsRows(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(flex: 4, child: Text("Total shooters", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${statistics.shooters}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Average rating", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${statistics.averageRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Row(
        children: [
          Expanded(flex: 4, child: Text("Min-max ratings", style: Theme.of(context).textTheme.bodyText2)),
          Expanded(flex: 2, child: Text("${statistics.minRating.round()}-${statistics.maxRating.round()}", style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
        ],
      ),
      Divider(height: 2, thickness: 1),
      Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8),
        child: Text("Class statistics", style: Theme.of(context).textTheme.bodyText1),
      ),
      rowForClass(context, Classification.GM),
      rowForClass(context, Classification.M),
      rowForClass(context, Classification.A),
      rowForClass(context, Classification.B),
      rowForClass(context, Classification.C),
      rowForClass(context, Classification.D),
    ];
  }

  Widget rowForClass(BuildContext context, Classification clas) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(clas.name, style: Theme.of(context).textTheme.bodyText2)),
        Expanded(flex: 4, child: Text("${statistics.countByClass[clas]} shooters, min-max (avg): "
            "${statistics.minByClass[clas]!.round()}-${statistics.maxByClass[clas]!.round()} "
            "(${statistics.averageByClass[clas]!.round()})",
            style: Theme.of(context).textTheme.bodyText2, textAlign: TextAlign.right)),
      ],
    );
  }
}
