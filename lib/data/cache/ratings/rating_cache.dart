import 'dart:async';

import 'package:shooting_sports_analyst/data/cache/ratings/memory_rating_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("RatingCache");

/// Mode-aware interface for shooter rating cache access.
///
/// Implementations are selected at runtime:
/// - single-isolate mode uses [MemoryRatingCache]
/// - multi-isolate mode must use an isolate-backed implementation
///   (for example, [IsolateRatingCacheClient]).
abstract interface class RatingCache {
  /// Returns whether the cache is ready to accept requests.
  FutureOr<bool> ready();
  /// Looks up a cached rating by project, group, and member number.
  FutureOr<DbShooterRating?> lookupRating(int projectId, RatingGroup group, String memberNumber);
  /// Caches a rating under all of its known lookup keys.
  FutureOr<void> cacheRating(int projectId, RatingGroup group, DbShooterRating rating);
  /// Invalidates a single cached rating entry.
  FutureOr<void> invalidateRating(int projectId, RatingGroup group, String memberNumber);
  /// Invalidates all cached entries for a project.
  FutureOr<void> invalidateProject(int projectId);
  /// Clears all cached entries.
  FutureOr<void> clear();

  static RatingCache? _instance;
  static MemoryRatingCache? _inMemoryInstance;
  static setInstance(RatingCache instance) {
    _instance = instance;
    if(instance is MemoryRatingCache) {
      _inMemoryInstance = instance;
    }
  }

  static RatingCache get instance {
    var serverMode = FlutterOrNative.isolateModeProvider.kMultiIsolateMode;
    if(_instance == null) {
      if(serverMode) {
        _log.i("Server mode: using isolate rating cache");
        if(_instance == null) {
          throw Exception("RatingCache must be set before use in server mode.");
        }
      }
      else {
        _log.i("Not server mode: using in-memory rating cache");
        _instance = inMemoryInstance;
      }
    }
    return _instance!;
  }

  /// Returns a process-local, synchronous in-memory cache instance.
  ///
  /// This is safe and convenient in single-isolate contexts. In multi-isolate
  /// contexts, callers should prefer [instance] with an isolate-aware cache.
  static MemoryRatingCache get inMemoryInstance {
    if(_inMemoryInstance == null) {
      _inMemoryInstance = MemoryRatingCache();
    }
    return _inMemoryInstance!;
  }
}