
import 'package:shooting_sports_analyst/data/cache/lru_tracker.dart';
import 'package:shooting_sports_analyst/data/cache/ratings/rating_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("MemoryRatingCache");

/// In-process rating cache used for single-isolate execution.
///
/// Data is stored by:
/// `projectId -> group -> memberNumber -> rating`.
///
/// This cache is not isolate-safe because each isolate has its own memory.
/// Since we're storing DbShooterRating objects, however, we can't use a single
/// isolate cache because they're not serializable (IsarLinks contain raw pointers).
class MemoryRatingCache implements RatingCache {
  MemoryRatingCache() : this.lru = null;
  MemoryRatingCache.withLru(this.lru);
  final LruTracker<MemoryRatingCacheLruKey>? lru;

  final Map<int, Map<RatingGroup, Map<String, DbShooterRating>>> _cache = {};

  @override
  bool ready() {
    return true;
  }

  @override
  void cacheRating(int projectId, RatingGroup group, DbShooterRating rating) {
    if(lru != null) {
      var key = MemoryRatingCacheLruKey(projectId: projectId, group: group, memberNumbers: rating.allPossibleMemberNumbers.toList());
      var evicted = lru!.record(key);
      _evictFromLruKey(evicted);
    }
    _cache[projectId] ??= {};
    _cache[projectId]![group] ??= {};
    for(var n in rating.allPossibleMemberNumbers) {
      _cache[projectId]![group]![n] = rating;
    }
  }

  @override
  void invalidateProject(int projectId) {
    if(lru != null) {
      for(var group in _cache[projectId]?.keys ?? <RatingGroup>[]) {
        for(var n in _cache[projectId]?[group]?.keys ?? <String>[]) {
          var rating = _cache[projectId]?[group]?[n];
          if(rating == null) continue;
          var key = MemoryRatingCacheLruKey(projectId: projectId, group: group, memberNumbers: rating.allPossibleMemberNumbers.toList());
          lru!.remove(key);
        }
      }
    }
    _cache.remove(projectId);
  }

  @override
  void invalidateRating(int projectId, RatingGroup group, String memberNumber) {
    if(lru != null) {
      var rating = _cache[projectId]?[group]?[memberNumber];
      if(rating != null) {
        var key = MemoryRatingCacheLruKey(projectId: projectId, group: group, memberNumbers: rating.allPossibleMemberNumbers.toList());
        lru!.remove(key);
      }
    }
    _cache[projectId]?[group]?.remove(memberNumber);
  }

  @override
  DbShooterRating? lookupRating(int projectId, RatingGroup group, String memberNumber) {
    var rating = _cache[projectId]?[group]?[memberNumber];
    if(lru != null) {
      if(rating != null) {
        var key = MemoryRatingCacheLruKey(projectId: projectId, group: group, memberNumbers: rating.allPossibleMemberNumbers.toList());
        var evicted = lru!.record(key);
        _evictFromLruKey(evicted);
      }
    }
    return rating;
  }

  void _evictFromLruKey(MemoryRatingCacheLruKey? key) {
    if(key == null) return;
    if(lru != null) {
      for(var n in key.memberNumbers) {
        _cache[key.projectId]?[key.group]?.remove(n);
      }
    }
  }

  @override
  void clear() {
    if(lru != null) {
      lru!.clear();
    }
    _cache.clear();
  }

  @override
  void printStats() {
    _log.i("cache size: ${_cache.length}");
    if(lru != null) {
      _log.i("lru load factor: ${(lru!.length / lru!.capacity).asPercentage(decimals: 1, includePercent: true)}");
      _log.i("lru size: ${lru!.length}");
    }
  }
}

class MemoryRatingCacheLruKey {
  final int projectId;
  final RatingGroup group;
  final List<String> memberNumbers;

  MemoryRatingCacheLruKey({required this.projectId, required this.group, required this.memberNumbers});

  @override
  bool operator ==(Object other) {
    if(other is! MemoryRatingCacheLruKey) return false;

    if(other.projectId != projectId) return false;
    if(other.group != group) return false;
    if(other.memberNumbers.length != memberNumbers.length) return false;
    if(other.memberNumbers.intersection(memberNumbers).length != memberNumbers.length) return false;

    return true;
  }

  // We can use hashCode rather than stable hashes because they don't survive across restarts.
  @override
  int get hashCode {
    var sortedMemberNumbers = memberNumbers.toList()..sort();
    return combineHashList64([projectId.hashCode, group.hashCode, ...sortedMemberNumbers.map((e) => e.hashCode)]);
  }
}