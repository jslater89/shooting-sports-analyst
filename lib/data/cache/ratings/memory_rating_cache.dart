
import 'package:shooting_sports_analyst/data/cache/ratings/rating_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

/// In-process rating cache used for single-isolate execution.
///
/// Data is stored by:
/// `projectId -> group -> memberNumber -> rating`.
///
/// This cache is not isolate-safe because each isolate has its own memory.
class MemoryRatingCache implements RatingCache {
  final Map<int, Map<RatingGroup, Map<String, DbShooterRating>>> _cache = {};

  @override
  bool ready() {
    return true;
  }

  @override
  void cacheRating(int projectId, RatingGroup group, DbShooterRating rating) {
    _cache[projectId] ??= {};
    _cache[projectId]![group] ??= {};
    for(var n in rating.allPossibleMemberNumbers) {
      _cache[projectId]![group]![n] = rating;
    }
  }

  @override
  void invalidateProject(int projectId) {
    _cache.remove(projectId);
  }

  @override
  void invalidateRating(int projectId, RatingGroup group, String memberNumber) {
    _cache[projectId]![group]!.remove(memberNumber);
  }

  @override
  DbShooterRating? lookupRating(int projectId, RatingGroup group, String memberNumber) {
    return _cache[projectId]?[group]?[memberNumber];
  }

  @override
  void clear() {
    _cache.clear();
  }
}