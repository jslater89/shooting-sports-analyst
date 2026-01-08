import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/empty_scaffold.dart';

class PredictionGameListPage extends StatefulWidget {
  const PredictionGameListPage({super.key});

  @override
  State<PredictionGameListPage> createState() => _PredictionGameListPageState();
}

class _PredictionGameListPageState extends State<PredictionGameListPage> {
  @override
  Widget build(BuildContext context) {
    return EmptyScaffold(
      title: "Prediction Games",
      child: ListView.builder(
        itemBuilder: (context, index) => ListTile(
          title: Text("Prediction Game $index"),
          onTap: () {
            // prediction game management page
          },
        ),
        itemCount: 10,
      ),
    );
  }
}