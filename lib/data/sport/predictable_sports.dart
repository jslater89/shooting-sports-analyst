/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/builtins/links/registry.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// Sports whose matches can be predicted from a project in [projectSport].
///
/// Includes the project sport and every source sport with a prediction link
/// into it. IPSC matches are predictable from a USPSA project, for example.
List<Sport> predictableSportsFor(Sport projectSport) {
  final sports = <Sport>[projectSport];
  for(final link in SportLinkRegistry().linksToTarget(projectSport, canPredict: true)) {
    if(sports.any((sport) => sport.name == link.sourceSport.name)) continue;
    sports.add(link.sourceSport);
  }
  return sports;
}

/// Sports that may be linked as the result of a match prep.
///
/// Starts from [predictableSportsFor] and also keeps the future match's own
/// sport, so an existing prep can still be linked to its result.
List<Sport> sportsForMatchPrepLink({
  required Sport projectSport,
  String? futureMatchSportName,
}) {
  final sports = predictableSportsFor(projectSport);
  if(futureMatchSportName == null) return sports;

  final futureSport = SportRegistry().lookup(futureMatchSportName, caseSensitive: false);
  if(futureSport == null) return sports;
  if(sports.any((sport) => sport.name == futureSport.name)) return sports;
  return [...sports, futureSport];
}

bool sportNameIn(String sportName, List<Sport> sports) {
  if(sports.any((sport) => sport.name == sportName)) return true;
  final lookedUp = SportRegistry().lookup(sportName, caseSensitive: false);
  if(lookedUp == null) return false;
  return sports.any((sport) => sport.name == lookedUp.name);
}
