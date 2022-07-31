import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';

class RaterPage extends StatefulWidget {
  const RaterPage({Key? key}) : super(key: key);

  @override
  State<RaterPage> createState() => _RaterPageState();
}

class _RaterPageState extends State<RaterPage> {
  bool _operationInProgress = false;

  Map<String, PracticalMatch> _matches = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;

    var animation = (_operationInProgress) ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    List<Widget> actions = _generateActions();

    return Scaffold(
      appBar: AppBar(
        title: Text("Shooter Rating Calculator"),
        centerTitle: true,
        actions: actions,
        bottom: _operationInProgress ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
      ),
    );
  }

  List<Widget> _generateActions() {
    return [
      Tooltip(
        message: "Add matches",
        child: IconButton(
          icon: Icon(Icons.add),
          onPressed: () async {
            var newUrls = await showDialog<List<String>>(context: context, builder: (context) {
              return EnterUrlsDialog();
            }) ?? [];

            for(var url in newUrls) {
              if(!_matches.containsKey(url)) {
                _getMatchResultFile(url);
              }
            }
          },
        )
      ),
      Tooltip(
        message: "Edit matches",
        child: IconButton(
          icon: Icon(Icons.list),
          onPressed: () {
            // TODO: show matches dialog
          },
        )
      )
    ];
  }

  Future<bool> _getMatchResultFile(String url) async {
    var id = await processMatchUrl(url);
    if(id != null) {
      var match = await getPractiscoreMatchHeadless(id);
      if(match != null) {
        _matches[url] = match;
        return true;
      }
    }
    return false;
  }
}
