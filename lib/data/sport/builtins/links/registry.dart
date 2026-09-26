/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/builtins/links/ipsc_to_uspsa_link.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/sport/sport_link.dart';

class SportLinkRegistry {
  static final SportLinkRegistry _instance = SportLinkRegistry._internal();
  factory SportLinkRegistry() => _instance;

  SportLinkRegistry._internal() {
    registerLink(ipscToUspsaLink);
  }

  final Map<(String, String), SportLink> _linksByPair = {};
  final Map<String, List<SportLink>> _linksBySourceName = {};
  final Map<String, List<SportLink>> _linksByTargetName = {};

  void registerLink(SportLink link) {
    final key = (link.sourceSportName, link.targetSportName);
    if(_linksByPair.containsKey(key)) {
      throw ArgumentError("A link already exists from ${link.sourceSportName} to ${link.targetSportName}");
    }
    _linksByPair[key] = link;
    _linksBySourceName.putIfAbsent(link.sourceSportName, () => []).add(link);
    _linksByTargetName.putIfAbsent(link.targetSportName, () => []).add(link);
  }

  SportLink? linkFor({required Sport source, required Sport target}) {
    return _linksByPair[(source.name, target.name)];
  }

  List<SportLink> linksFromSource(Sport source) => _linksBySourceName[source.name] ?? [];

  List<SportLink> linksToTarget(Sport target, {bool? canIngest, bool? canPredict}) {
    return (_linksByTargetName[target.name] ?? []).where((link) =>
      (canIngest == null || link.canIngest == canIngest)
      && (canPredict == null || link.canPredict == canPredict)
    ).toList();
  }
}