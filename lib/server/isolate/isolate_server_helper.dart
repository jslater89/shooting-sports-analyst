/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';

final _log = SSALogger("ServerIsolateHelper");

typedef ServerCommandHandler<C, R> = Future<R> Function(C command);

/// A helper for server isolates that handles communication with client isolates
/// through the IsolateManagerServer. It manages registration with the manager,
/// handles connection requests from client isolates, and processes client commands.
///
/// [C] is the client command data type for this server isolate.
/// [R] is the server response data type for this server isolate.
///
/// Typical usage in a server isolate:
///
/// 1. Spawn the server isolate, passing [IsolateStartData] that includes the manager send port.
/// 2. Create an instance of ServerIsolateHelper with the isolate ID and a command handler function.
/// 3. Call [handleStartup] with the manager send port from [IsolateStartData.managerPort].
///    This sends an [IsolateRegistrationRequest] to the manager. Wait for [registered] to complete.
/// 4. In the init isolate, call [IsolateManagerServer.register] with the server isolate's ID
///    and send port to complete the registration process.
/// 5. When a client isolate connects via [IsolateManagerClient.connect], the manager forwards
///    an [IsolateConnectionRequest] to this server. The helper stores the client's send port
///    and responds with an [IsolateConnectionResponse] containing this server's receive port.
/// 6. When a client sends a command via [IsolateManagerClient.sendCommand], the helper receives
///    a [ClientCommand] and calls [commandHandler] with the command data. The handler should
///    return a value of type [R], which the helper wraps in a [ServerResponse] and sends back
///    to the client isolate.
class ServerIsolateHelper<C, R> {
  static bool verboseLogging = false;

  /// The isolate ID of this server isolate.
  final String isolateId;
  /// The send ports of the client isolates that are connected to this server isolate.
  final Map<String, SendPort> _clientSendPorts = {};
  /// The receive port of this server isolate.
  final ReceivePort _receivePort = ReceivePort();

  /// The handler for commands from client isolates.
  final ServerCommandHandler<C, R> commandHandler;

  final Completer<bool> _registeredCompleter = Completer();
  Future<bool> get registered => _registeredCompleter.future;

  ServerIsolateHelper({
    required this.isolateId,
    required this.commandHandler,
  }) {
    _receivePort.listen(_listen);
  }

  void _listen(dynamic message) async{
    if(message is! IsolateManagerMessage) {
      throw Exception("Invalid message type: ${message.runtimeType}");
    }

    if(verboseLogging) {
      _log.i("${message.runtimeType}: ${message.sourceIsolateId} -> ${message.destinationIsolateId}");
    }
    if(message is IsolateRegistrationResponse) {
      _log.i("Registered with manager isolate");
      // Servers only receive messages from the manager isolate, but
      // just in case that pattern changes...
      _clientSendPorts[IsolateManagerServer.id] = message.sendPort;
      _registeredCompleter.complete(true);
    }
    else if(message is IsolateConnectionRequest) {
      _log.i("Connected to client isolate ${message.sourceIsolateId}");
      _clientSendPorts[message.sourceIsolateId] = message.sendPort;
      _clientSendPorts[message.sourceIsolateId]!.send(
        IsolateConnectionResponse(
          id: message.id,
          sourceIsolateId: isolateId,
          destinationIsolateId: message.sourceIsolateId,
          sendPort: _receivePort.sendPort,
        )
      );
    }
    else if(message is ClientCommand<C>) {
      var response = await commandHandler(message.data);
      _clientSendPorts[message.sourceIsolateId]!.send(
        ServerResponse<R>(
          id: message.id,
          sourceIsolateId: isolateId,
          destinationIsolateId: message.sourceIsolateId,
          data: response,
        )
      );
    }
    else if(message is ClientCommand) {
      _log.w("Received incorrect client command type: ${message.runtimeType}");
      _log.i("IsolateMessage: ${message.sourceIsolateId} -> ${message.destinationIsolateId}");
      _clientSendPorts[message.sourceIsolateId]!.send(null);
    }
    else {
      _log.w("Received unexpected message from client isolate: ${message.runtimeType}");
      _log.i("IsolateMessage: ${message.sourceIsolateId} -> ${message.destinationIsolateId}");
      _clientSendPorts[message.sourceIsolateId]!.send(null);
    }
  }

  /// Handle starting up the server isolate by registering with the IsolateManagerServer.
  ///
  /// Sends an [IsolateRegistrationRequest] to the manager isolate and waits for
  /// an [IsolateRegistrationResponse] to confirm registration.
  ///
  /// [managerSendPort] is a send port that sends to the IsolateManagerServer's receive port.
  Future<void> handleStartup({required IsolateStartData startData}) async {
    _clientSendPorts[IsolateManagerServer.id] = startData.managerPort!;
    _log.i("Server isolate $isolateId registering with manager isolate");
    startData.managerPort!.send(
      IsolateRegistrationRequest(
        sourceIsolateId: isolateId,
        destinationIsolateId: IsolateManagerServer.id,
        sendPort: _receivePort.sendPort,
      )
    );
    await _registeredCompleter.future;

    startData.initPort.send(StartupCompleteResponse(sourceIsolateId: isolateId));
  }
}
