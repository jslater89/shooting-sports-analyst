import 'package:shooting_sports_analyst/data/cache/lru_tracker.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("MonteCarloSimulationCache");

/// A cache for Monte Carlo prediction probability simulation results.
///
/// It is keyed by a [MonteCarloSimulationLruKey] and contains a [MonteCarloSimulationResult].
/// Cache entries are valid for a prediction set (i.e. also a match prep and project), a shooter,
/// and a number of trials.
class MonteCarloSimulationCache implements IMonteCarloCache {
  final Map<MonteCarloSimulationLruKey, MonteCarloSimulationResult> _cache = {};
  late final LruTracker<MonteCarloSimulationLruKey> _lru;

  MonteCarloSimulationCache({required int capacity}) {
    _lru = LruTracker<MonteCarloSimulationLruKey>(capacity: capacity);
  }

  /// Caches an entry by key and updates the LRU tracker.
  void cacheSync(MonteCarloSimulationLruKey key, MonteCarloSimulationResult entry, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) {
    _cache[key] = entry;
    var evicted = _lru.record(key);
    _evictFromLruKey(evicted);
    for(var additionalKey in additionalKeys) {
      _cache[additionalKey] = entry;
      evicted = _lru.record(additionalKey);
      _evictFromLruKey(evicted);
    }
  }

  /// Looks up a cached entry by key and update the LRU tracker.
  MonteCarloSimulationResult? lookupSync(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) {
    var entry = _cache[key];
    if(entry != null) {
      var evicted = _lru.record(key);
      _evictFromLruKey(evicted);
    }
    for(var additionalKey in additionalKeys) {
      entry ??= _cache[additionalKey];
      if(entry != null) {
        var evicted = _lru.record(additionalKey);
        _evictFromLruKey(evicted);
      }
    }
    return entry;
  }

  /// Invalidates a single cached entry.
  void invalidateSync(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) {
    _cache.remove(key);
    _lru.remove(key);
    for(var additionalKey in additionalKeys) {
      _cache.remove(additionalKey);
      _lru.remove(additionalKey);
    }
  }

  /// Invalidate all cached entries for all prediction sets in a match prep.
  Future<void> invalidateMatchPrepSync(MatchPrep matchPrep) async {
    await matchPrep.predictionSets.load();
    List<int> predictionSetIds = [];
    for(var predictionSet in matchPrep.predictionSets) {
      predictionSetIds.add(predictionSet.id);
    }
    invalidatePredictionSetsSync(predictionSetIds);
  }

  /// Invalidates all cached entries for a prediction set.
  void invalidatePredictionSetSync(int predictionSetId) {
    invalidatePredictionSetsSync([predictionSetId]);
  }

  /// Invalidates all cached entries for a list of prediction sets.
  void invalidatePredictionSetsSync(List<int> predictionSetIds) {
    final keys = [..._cache.keys.where((key) => predictionSetIds.contains(key.predictionSetId))];
    for(var key in keys) {
      invalidateSync(key);
    }
  }

  void clearSync() {
    _cache.clear();
    _lru.clear();
  }

  /// Helper to evict a cache entry when the LRU tracker evicts it.
  void _evictFromLruKey(MonteCarloSimulationLruKey? key) {
    if(key == null) return;
    _cache.remove(key);
  }

  void printStatsSync() {
    _log.i("cache entries/size/load factor: ${_cache.length}/${_lru.capacity}/${(_lru.length / _lru.capacity).asPercentage(decimals: 1, includePercent: true)}");
  }

  @override
  Future<void> cache(MonteCarloSimulationLruKey key, MonteCarloSimulationResult entry, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) async {
    cacheSync(key, entry, additionalKeys: additionalKeys);
  }

  @override
  Future<void> clear() async {
    clearSync();
  }

  @override
  Future<void> invalidate(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) async {
    invalidateSync(key, additionalKeys: additionalKeys);
  }

  @override
  Future<void> invalidateMatchPrep(MatchPrep matchPrep) async {
    invalidateMatchPrepSync(matchPrep);
  }

  @override
  Future<void> invalidatePredictionSet(int predictionSetId) async {
    invalidatePredictionSetSync(predictionSetId);
  }

  @override
  Future<void> invalidatePredictionSets(List<int> predictionSetIds) async {
    invalidatePredictionSetsSync(predictionSetIds);
  }

  @override
  Future<MonteCarloSimulationResult?> lookup(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) async {
    return lookupSync(key, additionalKeys: additionalKeys);
  }

  @override
  Future<void> printStats() async {
    printStatsSync();
  }
}