/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

final _log = SSALogger("IsolateManager");


/// IsolateManagerServer is a special server isolate that forwards [IsolateConnectionRequest]s
/// to the appropriate server isolate and returns their [IsolateConnectionResponse]s.
class IsolateManagerServer {
  static const id = "isolate_manager";

  /// A map of isolate IDs to send ports used to send messages to those isolate IDs.
  final Map<String, SendPort> _sendPorts = {};
  final ReceivePort _receivePort = ReceivePort();

  static IsolateManagerServer? _instance;
  factory IsolateManagerServer() {
    if(_instance == null) {
      _instance = IsolateManagerServer._();
    }
    return _instance!;
  }
  IsolateManagerServer._() {
    _receivePort.listen(_listen);
  }

  void _listen(dynamic message) {
    _log.v("Manager isolate received message: ${message.runtimeType} ${message.sourceIsolateId} -> ${message.destinationIsolateId}");
    if(message is! IsolateMessage) {
      throw Exception("Invalid message type: ${message.runtimeType}");
    }
    else if(message is IsolateRegistrationRequest) {
      if(_sendPorts.containsKey(message.sourceIsolateId)) {
        throw Exception("Isolate ${message.sourceIsolateId} already registered");
      }

      // Save the client's send port.
      _sendPorts[message.sourceIsolateId] = message.sendPort;
      _sendPorts[message.sourceIsolateId]!.send(IsolateRegistrationResponse(
        sourceIsolateId: id,
        destinationIsolateId: message.sourceIsolateId,
        sendPort: _receivePort.sendPort,
      ));
    }
    else if(message is IsolateConnectionRequest) {
      if(!_sendPorts.containsKey(message.sourceIsolateId)) {
        throw Exception("Isolate ${message.sourceIsolateId} not registered");
      }
      // Forward the connection request to the server isolate.
      _sendPorts[message.destinationIsolateId]!.send(IsolateConnectionRequest(
        sourceIsolateId: message.sourceIsolateId,
        destinationIsolateId: message.destinationIsolateId,
        sendPort: _sendPorts[message.sourceIsolateId]!,
      ));
    }
    else if(message is IsolateConnectionResponse) {
      if(message.destinationIsolateId == id) {
        // If the response is for us, it's a response from a server isolate to the message sent in
        // register().
        _sendPorts[message.sourceIsolateId] = message.sendPort;
      }
      else if(_sendPorts.containsKey(message.destinationIsolateId)) {
        // Otherwise it's a response from a server isolate to a client isolate.
        _sendPorts[message.destinationIsolateId]!.send(message);
      }
      else {
        throw Exception("Isolate ${message.destinationIsolateId} not registered");
      }
    }
  }

  /// Register a server isolate with the IsolateManagerServer.
  ///
  /// [sendPort] is the port that the server isolate should use to send back to
  /// this isolate.
  Future<void> register(String isolateId, SendPort sendPort) async {
    _sendPorts[isolateId] = sendPort;
    sendPort.send(IsolateConnectionRequest(
      sourceIsolateId: id,
      destinationIsolateId: isolateId,
      sendPort: sendPort,
    ));
  }

  static Future<void> entrypoint(IsolateStartData startData) async {
    FlutterOrNative.debugModeProvider = ServerDebugProvider();
    SSALogger.setupSendPort(startData.logPort, isolateName: id);
    var managerIsolate = IsolateManagerServer();
    startData.initPort.send(IsolateConnectionResponse(
      sourceIsolateId: id,
      destinationIsolateId: "init",
      sendPort: managerIsolate._receivePort.sendPort,
    ));
    await Future.delayed(Duration(days: 10000));
  }
}
