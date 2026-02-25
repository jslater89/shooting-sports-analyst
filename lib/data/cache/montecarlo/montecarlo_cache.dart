import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';

/// A cache for Monte Carlo prediction probability simulation results.
///
/// It is backed by an implementation of [IMonteCarloCache], which is selected at runtime.
/// At present, only the isolate-backed implementation is available, and only used in
/// multi-isolate/server mode.
class MonteCarloCache implements IMonteCarloCache {
  static MonteCarloCache? _instance;

  IMonteCarloCache? _delegate;

  factory MonteCarloCache({IMonteCarloCache? delegate}) {
    if(_instance == null) {
      _instance = MonteCarloCache._internal(delegate);
    }
    return _instance!;
  }

  MonteCarloCache._internal(this._delegate);

  void setDelegate(IMonteCarloCache? delegate) {
    _delegate = delegate;
  }

  @override
  Future<void> cache(MonteCarloSimulationLruKey key, MonteCarloSimulationResult entry) async {
    return _delegate?.cache(key, entry);
  }

  @override
  Future<MonteCarloSimulationResult?> lookup(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) async {
    return _delegate?.lookup(key, additionalKeys: additionalKeys);
  }

  @override
  Future<void> invalidate(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) async {
    return _delegate?.invalidate(key, additionalKeys: additionalKeys);
  }

  @override
  Future<void> invalidatePredictionSets(List<int> predictionSetIds) async {
    return _delegate?.invalidatePredictionSets(predictionSetIds);
  }

  @override
  Future<void> invalidatePredictionSet(int predictionSetId) async {
    return _delegate?.invalidatePredictionSet(predictionSetId);
  }

  @override
  Future<void> invalidateMatchPrep(MatchPrep matchPrep) async {
    return _delegate?.invalidateMatchPrep(matchPrep);
  }

  @override
  Future<void> clear() async {
    return _delegate?.clear();
  }

  @override
  Future<void> printStats() async {
    return _delegate?.printStats();
  }
}

abstract interface class IMonteCarloCache {
  Future<void> cache(MonteCarloSimulationLruKey key, MonteCarloSimulationResult entry);
  Future<MonteCarloSimulationResult?> lookup(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []});
  Future<void> invalidate(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []});
  Future<void> invalidatePredictionSets(List<int> predictionSetIds);
  Future<void> invalidatePredictionSet(int predictionSetId);
  Future<void> invalidateMatchPrep(MatchPrep matchPrep);
  Future<void> clear();
  Future<void> printStats();
}