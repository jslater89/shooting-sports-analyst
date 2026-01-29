

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/example/hello_world_isolate_server.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_client.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("HelloWorldIsolateClient");

class HelloWorldIsolateClient {
  final String isolateId;
  final IsolateManagerClient _isolateManagerClient;

  HelloWorldIsolateClient(this.isolateId, this._isolateManagerClient);

  Future<void> connect() async {
    await _isolateManagerClient.connect(isolateId: HelloWorldServer.id);
  }

  Future<String> getHelloWorld() async {
    var response = await _isolateManagerClient.sendCommand<HelloWorldServerCommand, HelloWorldServerResponse>(
      isolateId: HelloWorldServer.id,
      command: HelloWorldServerCommand()
    );
    if(response == null) {
      throw Exception("No response from server isolate");
    }
    return response.data.data;
  }

  /// The entrypoint for the client isolate, which handles initial setup
  /// (setting up common isolate variables in [IsolateCommon]) and connecting to the server isolate.
  ///
  /// Pass this method to Isolate.spawn to run it on a new isolate, or call [startOnCurrentIsolate] to create a
  /// HelloWorldIsolateClient on the existing isolate.
  static Future<void> entrypoint(IsolateStartData startData) async {
    var client = await startOnCurrentIsolate(startData, mainIsolate: false);

    // Real client code would probably wait on a webserver or some other long-running task, and
    // use the returned client to interact with the server isolate.
    await Future.delayed(Duration(days: 10000));
  }

  /// Create a HelloWorldIsolateClient on the current isolate.
  static Future<HelloWorldIsolateClient> startOnCurrentIsolate(IsolateStartData startData, {bool mainIsolate = false}) async {
    var managerClient = await IsolateCommon.setupClient(startData, mainIsolate: mainIsolate);
    var client = HelloWorldIsolateClient(IsolateCommon.isolateId, managerClient);
    await client.connect();
    _log.i("Client connected to server isolate");
    startData.initPort.send(StartupCompleteResponse(sourceIsolateId: IsolateCommon.isolateId));
    var helloWorld = await client.getHelloWorld();
    _log.i("Hello world: $helloWorld");
    return client;
  }
}