/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/results_file_parser.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/route/practiscore_url.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/url_entry_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';


String getClubNameToken(String source) {
  var tokenLine = source.split("\n").firstWhere((element) => element.startsWith('<meta name="csrf-token"'), orElse: () => "");
  var token = tokenLine.split('"')[3];
  return token;
}

String? getPractiscoreWebReportUrl(String source) {
  var webReportLine = source.split("\n").firstWhereOrNull((element) => element.contains("/reports/web"));
  return webReportLine?.split('"').firstWhereOrNull((element) => element.contains("reports/web"));
}

Future<String?> processMatchUrl(String matchUrl, {BuildContext? context}) async {
  var matchUrlParts = matchUrl.split("/");
  var matchId = matchUrlParts.last;

  // It's probably a short ID—the long IDs are UUID-style, with dashes separating
  // blocks of alphanumeric characters
  if(!matchId.contains(r"-")) {
    try {
      if(verboseParse) debugPrint("Trying to get match from URL: $matchUrl");
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
          debugPrint("Unable to determine web report URL (probably not hit factor)");
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

Future<Result<PracticalMatch, MatchGetError>> getPractiscoreMatchHeadless(String matchId) async {
  var proxyUrl = getProxyUrl();
  var reportUrl = "${proxyUrl}https://practiscore.com/reports/web/$matchId";
  if(verboseParse) debugPrint("Report download URL: $reportUrl");

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
      return Result.err(MatchGetError.noMatch);
    }

    if(verboseParse) debugPrint("response: ${response.body.split("\n").first}");
  }
  catch(err, stackTrace) {
    debugPrint("download error: $err ${err.runtimeType}");
    debugPrint("$stackTrace");

    if (err is http.ClientException) {
      http.ClientException ce = err;
      debugPrint("${ce.uri} ${ce.message}");
    }
    return Result.err(MatchGetError.network);
  }

  try {
    var token = getClubNameToken(responseString);
    if(verboseParse) debugPrint("Token: $token");
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

    if(verboseParse) debugPrint("Didn't work: ${response.statusCode} ${response.body}");
  }
  catch(err) {
    debugPrint("download error pt. 2: $err ${err.runtimeType}");
  }
  return Result.err(MatchGetError.network);
}

Future<String?> getMatchId(BuildContext context, {String? presetUrl}) async {
  var matchUrl = presetUrl ??
      await getMatchUrl(context);

  if (matchUrl == null) {
    return null;
  }

  var matchId = processMatchUrl(matchUrl, context: context);

  return matchId;
}

Future<(MatchSource, String?)?> getMatchIdWithSource(BuildContext context) async {
  (MatchSource, String?)? response;
  response = await getMatchUrlWithSource(context);

  if (response == null || response.$2 == null) {
    return null;
  }

  var (matchSource, matchUrl) = response;

  var matchId = await processMatchUrl(matchUrl!, context: context);

  return (matchSource, matchId);
}

Future<(MatchSource, String?)?> getMatchUrlWithSource(BuildContext context) {
  return showDialog<(MatchSource, String?)>(
      context: context,
      builder: (context) {
        return UrlEntryDialog(
          hintText: "https://practiscore.com/results/new/...",
          title: "Enter PractiScore match URL",
          descriptionText: "Copy the URL to the match's PractiScore results page and paste it in the field below.",
          sources: MatchSourceRegistry().practiscoreUrlSources,
        );
      }
  );
}

Future<String?> getMatchUrl(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return UrlEntryDialog(
        hintText: "https://practiscore.com/results/new/...",
        title: "Enter PractiScore match URL",
        descriptionText: "Copy the URL to the match's PractiScore results page and paste it in the field below.",
      );
    }
  );
}