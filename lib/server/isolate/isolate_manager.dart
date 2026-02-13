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


/// IsolateManagerServer is a central registry isolate that manages communication between
/// client and server isolates. It maintains a registry of all registered isolates (both
/// clients and servers) and their send ports.
///
/// When a client isolate wants to connect to a server isolate:
/// 1. The client sends an [IsolateConnectionRequest] to the manager, containing a send port that sends to the client's receive port.
/// 2. The manager forwards the request to the target server isolate.
/// 3. The server isolate responds with an [IsolateConnectionResponse] containing a send port that sends to the server's receive port.
/// 4. The manager forwards the response back to the client isolate.
///
/// After this exchange, the client and server isolates can communicate directly without
/// going through the manager. The manager only facilitates the initial connection setup.
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
    if(message is! IsolateManagerMessage) {
      throw Exception("Invalid message type: ${message.runtimeType}");
    }
    else if(message is IsolateRegistrationRequest) {
      if(_sendPorts.containsKey(message.sourceIsolateId)) {
        if(message.failOnDuplicateRegistration) {
          throw Exception("Isolate ${message.sourceIsolateId} already registered");
        }
        else {
          _log.w("Isolate ${message.sourceIsolateId} already registered, skipping registration");
          // Send a response to the client so that it receives registration info and doesn't
          // wait forever for the command to complete.
          message.sendPort.send(IsolateRegistrationResponse(
            id: message.id,
            sourceIsolateId: id,
            destinationIsolateId: message.sourceIsolateId,
            sendPort: _receivePort.sendPort,
          ));
          return;
        }
      }

      // Save the client's send port.
      _sendPorts[message.sourceIsolateId] = message.sendPort;
      _sendPorts[message.sourceIsolateId]!.send(IsolateRegistrationResponse(
        id: message.id,
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
      _sendPorts[message.destinationIsolateId]!.send(IsolateConnectionRequest.forwarded(
        id: message.id,
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

  static Future<void> entrypoint(IsolateStartData startData) async {
    FlutterOrNative.debugModeProvider = ServerDebugProvider();
    SSALogger.setupSendPort(startData.logPort, isolateName: id);
    var managerIsolate = IsolateManagerServer();
    startData.initPort.send(IsolateConnectionResponse(
      id: 0,
      sourceIsolateId: id,
      destinationIsolateId: "init",
      sendPort: managerIsolate._receivePort.sendPort,
    ));
    await Future.delayed(Duration(days: 10000));
  }
}
