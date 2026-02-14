import 'dart:async';

import 'package:shooting_sports_analyst/data/cache/lru_tracker.dart';
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
  bool ready();
  /// Looks up a cached rating by project, group, and member number.
  DbShooterRating? lookupRating(int projectId, RatingGroup group, String memberNumber);
  /// Caches a rating under all of its known lookup keys.
  void cacheRating(int projectId, RatingGroup group, DbShooterRating rating);
  /// Invalidates a single cached rating entry.
  void invalidateRating(int projectId, RatingGroup group, String memberNumber);
  /// Invalidates all cached entries for a project.
  void invalidateProject(int projectId);
  /// Clears all cached entries.
  void clear();

  static RatingCache? _instance;

  static RatingCache get instance {
    var serverMode = FlutterOrNative.isolateModeProvider.kMultiIsolateMode;
    if(serverMode) {
      _instance ??= MemoryRatingCache.withLru(LruTracker<MemoryRatingCacheLruKey>(capacity: 5000));
    }
    else {
      _instance ??= MemoryRatingCache();
    }
    return _instance!;
  }
}