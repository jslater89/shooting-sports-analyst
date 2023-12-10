import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uspsa_result_viewer/data/database/match_database.dart';
import 'package:uspsa_result_viewer/data/database/schema/match.dart';

class MatchDatabaseListView extends StatefulWidget {
  const MatchDatabaseListView({super.key});

  @override
  State<MatchDatabaseListView> createState() => _MatchDatabaseListViewState();
}

class _MatchDatabaseListViewState extends State<MatchDatabaseListView> {
  var listModel = MatchDatabaseListModel();
  var searchModel = MatchDatabaseSearchModel();
  @override
  void initState() {
    super.initState();

    searchModel.addListener(() {
        listModel.search(searchModel);
    });
    listModel.search(null);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: searchModel),
        ChangeNotifierProvider.value(value: listModel),
      ],
      builder: (context, child) {
        var listModel = Provider.of<MatchDatabaseListModel>(context);

        if(listModel.loading) {
          return Center(child: Text("Loading..."));
        }
        return ListView.builder(
          itemBuilder: (context, i) => Text("${listModel.searchedMatches[i].eventName}"),
          itemCount: listModel.searchedMatches.length,
        );
      },
    );
  }
}

class MatchDatabaseSearchModel extends ChangeNotifier {
  MatchDatabaseSearchModel();

  String? name;
  DateTime? before;
  DateTime? after;
}

class MatchDatabaseListModel extends ChangeNotifier {
  MatchDatabaseListModel() : matchDb = MatchDatabase();

  List<DbShootingMatch> searchedMatches = [];
  bool loading = false;

  MatchDatabase matchDb;

  Future<void> search(MatchDatabaseSearchModel? search) async {
    loading = true;
    notifyListeners();

    var newMatches = await matchDb.query(
      name: search?.name,
      before: search?.before,
      after: search?.after,
    );

    loading = false;
    searchedMatches = newMatches;
    notifyListeners();
  }

}