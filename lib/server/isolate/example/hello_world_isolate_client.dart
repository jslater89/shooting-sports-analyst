

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
  static Future<void> entrypoint(IsolateStartData startData) async {
    IsolateCommon.setup(startData);
    var managerClient = IsolateManagerClient(IsolateCommon.isolateId, IsolateCommon.managerSendPort!);
    await managerClient.ready;
    var client = HelloWorldIsolateClient(IsolateCommon.isolateId, managerClient);
    await client.connect();
    _log.i("Client connected to server isolate");
    var helloWorld = await client.getHelloWorld();
    _log.i("Hello world: $helloWorld");
  }
}