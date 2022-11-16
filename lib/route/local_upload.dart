import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/parser/hitfactor/results_file_parser.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

class UploadedResultPage extends StatefulWidget {
  const UploadedResultPage({Key? key}) : super(key: key);

  @override
  _UploadedResultPageState createState() => _UploadedResultPageState();
}

class _UploadedResultPageState extends State<UploadedResultPage> {
  HitFactorMatch? _match;
  String? _resultString;
  bool _operationInProgress = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _getMatch() async {
    try {
      _resultString = ModalRoute
          .of(context)!
          .settings
          .arguments as String?;

      if (_resultString == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No file given. Go back and try again.")));
        setState(() {
          _operationInProgress = false;
        });

      }

      HitFactorMatch m = await processHitFactorScoreFile(_resultString!);
      setState(() {
        _match = m;
      });
    }
    catch(err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No file given. Go back and try again.")));
      setState(() {
        _operationInProgress = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if(_resultString == null) {
      _getMatch();
    }

    if(_match == null) {
      return EmptyScaffold(
        title: "Match Result Viewer",
        operationInProgress: _operationInProgress,
        child: Center(
          child: Text("Processing..."),
        ),
      );
    }

    return ResultPage(
      canonicalMatch: _match,
    );
  }
}
