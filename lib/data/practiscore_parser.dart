import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/route/practiscore_url.dart';


String getClubNameToken(String source) {
  var tokenLine = source.split("\n").firstWhere((element) => element.startsWith('<meta name="csrf-token"'), orElse: () => "");
  var token = tokenLine.split('"')[3];
  return token;
}

String? getPractiscoreWebReportUrl(String source) {
  var webReportLine = source.split("\n").firstWhere((element) => element.contains("/reports/web"));
  return webReportLine.split('"').firstWhereOrNull((element) => element.contains("reports/web"));
}

Future<String?> processMatchUrl(String matchUrl, {BuildContext? context}) async {
  var matchUrlParts = matchUrl.split("/");
  var matchId = matchUrlParts.last;

  // It's probably a short ID—the long IDs are UUID-style, with dashes separating
  // blocks of alphanumeric characters
  if(!matchId.contains(r"-")) {
    try {
      debugPrint("Trying to get match from URL: $matchUrl");
      var response = await http.get(Uri.parse("${getProxyUrl()}$matchUrl"));
      if(response.statusCode == 404) {
        if(context != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Match not found.")));
        debugPrint("404: match not found");
        return null;
      }
      else if(response.statusCode == 200) {
        var foundUrl = getPractiscoreWebReportUrl(response.body);
        if(foundUrl != null) {
          matchId = foundUrl.split("/").last;
        }
        else {
          if(context != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to determine web report URL.")));
          debugPrint("Unable to determine web report URL");
          return null;
        }
      }
      else {
        debugPrint("${response.statusCode} ${response.body}");
        if(context != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to download match file.")));
        return null;
      }
    }
    catch(err) {
      debugPrint("$err");
      if(context != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to download match file.")));
      return null;
    }
  }

  return matchId;
}

Future<PracticalMatch?> getPractiscoreMatchHeadless(String matchId) async {
  var proxyUrl = getProxyUrl();
  var reportUrl = "${proxyUrl}https://practiscore.com/reports/web/$matchId";
  debugPrint("Report download URL: $reportUrl");

  var responseString = "";
  try {
    var response = await http.get(Uri.parse(reportUrl));
    if(response.statusCode < 400) {
      responseString = response.body;
      if (responseString.startsWith(r"$")) {
        var match = await processScoreFile(responseString);
        return match;
      }
    }
    else if(response.statusCode == 404) {
      debugPrint("No match record at $reportUrl");
      return null;
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
    return null;
  }

  try {
    var token = getClubNameToken(responseString);
    debugPrint("Token: $token");
    var body = {
      '_token': token,
      'ClubName': 'None',
      'ClubCode': 'None',
      'matchId': matchId,
    };
    var response = await http.post(Uri.parse(reportUrl), body: body);
    if(response.statusCode < 400) {
      var responseString = response.body;
      if (responseString.startsWith(r"$")) {
        var match = await processScoreFile(responseString);
        return match;
      }
    }

    debugPrint("Didn't work: ${response.statusCode} ${response.body}");
  }
  catch(err) {
    debugPrint("download error pt. 2: $err ${err.runtimeType}");
  }
  return null;
}