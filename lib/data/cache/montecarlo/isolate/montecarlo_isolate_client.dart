import 'dart:async';

import 'package:shooting_sports_analyst/data/cache/montecarlo/isolate/montecarlo_isolate_server.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_client.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';

final _log = SSALogger("MonteCarloIsolateClient");

/// A client for the isolate-based Monte Carlo cache, which connects to the
/// server isolate to cache and look up Monte Carlo simulation results.
class MonteCarloIsolateClient implements IMonteCarloCache {
  static MonteCarloIsolateClient? _instance;
  factory MonteCarloIsolateClient(IsolateManagerClient isolateManagerClient) {
    if(_instance == null) {
      _instance = MonteCarloIsolateClient._internal(isolateManagerClient);
    }
    return _instance!;
  }

  MonteCarloIsolateClient._internal(this.isolateManagerClient) {
    if(IsolateCommon.isolateId == "unset") {
      throw Exception("IsolateCommon.isolateId is not set. Isolate must be started with IsolateCommon.setup() first in the isolate entrypoint.");
    }
    _init();
  }

  Future<void> _init() async {
    await isolateManagerClient.ready;
    await isolateManagerClient.connect(isolateId: MonteCarloIsolateServer.id);
    _readyCompleter.complete(true);
  }

  Future<bool> get clientReady => _readyCompleter.future;
  final Completer<bool> _readyCompleter = Completer();

  final IsolateManagerClient isolateManagerClient;

  @override
  Future<void> cache(MonteCarloSimulationLruKey key, MonteCarloSimulationResult entry, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) {
    return isolateManagerClient.sendCommand<CacheCommand, MonteCarloIsolateServerResponse>(
      isolateId: MonteCarloIsolateServer.id,
      command: CacheCommand(key: key, entry: entry, additionalKeys: additionalKeys),
    );
  }

  @override
  Future<void> clear() {
    return isolateManagerClient.sendCommand<ClearCommand, MonteCarloIsolateServerResponse>(
      isolateId: MonteCarloIsolateServer.id,
      command: ClearCommand(),
    );
  }

  @override
  Future<void> invalidate(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) {
    return isolateManagerClient.sendCommand<InvalidateKeyCommand, MonteCarloIsolateServerResponse>(
      isolateId: MonteCarloIsolateServer.id,
      command: InvalidateKeyCommand(key: key, additionalKeys: additionalKeys),
    );
  }

  @override
  Future<void> invalidateMatchPrep(MatchPrep matchPrep) async {
    List<int> predictionSetIds = [];
    await matchPrep.predictionSets.load();
    for(var predictionSet in matchPrep.predictionSets) {
      predictionSetIds.add(predictionSet.id);
    }
    return invalidatePredictionSets(predictionSetIds);
  }

  @override
  Future<void> invalidatePredictionSet(int predictionSetId) {
    return invalidatePredictionSets([predictionSetId]);
  }

  @override
  Future<void> invalidatePredictionSets(List<int> predictionSetIds) {
    return isolateManagerClient.sendCommand<InvalidatePredictionSetsCommand, MonteCarloIsolateServerResponse>(
      isolateId: MonteCarloIsolateServer.id,
      command: InvalidatePredictionSetsCommand(predictionSetIds: predictionSetIds),
    );
  }

  @override
  Future<MonteCarloSimulationResult?> lookup(MonteCarloSimulationLruKey key, {List<MonteCarloSimulationLruKey> additionalKeys = const []}) async {
    final response = await isolateManagerClient.sendCommand<LookupCommand, MonteCarloIsolateServerResponse>(
      isolateId: MonteCarloIsolateServer.id,
      command: LookupCommand(key: key, additionalKeys: additionalKeys),
    );

    if(response == null) {
      _log.e("No response from server isolate");
      return null;
    }
    var data = response.data;
    if(data is LookupResponse) {
      return data.entry;
    }
    else if(data is ErrorResponse) {
        _log.e("Error response from server isolate: ${data.message}");
        return null;
    }
    else {
      _log.e("Invalid response from server isolate: ${data.runtimeType}");
      return null;
    }
  }

  static Future<MonteCarloIsolateClient> startOnCurrentIsolate(IsolateStartData startData, {
    bool mainIsolate = true,
    bool failOnDuplicateRegistration = true,
  }) async {
    var managerClient = await IsolateCommon.setupClient(
      startData,
      mainIsolate: mainIsolate,
      failOnDuplicateRegistration: failOnDuplicateRegistration,
    );
    var client = MonteCarloIsolateClient(managerClient);
    await client.clientReady;
    return client;
  }
}