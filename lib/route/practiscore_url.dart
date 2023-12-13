/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// ignore: avoid_web_libraries_in_flutter
//import 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/data/source/practiscore_report.dart';
import 'package:uspsa_result_viewer/data/source/registered_sources.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/ipsc.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:http/http.dart' as http;

class PractiscoreResultPage extends StatefulWidget {
  final String? matchId;
  final String? resultUrl;
  final String sourceId;

  const PractiscoreResultPage({Key? key, this.matchId, this.resultUrl, required this.sourceId}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PractiscoreResultPageState();
  }
}

class _PractiscoreResultPageState extends State<PractiscoreResultPage> {
  ShootingMatch? _match;
  bool _operationInProgress = false;

  @override
  void initState() {
    super.initState();

    if(widget.matchId != null)        _getPractiscoreMatch();
    else if(widget.resultUrl != null) _getResultFileMatch();
    else throw StateError("missing match ID or result URL");
  }

  Future<void> _getResultFileMatch() async {
    var matchSource = MatchSourceRegistry().getByCode(widget.sourceId, PractiscoreHitFactorReportParser(uspsaSport));

    try {
      var response = await http.get(Uri.parse(widget.resultUrl!));
      if(response.statusCode < 400) {
        var responseString = response.body;
        if (responseString.startsWith("\$")) {
          // TODO: this is broken
          var result = await matchSource.getHitFactorMatch(responseString);
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
        else {
          debugPrint("Bad file contents");
        }
      }

      debugPrint("response: $response");
    }
    catch(err) {

    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to download result file from ${widget.resultUrl}.")));
  }

  Future<void> _getPractiscoreMatch() async {
    var proxyUrl = getProxyUrl();
    var reportUrl = "${proxyUrl}https://practiscore.com/reports/web/${widget.matchId}";
    debugPrint("Report download URL: $reportUrl");

    var matchSource = MatchSourceRegistry().getByCode(widget.sourceId, PractiscoreHitFactorReportParser(uspsaSport));

    var result = await matchSource.getHitFactorMatch(widget.matchId!);
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

  @override
  Widget build(BuildContext context) {
    if(_match == null) {
      return EmptyScaffold(
        title: "Match Result Viewer",
        operationInProgress: _operationInProgress,
        child: Center(
          child: Text("Downloading..."),
        ),
      );
    }

    return ResultPage(
      canonicalMatch: _match!,
    );
  }
}

String getProxyUrl() {
  if(HtmlOr.needsProxy) {
    if (kDebugMode) {
      return "https://parabellum.stagerepo.com:10541/";
    }
    else {
      return "https://parabellum.stagerepo.com:10541/";
    }
  }
  return "";
}