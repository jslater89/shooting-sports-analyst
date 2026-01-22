import 'dart:async';

import 'package:shooting_sports_analyst/data/cache/match/isolate_match_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/util.dart';

/// A cache for matches. Use [MatchCache.instance] to get an instance
/// appropriate for the current mode.
///
/// When [serverMode] is true, the cache will be an isolate-safe cache
/// (using a server isolate to handle singleton storage) [IsolateMatchCacheClient]. When false,
/// it will return a local in-memory cache [HydratedMatchCache].
///
/// In UI code, you can use [MatchCache.inMemoryInstance] to always get a hydrated cache,
/// which is fully synchronous and can be more readily used in UI code. In
/// data-handling code, prefer to use [MatchCache.instance] for isolate safety.
abstract interface class MatchCache {
  FutureOr<bool> ready();
  FutureOr<void> cache(ShootingMatch match);
  FutureOr<void> remove(int id);
  FutureOr<void> clear();
  FutureOr<Result<ShootingMatch, ResultErr>> get(DbShootingMatch match);
  FutureOr<Result<ShootingMatch, ResultErr>> getBySourceId(String sourceId);

  static bool serverMode = false;
  static MatchCache? _instance;
  static HydratedMatchCache? _inMemoryInstance;
  static MatchCache get instance {
    if(_instance == null) {
      if(serverMode) {
        _instance = IsolateMatchCacheClient();
      }
      else {
        _instance = inMemoryInstance;
      }
    }
    return _instance!;
  }

  static HydratedMatchCache get inMemoryInstance {
    if(_inMemoryInstance == null) {
      _inMemoryInstance = HydratedMatchCache();
    }
    return _inMemoryInstance!;
  }
}
