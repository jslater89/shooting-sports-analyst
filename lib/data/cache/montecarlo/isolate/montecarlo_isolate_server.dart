/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';
import 'dart:isolate';

import 'package:shooting_sports_analyst/data/cache/constants.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/monte_carlo_simulation_result.dart';
import 'package:shooting_sports_analyst/data/cache/montecarlo/montecarlo_lru_key.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_server_helper.dart';

final _log = SSALogger("MonteCarloIsolateServer");

/// A server isolate that wraps a [MonteCarloSimulationCache] and provides an isolate server interface for it.
///
/// This allows the cache to be used by multiple worker isolates.
class MonteCarloIsolateServer {
  static const id = "montecarlo-cache";
  final ReceivePort receivePort;
  late final ServerIsolateHelper<MonteCarloIsolateServerCommand, MonteCarloIsolateServerResponse> serverHelper;

  late final MonteCarloSimulationCache cache;

  MonteCarloIsolateServer({
    required this.receivePort,
  }) {
    final monteCarloLruSizeString = Platform.environment[monteCarloLruSizeEnv] ?? "";
    final monteCarloLruSize = int.tryParse(monteCarloLruSizeString);
    serverHelper = ServerIsolateHelper(isolateId: id, commandHandler: _commandHandler);
    cache = MonteCarloSimulationCache(capacity: monteCarloLruSize ?? 1000);
    _log.i("Using LRU monte carlo cache with size ${monteCarloLruSize ?? 1000}");
  }

  Future<MonteCarloIsolateServerResponse> _commandHandler(MonteCarloIsolateServerCommand command) async {
    switch(command) {
      case CacheCommand(key: var key, entry: var entry, additionalKeys: var additionalKeys):
        cache.cacheSync(key, entry, additionalKeys: additionalKeys);
        return AckResponse();
      case LookupCommand(key: var key, additionalKeys: var additionalKeys):
        return LookupResponse(entry: cache.lookupSync(key, additionalKeys: additionalKeys));
      case InvalidateKeyCommand(key: var key, additionalKeys: var additionalKeys):
        cache.invalidateSync(key, additionalKeys: additionalKeys);
        return AckResponse();
      case InvalidatePredictionSetsCommand(predictionSetIds: var predictionSetIds):
        cache.invalidatePredictionSetsSync(predictionSetIds);
        return AckResponse();
      case ClearCommand():
        cache.clearSync();
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