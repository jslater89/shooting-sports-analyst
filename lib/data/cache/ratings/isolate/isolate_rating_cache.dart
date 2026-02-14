import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/data/cache/ratings/isolate/commands.dart';
import 'package:shooting_sports_analyst/data/cache/ratings/memory_rating_cache.dart';
import 'package:shooting_sports_analyst/data/cache/ratings/rating_cache.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_client.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_server_helper.dart';

final _log = SSALogger("IsolateRatingCache");

/// Isolate-backed rating cache client.
///
/// This implementation forwards cache commands to [IsolateRatingCacheServer]
/// through the isolate manager messaging layer.
class IsolateRatingCacheClient implements RatingCache {
  static IsolateRatingCacheClient? _instance;
  factory IsolateRatingCacheClient(IsolateManagerClient isolateManagerClient) {
    if(_instance == null) {
      _instance = IsolateRatingCacheClient._internal(isolateManagerClient);
    }
    return _instance!;
  }
  IsolateRatingCacheClient._internal(this.isolateManagerClient) {
    if(IsolateCommon.isolateId == "unset") {
      throw Exception("IsolateCommon.isolateId is not set. Isolate must be started with IsolateCommon.setup() first in the isolate entrypoint.");
    }
    _init();
  }

  final IsolateManagerClient isolateManagerClient;

  /// Connects this client to the rating cache server isolate.
  Future<void> _init() async {
    await isolateManagerClient.ready;
    await isolateManagerClient.connect(isolateId: IsolateRatingCacheServer.id);
    _readyCompleter.complete(true);
  }

  Future<bool> get clientReady => _readyCompleter.future;
  final Completer<bool> _readyCompleter = Completer();

  @override
  Future<bool> ready() {
    return clientReady;
  }

  @override
  Future<void> cacheRating(int projectId, RatingGroup group, DbShooterRating rating) async {
    await isolateManagerClient.sendCommand<CacheRatingCommand, IsolateRatingCacheResponse>(
      isolateId: IsolateRatingCacheServer.id,
      command: CacheRatingCommand(projectId: projectId, group: group, rating: rating)
    );
  }

  @override
  Future<void> invalidateProject(int projectId) async {
    await isolateManagerClient.sendCommand<InvalidateProjectCommand, IsolateRatingCacheResponse>(
      isolateId: IsolateRatingCacheServer.id,
      command: InvalidateProjectCommand(projectId: projectId)
    );
  }

  @override
  Future<void> invalidateRating(int projectId, RatingGroup group, String memberNumber) async {
    await isolateManagerClient.sendCommand<InvalidateRatingCommand, IsolateRatingCacheResponse>(
      isolateId: IsolateRatingCacheServer.id,
      command: InvalidateRatingCommand(projectId: projectId, group: group, memberNumber: memberNumber)
    );
  }

  @override
  Future<void> clear() async {
    await isolateManagerClient.sendCommand<ClearCommand, IsolateRatingCacheResponse>(
      isolateId: IsolateRatingCacheServer.id,
      command: ClearCommand()
    );
  }

  @override
  Future<DbShooterRating?> lookupRating(int projectId, RatingGroup group, String memberNumber) async {
    var response = await isolateManagerClient.sendCommand<LookupRatingCommand, IsolateRatingCacheResponse>(
      isolateId: IsolateRatingCacheServer.id,
      command: LookupRatingCommand(projectId: projectId, group: group, memberNumber: memberNumber)
    );
    if(response == null) {
      return null;
    }
    var data = response.data;
    if(data is LookupRatingResponse) {
      return data.rating;
    }
    else if(data is ErrorResponse) {
      _log.e("Error response from server isolate: ${data.message}");
      return null;
    }
    else {
      throw Exception("Invalid response from server isolate: ${response.data.runtimeType}");
    }
  }

  /// Initializes isolate-common state on the current isolate and connects a
  /// rating cache client to the rating cache server.
  static Future<IsolateRatingCacheClient> startOnCurrentIsolate(IsolateStartData startData, {
    bool mainIsolate = true,
    bool failOnDuplicateRegistration = true,
  }) async {
    var managerClient = await IsolateCommon.setupClient(
      startData,
      mainIsolate: mainIsolate,
      failOnDuplicateRegistration: failOnDuplicateRegistration,
    );
    var client = IsolateRatingCacheClient(managerClient);
    await client.clientReady;

    return client;
  }
}


/// Server isolate that owns rating cache state in multi-isolate mode.
///
/// Client isolates communicate with this server through command messages.
class IsolateRatingCacheServer {
  static const id = "rating_cache";
  final ReceivePort receivePort;
  late final ServerIsolateHelper<IsolateRatingCacheCommand, IsolateRatingCacheResponse> serverHelper;
  final db = AnalystDatabase();

  final MemoryRatingCache cache = MemoryRatingCache();

  IsolateRatingCacheServer({
    required this.receivePort
  }) {
    serverHelper = ServerIsolateHelper(isolateId: id, commandHandler: _commandHandler);
  }

  /// Handles commands from client isolates and returns typed responses.
  Future<IsolateRatingCacheResponse> _commandHandler(IsolateRatingCacheCommand command) async {
    switch(command) {
      case CacheRatingCommand(projectId: var projectId, group: var group, rating: var rating):
        cache.cacheRating(projectId, group, rating);
        return AckResponse();
      case InvalidateRatingCommand(projectId: var projectId, group: var group, memberNumber: var memberNumber):
        cache.invalidateRating(projectId, group, memberNumber);
        return AckResponse();
      case InvalidateProjectCommand(projectId: var projectId):
        cache.invalidateProject(projectId);
        return AckResponse();
      case LookupRatingCommand(projectId: var projectId, group: var group, memberNumber: var memberNumber):
        var rating = cache.lookupRating(projectId, group, memberNumber);
        return LookupRatingResponse(rating: rating);
      case ClearCommand():
        cache.clear();
        return AckResponse();
    }
  }

  /// Entrypoint for the rating cache server isolate.
  static Future<void> entrypoint(IsolateStartData startData) async {
    IsolateCommon.setup(startData);
    final ratingCacheReceivePort = ReceivePort();
    var server = IsolateRatingCacheServer(receivePort: ratingCacheReceivePort);
    await server.serverHelper.handleStartup(startData: startData);
    await Future.delayed(Duration(days: 10000));
  }
}

