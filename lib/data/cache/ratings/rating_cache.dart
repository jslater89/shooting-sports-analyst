import 'dart:async';
import 'dart:io';

import 'package:shooting_sports_analyst/data/cache/constants.dart';
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
    final lruSizeString = Platform.environment[ratingLruSizeEnv] ?? "";
    final lruSize = int.tryParse(lruSizeString);
    final lru = lruSize != null ? LruTracker<MemoryRatingCacheLruKey>(capacity: lruSize) : null;
    var multiIsolateMode = FlutterOrNative.isolateModeProvider.kMultiIsolateMode;
    if(multiIsolateMode) {
      _instance ??= MemoryRatingCache.withLru(lru);
    }
    else {
      _instance ??= MemoryRatingCache();
    }
    return _instance!;
  }
}