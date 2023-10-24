/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:convert';

final _profileMatchesRegex = RegExp(r"var matches = (?<matchListJson>\[\{.*\}\])");
final _resultsNewRegex = RegExp(r'\/results\/new\/(?<matchId>[a-zA-Z\-0-9]+)[' + "'" + r'\"]');
final _matchIdRegex = RegExp(r'matchid=[' + "'" + r'\"](?<matchId>[a-zA-Z\-0-9]+)[' + "'" + r'\"]');

List<String> getMatchResultLinksFromHtml(String html) {
  try {
    var profileMatch = _profileMatchesRegex.firstMatch(html);
    if (profileMatch != null) {
      return _parseSelectProfileMatches(profileMatch.namedGroup("matchListJson")!);
    }

    var matchIdMatches = _matchIdRegex.allMatches(html);
    if (matchIdMatches.isNotEmpty) {
      return matchIdMatches.map((m) {
        var matchId = m.namedGroup("matchId")!;
        return "https://practiscore.com/results/new/$matchId";
      }).toList();
    }

    var resultsNewMatches = _resultsNewRegex.allMatches(html);
    if (resultsNewMatches.isNotEmpty) {
      return resultsNewMatches.map((m) {
        var matchId = m.namedGroup("matchId")!;
        return "https://practiscore.com/results/new/$matchId";
      }).toList();
    }
  }
  catch(e) {
    print("Error parsing results HTML: $e");
    return [];
  }

  print("No URLs found");
  return [];
}

// List of:
// {"name":"Castlewood USPSA September 2022 Shoot","date":"2022-09-24","matchId":"ac2589c8-73c1-466e-813a-7c71f7dfb842","shooter_uuid":"mmShooter_4714741","tracked_id":6269448}
List<String> _parseSelectProfileMatches(String matchListJson) {
  try {
    List<String> uris = [];
    List<dynamic> json = jsonDecode(matchListJson);

    for(var matchEntry in json) {
      matchEntry as Map<String, dynamic>;
      var id = (matchEntry["matchId"]) as String?;
      if(id != null) {
        uris.add("https://practiscore.com/results/new/$id");
      }
    }

    return uris;
  }
  catch(e) {
    print("Error parsing JSON: $e");
    return [];
  }
}