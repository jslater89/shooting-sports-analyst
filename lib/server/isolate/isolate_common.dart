import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_client.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("IsolateCommon");

class IsolateCommon {
  static String isolateId = "unset";
  static SendPort? managerSendPort;
  static IsolateManagerClient? managerClient;

  static void setup(IsolateStartData startData, {bool existingIsolate = false}) {
    if(!existingIsolate) {
      FlutterOrNative.debugModeProvider = ServerDebugProvider();
      SSALogger.setupSendPort(startData.logPort, isolateName: startData.isolateId);
    }
    managerSendPort = startData.managerPort;
    isolateId = startData.isolateId;
  }

  static Future<IsolateManagerClient> setupClient(IsolateStartData startData, {bool existingIsolate = false}) async {
    setup(startData, existingIsolate: existingIsolate);
    managerClient = IsolateManagerClient(isolateId, managerSendPort!);
    await managerClient!.ready;
    return managerClient!;
  }

  static Future<SendPort> startManagerIsolate({
    required SendPort loggerSendPort,
    required ReceivePort initIsolateReceivePort,
  }) async {
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
      IsolateStartData(
        isolateId: IsolateManagerServer.id,
        logPort: loggerSendPort,
        initPort: initIsolateReceivePort.sendPort,
        managerPort: null,
      ),
    );
    _log.i("Manager isolate spawned");
    var managerIsolateSendPort = await managerIsolateSendPortCompleter.future;
    _log.i("Manager isolate send port received");

    initIsolateReceivePort.close();
    return managerIsolateSendPort;

  }
}