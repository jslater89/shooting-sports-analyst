// ignore: avoid_web_libraries_in_flutter
//import 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/parser/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/parser/hitfactor/results_file_parser.dart';
import 'package:uspsa_result_viewer/data/parser/timeplus/timeplus_html_parser.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:http/http.dart' as http;

class PractiscoreResultPage extends StatefulWidget {
  final String? hitFactorMatchId;
  final String? timePlusMatchId;
  final String? resultUrl;

  const PractiscoreResultPage({Key? key, this.hitFactorMatchId, this.resultUrl, this.timePlusMatchId}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PractiscoreResultPageState();
  }
}

class _PractiscoreResultPageState extends State<PractiscoreResultPage> {
  HitFactorMatch? _match;
  bool _operationInProgress = false;

  @override
  void initState() {
    super.initState();

    if(widget.hitFactorMatchId != null)       _getMatch();
    else if(widget.timePlusMatchId != null)   _getTimePlusMatch();
    else if(widget.resultUrl != null)         _getResultFileMatch();
    else throw StateError("missing match ID or result URL");
  }

  Future<void> _getResultFileMatch() async {
    try {
      var response = await http.get(Uri.parse(widget.resultUrl!));
      if(response.statusCode < 400) {
        var responseString = response.body;
        if (responseString.startsWith("\$")) {
          var match = await processHitFactorScoreFile(responseString);
          setState(() {
            _match = match;
          });
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

  Future<void> _getMatch() async {
    var proxyUrl = getProxyUrl();
    String reportUrl;
    if(widget.hitFactorMatchId != null) {
      reportUrl = "${proxyUrl}https://practiscore.com/reports/web/${widget.hitFactorMatchId}";
    }
    else if(widget.timePlusMatchId != null) {
      reportUrl = "${proxyUrl}https://practiscore.com/results/html/${widget.timePlusMatchId}";
    }
    else {
      throw StateError("No URL for getMatch()");
    }

    debugPrint("Report download URL: $reportUrl");

    var responseString = "";
    try {
      var response = await http.get(Uri.parse(reportUrl));
      if(response.statusCode < 400) {
        responseString = response.body;
        if (responseString.startsWith(r"$")) {
          var match = await processHitFactorScoreFile(responseString);
          setState(() {
            _match = match;
          });
          return;
        }
        else if (responseString.startsWith("<html>")) {
          var match = await processTimePlusHtml(widget.timePlusMatchId!, responseString);
        }
      }
      else if(response.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No match record exists at given URL.")));
        debugPrint("No match record at $reportUrl");
        return;
      }

      debugPrint("response: ${response.body.split("\n").first}");
    }
    catch(err, stackTrace) {
      debugPrint("download error: $err ${err.runtimeType}");
      debugPrint("$stackTrace");
      if (err is http.ClientException) {
        http.ClientException ce = err;
        debugPrint("${ce.uri} ${ce.message}");
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to download match report.")));
      return;
    }

    try {
      var token = getClubNameToken(responseString);
      debugPrint("Token: $token");
      var body = {
        '_token': token,
        'ClubName': 'None',
        'ClubCode': 'None',
        'matchId': widget.hitFactorMatchId,
      };
      var response = await http.post(Uri.parse(reportUrl), body: body);
      if(response.statusCode < 400) {
        var responseString = response.body;
        if (responseString.startsWith(r"$")) {
          var match = await processHitFactorScoreFile(responseString);
          setState(() {
            _match = match;
          });
          return;
        }
      }

      debugPrint("Didn't work: ${response.statusCode} ${response.body}");
    }
    catch(err) {
      debugPrint("download error pt. 2: $err ${err.runtimeType}");
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to download match report.")));
  }
  
  Future<void> _getTimePlusMatch() async {
    
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
      canonicalMatch: _match,
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