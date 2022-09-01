// ignore: avoid_web_libraries_in_flutter
//import 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:http/http.dart' as http;

class PractiscoreResultPage extends StatefulWidget {
  final String? matchId;
  final String? resultUrl;

  const PractiscoreResultPage({Key? key, this.matchId, this.resultUrl}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PractiscoreResultPageState();
  }
}

class _PractiscoreResultPageState extends State<PractiscoreResultPage> {
  PracticalMatch? _match;
  late BuildContext _innerContext;
  bool _operationInProgress = false;

  @override
  void initState() {
    super.initState();

    if(widget.matchId != null)        _getPractiscoreMatch();
    else if(widget.resultUrl != null) _getResultFileMatch();
    else throw StateError("missing match ID or result URL");
  }

  Future<void> _getResultFileMatch() async {
    try {
      var response = await http.get(Uri.parse(widget.resultUrl!));
      if(response.statusCode < 400) {
        var responseString = response.body;
        if (responseString.startsWith("\$")) {
          var match = await processScoreFile(responseString);
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
    ScaffoldMessenger.of(_innerContext).showSnackBar(SnackBar(content: Text("Failed to download result file from ${widget.resultUrl}.")));
  }

  Future<void> _getPractiscoreMatch() async {
    var proxyUrl = getProxyUrl();
    var reportUrl = "${proxyUrl}https://practiscore.com/reports/web/${widget.matchId}";
    debugPrint("Report download URL: $reportUrl");

    var responseString = "";
    try {
      var response = await http.get(Uri.parse(reportUrl));
      if(response.statusCode < 400) {
        responseString = response.body;
        if (responseString.startsWith(r"$")) {
          var match = await processScoreFile(responseString);
          setState(() {
            _match = match;
          });
          return;
        }
      }
      else if(response.statusCode == 404) {
        ScaffoldMessenger.of(_innerContext).showSnackBar(SnackBar(content: Text("No match record exists at given URL.")));
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
      ScaffoldMessenger.of(_innerContext).showSnackBar(SnackBar(content: Text("Failed to download match report.")));
      return;
    }

    try {
      var token = getClubNameToken(responseString);
      debugPrint("Token: $token");
      var body = {
        '_token': token,
        'ClubName': 'None',
        'ClubCode': 'None',
        'matchId': widget.matchId,
      };
      var response = await http.post(Uri.parse(reportUrl), body: body);
      if(response.statusCode < 400) {
        var responseString = response.body;
        if (responseString.startsWith(r"$")) {
          var match = await processScoreFile(responseString);
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
    ScaffoldMessenger.of(_innerContext).showSnackBar(SnackBar(content: Text("Failed to download match report.")));
  }

  @override
  Widget build(BuildContext context) {
    if(_match == null) {
      return EmptyScaffold(
        operationInProgress: _operationInProgress,
        onInnerContextAssigned: (context) => _innerContext = context,
        child: Center(
          child: Text("Downloading..."),
        ),
      );
    }

    return ResultPage(
      canonicalMatch: _match,
      onInnerContextAssigned: (context) => _innerContext = context,
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