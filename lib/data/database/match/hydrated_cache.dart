/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/cache/lru_tracker.dart";
import "package:shooting_sports_analyst/data/cache/match/match_cache.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("HydratedMatchCache");

class HydratedMatchCache implements MatchCache {
  static HydratedMatchCache? _instance;

  factory HydratedMatchCache({bool useLru = false, int lruCapacity = 250}) {
    if (_instance == null || (_instance!.lru == null && useLru)) {
      _instance = useLru
          ? HydratedMatchCache._withLru(LruTracker<int>(capacity: lruCapacity))
          : HydratedMatchCache._internal();
    }
    return _instance!;
  }

  HydratedMatchCache._internal() : lru = null;
  HydratedMatchCache._withLru(this.lru);

  final LruTracker<int>? lru;

  final Map<int, ShootingMatch> _cache = {};
  final Map<int, DateTime?> _matchUpdatedAt = {};
  final Map<String, ShootingMatch> _sourceIdCache = {};

  void printStats() {
    _log.i("cache size: ${_cache.length}");
    if(lru != null) {
      _log.i("lru load factor: ${(lru!.length / lru!.capacity).asPercentage(decimals: 1, includePercent: true)}");
      _log.i("lru size: ${lru!.length}");
    }
  }

  @override
  bool ready() => true;

  void _evictId(int id) {
    _cache.remove(id);
    _matchUpdatedAt.remove(id);
    final toRemove = _sourceIdCache.entries
        .where((e) => e.value.databaseId == id)
        .map((e) => e.key)
        .toList();
    for (final key in toRemove) {
      _sourceIdCache.remove(key);
    }
  }

  @override
  void cache(ShootingMatch match) {
    if (match.databaseId != null) {
      if (lru != null) {
        final evicted = lru!.record(match.databaseId!);
        if (evicted != null) {
          _evictId(evicted);
        }
      }
      _cache[match.databaseId!] = match;
      _matchUpdatedAt[match.databaseId!] = match.sourceLastUpdated;
    }
    for (var id in match.sourceIds) {
      _sourceIdCache[id] = match;
    }
  }

  bool contains(int id) => _cache.containsKey(id);

  @override
  void remove(int id) {
    if (lru != null) {
      lru!.remove(id);
    }
    _evictId(id);
  }

  @override
  void clear() {
    if (lru != null) {
      lru!.clear();
    }
    _cache.clear();
    _matchUpdatedAt.clear();
    _sourceIdCache.clear();
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
      if (_cache[match.id]!.sourceLastUpdated == match.sourceLastUpdated) {
        if (lru != null) {
          final evicted = lru!.record(match.id);
          if (evicted != null) {
            _evictId(evicted);
          }
        }
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
    if (_cache.containsKey(id)) {
      var match = _cache[id]!;
      if (sourceLastUpdated != null && match.sourceLastUpdated != sourceLastUpdated) {
        return Result.err(StringError("cached match outdated"));
      }
      if (lru != null) {
        final evicted = lru!.record(id);
        if (evicted != null) {
          _evictId(evicted);
        }
      }
      return Result.ok(match);
    }
    return Result.err(StringError("id not found in cache"));
  }

  @override
  Result<ShootingMatch, ResultErr> getBySourceId(String sourceId, {DateTime? sourceLastUpdated}) {
    if (_sourceIdCache.containsKey(sourceId)) {
      var match = _sourceIdCache[sourceId]!;
      if (sourceLastUpdated != null && match.sourceLastUpdated != sourceLastUpdated) {
        return Result.err(StringError("cached match outdated"));
      }
      if (lru != null && match.databaseId != null) {
        final evicted = lru!.record(match.databaseId!);
        if (evicted != null) {
          _evictId(evicted);
        }
      }
      return Result.ok(match);
    }
    return Result.err(StringError("sourceId not found in cache"));
  }
}