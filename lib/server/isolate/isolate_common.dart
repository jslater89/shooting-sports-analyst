/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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

  static const verboseLogging = false;

  static void setup(IsolateStartData startData, {bool mainIsolate = false}) {
    if(!mainIsolate) {
      FlutterOrNative.debugModeProvider = ServerDebugProvider();
      FlutterOrNative.isolateModeProvider = ServerDebugProvider();
      SSALogger.setupSendPort(startData.logPort, isolateName: startData.isolateId);
    }
    managerSendPort = startData.managerPort;
    isolateId = startData.isolateId;
  }

  /// Set up the [IsolateManagerClient] for the current isolate.
  ///
  /// [startData] is the [IsolateStartData] for the current isolate.
  /// [mainIsolate] is whether the current isolate is the main isolate. If mainIsolate is false,
  /// the setup process will redirect logging to the main isolate via the [SendPort] in [startData.logPort].
  /// [failOnDuplicateRegistration] is whether to fail if the isolate is already registered with the manager isolate.
  /// This should generally be true, except in cases where an isolate will register as both a server and a client.
  /// In the latter case, it should register as a server first.
  ///
  /// Returns the [IsolateManagerClient] for the current isolate.
  static Future<IsolateManagerClient> setupClient(IsolateStartData startData, {
    bool mainIsolate = false,
    bool failOnDuplicateRegistration = true,
  }) async {
    setup(startData, mainIsolate: mainIsolate);
    if(managerClient == null) {
      managerClient = IsolateManagerClient(isolateId, managerSendPort!, failOnDuplicateRegistration: failOnDuplicateRegistration);
    }
    await managerClient!.ready;
    return managerClient!;
  }

  /// Start the manager isolate and return the send port to the calling isolate. Call from the main isolate.
  ///
  /// [loggerSendPort] is the send port to the main isolate for logging.
  /// [initIsolateReceivePort] is the receive port to listen for messages from the manager isolate.
  ///
  /// Returns the send port to the manager isolate.
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
        if(message is IsolateManagerMessage) {
          _log.e("IsolateMessage: ${message.sourceIsolateId} -> ${message.destinationIsolateId}");
        }
        return;
      }
    };
    _log.i("Init isolate receive port listener set up");
    initIsolateReceivePort.listen(initReceivePortHandler);

    // ignore: unused_local_variable
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