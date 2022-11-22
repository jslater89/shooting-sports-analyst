import 'dart:math';

import 'package:uspsa_result_viewer/data/match/timeplus/timeplus_match.dart';
import 'package:uspsa_result_viewer/data/parser/timeplus/icore_parser.dart';
import 'package:uspsa_result_viewer/data/parser/timeplus/idpa_parser.dart';
import 'package:uspsa_result_viewer/route/practiscore_url.dart';
import 'package:http/http.dart' as http;

Future<TimePlusMatch?> processTimePlusHtml(String matchId, String indexHtml) async {
  var proxyUrl = getProxyUrl();

  // Extract all per-stage combined result links from the index page and download them
  var pattern = RegExp(r'(stage[0-9]+-combined)"');
  var matches = pattern.allMatches(indexHtml).toList();

  List<String> stageHtml = [];

  while(matches.isNotEmpty) {
    List<Future<http.Response>> responseFutures = [];
    for(int i = 0; i < min(10, matches.length); i++) {

      if(matches.isEmpty) {
        print("Logic error, dummy");
        break;
      }

      var urlTerminator = matches.removeAt(0);
      var stageUrl = "${proxyUrl}https://s3.amazonaws.com/ps-scores/production/$matchId/html/$urlTerminator";
      responseFutures.add(http.get(Uri.parse(stageUrl)));
    }

    var responses = await Future.wait(responseFutures);
    for(var r in responses) {
      if(r.statusCode < 300) {
        stageHtml.add(r.body.replaceAll("</title>","</title>\n").replaceAll("</div>","</div>\n").replaceAll("</tr>","</tr>\n"));
      }
      else {
        print("Response error: ${r.statusCode} ${r.body}");
      }
    }
  }

  if(stageHtml.isNotEmpty) {
    var firstStage = stageHtml[0];
    if(firstStage.contains("<th>X</th>")) {
      return parseIcoreMatch(matchId, indexHtml, stageHtml);
    }
    else {
      return parseIdpaMatch(matchId, indexHtml, stageHtml);
    }
  }

  return null;
}