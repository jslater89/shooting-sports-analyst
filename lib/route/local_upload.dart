/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/data/source/practiscore_report.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/match/translator.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

class UploadedResultPage extends StatefulWidget {
  const UploadedResultPage({Key? key}) : super(key: key);

  @override
  _UploadedResultPageState createState() => _UploadedResultPageState();
}

class _UploadedResultPageState extends State<UploadedResultPage> {
  ShootingMatch? _match;
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

      var processor = PractiscoreHitFactorReportParser(uspsaSport);
      var result = await processor.parseWebReport(_resultString!);
      if(result.isOk()) {
        var match = result.unwrap();
        setState(() {
          _match = match;
        });
      }
      else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.unwrapErr().message)));
      }
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
      canonicalMatch: _match!,
    );
  }
}
