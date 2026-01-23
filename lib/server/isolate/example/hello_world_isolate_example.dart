
import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/example/hello_world_isolate_client.dart';
import 'package:shooting_sports_analyst/server/isolate/example/hello_world_isolate_server.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("HelloWorldIsolateExample");

void main() async {
  var provider = ServerDebugProvider();
  FlutterOrNative.debugModeProvider = provider;
  FlutterOrNative.serverModeProvider = provider;

  // Create the ports for the init isolate and the logger isolate.
  var initIsolateReceivePort = ReceivePort();
  var initIsolateSendPort = initIsolateReceivePort.sendPort;

  var loggerReceivePort = ReceivePort();
  var loggerSendPort = loggerReceivePort.sendPort;

  // Other isolates should use [SSALogger.setupSendPort] to send logs to the logger isolate.
  SSALogger.handleReceivePort(loggerReceivePort);
  _log.i("Logger setup complete");

  // Start the manager isolate and get its send port.
  var managerIsolateSendPort = await IsolateCommon.startManagerIsolate(loggerSendPort: loggerSendPort, initIsolateReceivePort: initIsolateReceivePort);

  var startupReceivePort = ReceivePort();
  startupReceivePort.listen((message) {
    if(message is StartupCompleteResponse) {
      _log.i("Startup complete for isolate ${message.sourceIsolateId}");
    }
  });
  // Set up the final init data for non-manager isolates.
  final initData = IsolateStartData(
    isolateId: "",
    logPort: loggerSendPort,
    initPort: startupReceivePort.sendPort,
    managerPort: managerIsolateSendPort,
  );

  // Spawn the server isolate. Its helper will register with the manager isolate.
  var helloWorldServerIsolate = await Isolate.spawn(HelloWorldServer.entrypoint, initData.copyWithId(HelloWorldServer.id));

  // Spawn the client isolates. They will use their own isolate's IsolateManagerClient to connect to the server isolate.
  var helloWorldClientIsolate1 = await Isolate.spawn(HelloWorldIsolateClient.entrypoint, initData.copyWithId("hello_client1"));
  var helloWorldClientIsolate2 = await Isolate.spawn(HelloWorldIsolateClient.entrypoint, initData.copyWithId("hello_client2"));

  var mainIsolateData = initData.copyWithId("main");
  var mainIsolateClient = await HelloWorldIsolateClient.startOnCurrentIsolate(mainIsolateData, existingIsolate: true);
  _log.i("Server and client isolates spawned");
}