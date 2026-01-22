
import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/example/hello_world_isolate_client.dart';
import 'package:shooting_sports_analyst/server/isolate/example/hello_world_isolate_server.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("HelloWorldIsolateExample");

void main() async {
  FlutterOrNative.debugModeProvider = ServerDebugProvider();
  // Create the ports for the init isolate and the logger isolate.
  var initIsolateReceivePort = ReceivePort();
  var initIsolateSendPort = initIsolateReceivePort.sendPort;

  var loggerReceivePort = ReceivePort();
  var loggerSendPort = loggerReceivePort.sendPort;

  // Other isolates should use [SSALogger.setupSendPort] to send logs to the logger isolate.
  SSALogger.handleReceivePort(loggerReceivePort);
  _log.i("Logger setup complete");

  // Create the manager isolate and get its send port.
  final Completer<SendPort> managerIsolateSendPortCompleter = Completer();
  final Function(dynamic) initReceivePortHandler = (message) {
    _log.v("Init isolate received message: ${message.runtimeType}");
    if(message is IsolateConnectionResponse) {
      managerIsolateSendPortCompleter.complete(message.sendPort);
    }
    else {
      _log.e("Init isolate received unexpected message: ${message.runtimeType}");
      if(message is IsolateMessage) {
        _log.e("IsolateMessage: ${message.sourceIsolateId} -> ${message.destinationIsolateId}");
      }
      return;
    }
  };
  _log.i("Init isolate receive port listener set up");
  initIsolateReceivePort.listen(initReceivePortHandler);

  var managerIsolate = await Isolate.spawn(
    IsolateManagerServer.entrypoint,
    IsolateStartData(logPort: loggerSendPort, initPort: initIsolateSendPort, managerPort: null),
  );
  _log.i("Manager isolate spawned");
  var managerIsolateSendPort = await managerIsolateSendPortCompleter.future;
  _log.i("Manager isolate send port received");

  // Set up the final init data for non-manager isolates.
  final initData = IsolateStartData(
    logPort: loggerSendPort,
    initPort: initIsolateSendPort,
    managerPort: managerIsolateSendPort,
  );

  // Spawn the server isolate. Its helper will register with the manager isolate.
  var helloWorldServerIsolate = await Isolate.spawn(HelloWorldServer.entrypoint, initData);

  // Spawn the client isolate. It will use its isolate's IsolateManagerClient to connect to the server isolate.
  var helloWorldClientIsolate = await Isolate.spawn(HelloWorldIsolateClient.entrypoint, initData);

  _log.i("Server and client isolates spawned");
}