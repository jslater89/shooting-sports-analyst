/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/util.dart";

class HydratedMatchCache {
  static final HydratedMatchCache _instance = HydratedMatchCache._internal();
  factory HydratedMatchCache() => _instance;
  HydratedMatchCache._internal();

  final Map<int, ShootingMatch> _cache = {};
  final Map<String, ShootingMatch> _sourceIdCache = {};

  void cache(ShootingMatch match) {
    if(match.databaseId != null) {
      _cache[match.databaseId!] = match;
    }
    for(var id in match.sourceIds) {
      _sourceIdCache[id] = match;
    }
  }

  void remove(int id) {
    _cache.remove(id);
  }

  void clear() {
    _cache.clear();
  }

  Result<ShootingMatch, ResultErr> get(DbShootingMatch match) {
    if (_cache.containsKey(match.id)) {
      return Result.ok(_cache[match.id]!);
    }

    var result = match.hydrate();
    if (result.isOk()) {
      cache(result.unwrap());
    }
    return result;
  }

  Result<ShootingMatch, ResultErr> getBySourceId(String sourceId) {
    if(_sourceIdCache.containsKey(sourceId)) {
      return Result.ok(_sourceIdCache[sourceId]!);
    }
    return Result.err(StringError("sourceId not found in cache"));
  }
}