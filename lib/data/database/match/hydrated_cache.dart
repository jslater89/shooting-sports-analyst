/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/cache/match/match_cache.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/util.dart";

class HydratedMatchCache implements MatchCache {
  static final HydratedMatchCache _instance = HydratedMatchCache._internal();
  factory HydratedMatchCache() => _instance;
  HydratedMatchCache._internal();

  final Map<int, ShootingMatch> _cache = {};
  final Map<int, DateTime?> _matchUpdatedAt = {};
  final Map<String, ShootingMatch> _sourceIdCache = {};

  @override
  bool ready() => true;

  @override
  void cache(ShootingMatch match) {
    if(match.databaseId != null) {
      _cache[match.databaseId!] = match;
      _matchUpdatedAt[match.databaseId!] = match.sourceLastUpdated;
    }
    for(var id in match.sourceIds) {
      _sourceIdCache[id] = match;
    }
  }

  bool contains(int id) => _cache.containsKey(id);

  @override
  void remove(int id) {
    _cache.remove(id);
  }

  @override
  void clear() {
    _cache.clear();
  }

  @override
  Result<ShootingMatch, ResultErr> get(DbShootingMatch match) {
    if (_cache.containsKey(match.id)) {
      // If the match in the cache is up to date, return it. If it's not, skip
      // returning and rehydrate/update the cache.
      //
      // Null doesn't get any special treatment; old null and new null returns
      // the cached value, while old non-null and new null or old null and new non-null
      // will rehydrate/update the cache.
      if(_cache[match.id]!.sourceLastUpdated == match.sourceLastUpdated) {
        return Result.ok(_cache[match.id]!);
      }
    }

    var result = match.hydrateSync();
    if (result.isOk()) {
      cache(result.unwrap());
    }
    return result;
  }

  Result<ShootingMatch, ResultErr> getById(int id, {DateTime? sourceLastUpdated}) {
    if(_cache.containsKey(id)) {
      var match = _cache[id]!;
      if(sourceLastUpdated != null && match.sourceLastUpdated != sourceLastUpdated) {
        return Result.err(StringError("cached match outdated"));
      }
      return Result.ok(match);
    }
    return Result.err(StringError("id not found in cache"));
  }

  @override
  Result<ShootingMatch, ResultErr> getBySourceId(String sourceId, {DateTime? sourceLastUpdated}) {
    if(_sourceIdCache.containsKey(sourceId)) {
      var match = _sourceIdCache[sourceId]!;
      if(sourceLastUpdated != null && match.sourceLastUpdated != sourceLastUpdated) {
        return Result.err(StringError("cached match outdated"));
      }
      return Result.ok(match);
    }
    return Result.err(StringError("sourceId not found in cache"));
  }
}