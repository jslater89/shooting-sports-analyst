/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:async";
import "dart:io";
import "dart:isolate";

import "package:shooting_sports_analyst/data/cache/constants.dart";
import "package:shooting_sports_analyst/data/cache/match/match_cache.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/hydrated_cache.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/server/isolate/isolate_client.dart";
import "package:shooting_sports_analyst/server/isolate/isolate_common.dart";
import "package:shooting_sports_analyst/server/isolate/isolate_messages.dart";
import "package:shooting_sports_analyst/server/isolate/isolate_server_helper.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("IsolateMatchCache");

/// A client for the isolate-based match cache, which connects to the
/// server isolate to cache and look up matches.
class IsolateMatchCacheClient implements MatchCache {
  static IsolateMatchCacheClient? _instance;
  factory IsolateMatchCacheClient(IsolateManagerClient isolateManagerClient) {
    if(_instance == null) {
      _instance = IsolateMatchCacheClient._internal(isolateManagerClient);
    }
    return _instance!;
  }
  IsolateMatchCacheClient._internal(this.isolateManagerClient) {
    if(IsolateCommon.isolateId == "unset") {
      throw Exception("IsolateCommon.isolateId is not set. Isolate must be started with IsolateCommon.setup() first in the isolate entrypoint.");
    }
    _init();
  }

  Future<void> _init() async {
    await isolateManagerClient.ready;
    await isolateManagerClient.connect(isolateId: IsolateMatchCacheServer.id);
    _readyCompleter.complete(true);
  }

  Future<bool> get clientReady => _readyCompleter.future;
  final Completer<bool> _readyCompleter = Completer();

  final IsolateManagerClient isolateManagerClient;

  @override
  Future<bool> ready() {
    return clientReady;
  }

  @override
  Future<void> cache(ShootingMatch match) async {
    await isolateManagerClient.sendCommand<_CacheCommand, _IsolateMatchCacheServerResponse>(
      isolateId: IsolateMatchCacheServer.id,
      command: _CacheCommand(match: match)
    );
  }

  @override
  Future<void> clear() async {
    await isolateManagerClient.sendCommand<_ClearCommand, _IsolateMatchCacheServerResponse>(
      isolateId: IsolateMatchCacheServer.id,
      command: _ClearCommand()
    );
  }

  @override
  Future<Result<ShootingMatch, ResultErr>> get(DbShootingMatch match) async {
    var response = await isolateManagerClient.sendCommand<_GetByDbIdCommand, _IsolateMatchCacheServerResponse>(
      isolateId: IsolateMatchCacheServer.id,
      command: _GetByDbIdCommand(id: match.id, sourceLastUpdated: match.sourceLastUpdated)
    );

    if(response == null) {
      return Result.err(StringError("No response from server isolate"));
    }
    var data = response.data;
    if(data is _MatchResponse) {
      return Result.ok(data.match);
    }
    else if(data is _ErrorResponse) {
      return Result.err(StringError(data.message));
    }
    else {
      return Result.err(StringError("Invalid response from server isolate: ${data.runtimeType}"));
    }
  }

  @override
  Future<Result<ShootingMatch, ResultErr>> getBySourceId(String sourceId, {DateTime? sourceLastUpdated}) async {
    var response = await isolateManagerClient.sendCommand<_GetBySourceIdCommand, _IsolateMatchCacheServerResponse>(
      isolateId: IsolateMatchCacheServer.id,
      command: _GetBySourceIdCommand(sourceId: sourceId, sourceLastUpdated: sourceLastUpdated)
    );

    if(response == null) {
      return Result.err(StringError("No response from server isolate"));
    }
    var data = response.data;
    if(data is _MatchResponse) {
      return Result.ok(data.match);
    }
    else if(data is _ErrorResponse) {
      return Result.err(StringError(data.message));
    }
    else {
      return Result.err(StringError("Invalid response from server isolate: ${data.runtimeType}"));
    }
  }

  @override
  Future<void> remove(int id) async {
    await isolateManagerClient.sendCommand<_RemoveCommand, _IsolateMatchCacheServerResponse>(
      isolateId: IsolateMatchCacheServer.id,
      command: _RemoveCommand(id: id)
    );
  }

  static Future<IsolateMatchCacheClient> startOnCurrentIsolate(IsolateStartData startData, {
    bool mainIsolate = true,
    bool failOnDuplicateRegistration = true,
  }) async {
    var managerClient = await IsolateCommon.setupClient(
      startData,
      mainIsolate: mainIsolate,
      failOnDuplicateRegistration: failOnDuplicateRegistration,
    );
    var client = IsolateMatchCacheClient(managerClient);
    await client.clientReady;

    return client;
  }
}

/// A server isolate that wraps a [HydratedMatchCache] and provides an isolate server interface for it.
///
/// This allows the cache to be used by multiple worker isolates.
class IsolateMatchCacheServer {
  static const id = "match_cache";
  final ReceivePort receivePort;
  late final ServerIsolateHelper<_IsolateMatchCacheServerCommand, _IsolateMatchCacheServerResponse> serverHelper;
  final db = AnalystDatabase();

  late final HydratedMatchCache cache;

  IsolateMatchCacheServer({
    required this.receivePort
  }) {
    serverHelper = ServerIsolateHelper(isolateId: id, commandHandler: _commandHandler);
    final matchLruSizeString = Platform.environment[matchLruSizeEnv] ?? "";
    final matchLruSize = int.tryParse(matchLruSizeString);
    cache = HydratedMatchCache(useLru: matchLruSize != null, lruCapacity: matchLruSize ?? 250);
    if(matchLruSize != null) {
      _log.i("Using LRU match cache with size $matchLruSize");
    }

  }

  Future<_IsolateMatchCacheServerResponse> _commandHandler(_IsolateMatchCacheServerCommand command) async {
    switch(command) {
      case _CacheCommand(match: var match):
        cache.cache(match);
        return _AckResponse();

      case _RemoveCommand(id: var id):
        cache.remove(id);
        return _AckResponse();

      case _ClearCommand():
        cache.clear();
        return _AckResponse();

      case _GetByMatchCommand(match: var match):
        var result = cache.get(match);
        if(result.isOk()) {
          return _MatchResponse(match: result.unwrap());
        }
        else {
          return _ErrorResponse(message: result.unwrapErr().message);
        }

      case _GetByDbIdCommand(id: var matchId, sourceLastUpdated: var sourceLastUpdated):
        if(cache.contains(matchId)) {
          var result = cache.getById(matchId, sourceLastUpdated: sourceLastUpdated);
          var match = result.unwrap();
          _log.v("Cache hit, returning match: ${match.name}");
          return _MatchResponse(match: result.unwrap());
        }
        else {
          _log.v("Cache miss, loading from database");
          var match = await db.getMatch(matchId);
          if(match == null) {
            return _ErrorResponse(message: "Match not found");
          }
          var hydrated = await match.hydrate();
          if(hydrated.isErr()) {
            return _ErrorResponse(message: "Failed to hydrate match: ${hydrated.unwrapErr().message}");
          }
          var hydratedMatch = hydrated.unwrap();
          cache.cache(hydratedMatch);
          _log.v("Cached match: ${hydratedMatch.name}");
          return _MatchResponse(match: hydratedMatch);
        }

      case _GetBySourceIdCommand(sourceId: var sourceId, sourceLastUpdated: var sourceLastUpdated):
        var result = cache.getBySourceId(sourceId, sourceLastUpdated: sourceLastUpdated);
        if(result.isOk()) {
          return _MatchResponse(match: result.unwrap());
        }
        else {
          return _ErrorResponse(message: result.unwrapErr().message);
        }
    }
  }

  static Future<void> entrypoint(IsolateStartData startData) async {
    IsolateCommon.setup(startData);
    final matchCacheReceivePort = ReceivePort();
    var server = IsolateMatchCacheServer(receivePort: matchCacheReceivePort);
    await server.serverHelper.handleStartup(startData: startData);
    await Future.delayed(Duration(days: 10000));
  }
}

/// A command from a client isolate to the match cache server isolate.
sealed class _IsolateMatchCacheServerCommand {
  const _IsolateMatchCacheServerCommand();
}

/// Cache a match, overwriting any existing match with the same database ID
/// and source IDs.
///
/// Responds with [_AckResponse] if the command was received and processed,
/// or [_ErrorResponse] if the command was invalid.
class _CacheCommand extends _IsolateMatchCacheServerCommand {
  final ShootingMatch match;

  const _CacheCommand({required this.match});
}

/// Remove a match from the cache by its database ID.
///
/// Responds with [_AckResponse] if the command was received and processed,
/// even if the match was not found in the cache.
class _RemoveCommand extends _IsolateMatchCacheServerCommand {
  final int id;

  const _RemoveCommand({required this.id});
}

/// Clear the cache.
///
/// Responds with [_AckResponse] if the command was received and processed.
class _ClearCommand extends _IsolateMatchCacheServerCommand {
  const _ClearCommand();
}

/// Get a hydrated match from the cache by its database ID. Unlike the MatchCache interface,
/// this takes a raw database ID rather than a [DbShootingMatch] object. The server isolate
/// load the match from the database and hydrate it if it is not already in the cache.
///
/// Responds with [_MatchResponse] if the match could be found in
/// the cache or was loaded from the database and cached. Responds with [_ErrorResponse]
/// if the match was not found in the database.
class _GetByDbIdCommand extends _IsolateMatchCacheServerCommand {
  final int id;
  final DateTime? sourceLastUpdated;

  const _GetByDbIdCommand({required this.id, this.sourceLastUpdated});
}

/// Get a hydrated match from the cache by a [DbShootingMatch] object.
///
/// Responds with [_MatchResponse] if the match was found in the cache
/// or [_ErrorResponse] if the match was not found in the cache.
///
/// Note that get does not attempt to load the match from the database if it is not found in the cache.
class _GetByMatchCommand extends _IsolateMatchCacheServerCommand {
  final DbShootingMatch match;

  const _GetByMatchCommand({required this.match});
}

///
/// Responds with [_MatchResponse] if the match was found in the cache
/// or [_ErrorResponse] if the match was not found in the cache.
///
/// Note that getBySourceId does not attempt to load the match from the database if it is not found in the cache.
class _GetBySourceIdCommand extends _IsolateMatchCacheServerCommand {
  final String sourceId;
  final DateTime? sourceLastUpdated;

  const _GetBySourceIdCommand({required this.sourceId, this.sourceLastUpdated});
}

/// A response from the match cache server isolate to a client isolate.
sealed class _IsolateMatchCacheServerResponse {
  const _IsolateMatchCacheServerResponse();
}

/// A hydrated match.
class _MatchResponse extends _IsolateMatchCacheServerResponse {
  final ShootingMatch match;

  const _MatchResponse({required this.match});
}

/// A simple acknowledgement that the command was received and processed, without any associated data.
class _AckResponse extends _IsolateMatchCacheServerResponse {
  const _AckResponse();
}

/// An error message.
class _ErrorResponse extends _IsolateMatchCacheServerResponse {
  final String message;

  const _ErrorResponse({required this.message});
}
