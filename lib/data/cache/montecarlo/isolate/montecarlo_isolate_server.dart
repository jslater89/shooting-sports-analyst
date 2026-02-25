import 'dart:isolate';

import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_server_helper.dart';

/// A server isolate that wraps a [MonteCarloSimulationCache] and provides an isolate server interface for it.
///
/// This allows the cache to be used by multiple worker isolates.
class MonteCarloIsolateServer {
  static const id = "montecarlo-cache";
  final ReceivePort receivePort;
  late final ServerIsolateHelper<MonteCarloIsolateServerCommand, MonteCarloIsolateServerResponse> serverHelper;
  final db = AnalystDatabase();

  late final MonteCarloSimulationCache cache;

  MonteCarloIsolateServer({
    required this.receivePort,
    int capacity = 1000,
  }) {
    serverHelper = ServerIsolateHelper(isolateId: id, commandHandler: _commandHandler);
    cache = MonteCarloSimulationCache(capacity: capacity);
  }

  Future<MonteCarloIsolateServerResponse> _commandHandler(MonteCarloIsolateServerCommand command) async {
    switch(command) {
      case CacheCommand(key: var key, entry: var entry, additionalKeys: var additionalKeys):
        cache.cache(key, entry, additionalKeys: additionalKeys);
        return AckResponse();
      case LookupCommand(key: var key, additionalKeys: var additionalKeys):
        return LookupResponse(entry: cache.lookup(key, additionalKeys: additionalKeys));
      case InvalidateKeyCommand(key: var key, additionalKeys: var additionalKeys):
        cache.invalidate(key, additionalKeys: additionalKeys);
        return AckResponse();
      case InvalidatePredictionSetsCommand(predictionSetIds: var predictionSetIds):
        cache.invalidatePredictionSets(predictionSetIds);
        return AckResponse();
      case ClearCommand():
        cache.clear();
        return AckResponse();
      case PrintCacheStatsCommand():
        cache.printStats();
        return AckResponse();
    }
  }

  static Future<void> entrypoint(IsolateStartData startData) async {
    IsolateCommon.setup(startData);
    final monteCarloCacheReceivePort = ReceivePort();
    var server = MonteCarloIsolateServer(receivePort: monteCarloCacheReceivePort);
    await server.serverHelper.handleStartup(startData: startData);
    await Future.delayed(Duration(days: 10000));
  }
}

sealed class MonteCarloIsolateServerCommand {
  const MonteCarloIsolateServerCommand();
}

sealed class MonteCarloIsolateServerResponse {
  const MonteCarloIsolateServerResponse();
}

class CacheCommand extends MonteCarloIsolateServerCommand {
  final MonteCarloSimulationLruKey key;
  final MonteCarloSimulationResult entry;
  final List<MonteCarloSimulationLruKey> additionalKeys;
  CacheCommand({required this.key, required this.entry, this.additionalKeys = const []});
}

class LookupCommand extends MonteCarloIsolateServerCommand {
  final MonteCarloSimulationLruKey key;
  final List<MonteCarloSimulationLruKey> additionalKeys;
  LookupCommand({required this.key, this.additionalKeys = const []});
}

class InvalidateKeyCommand extends MonteCarloIsolateServerCommand {
  final MonteCarloSimulationLruKey key;
  final List<MonteCarloSimulationLruKey> additionalKeys;
  InvalidateKeyCommand({required this.key, this.additionalKeys = const []});
}

class InvalidatePredictionSetsCommand extends MonteCarloIsolateServerCommand {
  final List<int> predictionSetIds;

  InvalidatePredictionSetsCommand({required this.predictionSetIds});
}

class ClearCommand extends MonteCarloIsolateServerCommand {
  const ClearCommand();
}

class PrintCacheStatsCommand extends MonteCarloIsolateServerCommand {
  const PrintCacheStatsCommand();
}

class AckResponse extends MonteCarloIsolateServerResponse {
  const AckResponse();
}

class LookupResponse extends MonteCarloIsolateServerResponse {
  final MonteCarloSimulationResult? entry;

  LookupResponse({required this.entry});
}

class ErrorResponse extends MonteCarloIsolateServerResponse {
  final String message;

  ErrorResponse({required this.message});
}