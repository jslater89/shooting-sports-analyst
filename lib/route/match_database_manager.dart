import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/ui/widget/matchdb/match_db_list_view.dart';

class MatchDatabaseManagerPage extends StatefulWidget {
  const MatchDatabaseManagerPage({super.key});

  @override
  State<MatchDatabaseManagerPage> createState() => _MatchDatabaseManagerPageState();
}

class _MatchDatabaseManagerPageState extends State<MatchDatabaseManagerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Match Database"),
        centerTitle: true,
      ),
      body: MatchDatabaseListView(),
    );
  }
}
