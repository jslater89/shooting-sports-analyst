
import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';

final _log = SSALogger("ServerIsolateHelper");

typedef ServerCommandHandler<C, R> = Future<R> Function(C command);

/// A helper for server isolates that handles communication with client isolates,
/// including the IsolateManagerServer, and handles converting server isolate-specific
/// data types to and from the generic [IsolateMessage] types.
///
/// [C] is the client command data type for this server isolate.
/// [R] is the server response datatype for this server isolate.
///
/// To use:
/// 1. Spawn your server isolate, passing in a send port that sends to the init receive port.
/// 2. Create an instance of ServerIsolateHelper for your server isolate, and call [handleStartup]
/// with the send port from the init isolate.
/// 3. In the init isolate, call [IsolateManagerServer.register] with the send port from the server isolate.
/// 4. [commandHandler] will be called when a command is received from a client isolate.
/// 5. [commandHandler] should return a [ServerResponse] object.
/// 6. The [ServerResponse] object will be sent back to the client isolate that sent the command.
class ServerIsolateHelper<C, R> {
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
    if(message is! IsolateMessage) {
      throw Exception("Invalid message type: ${message.runtimeType}");
    }
    else if(message is IsolateRegistrationResponse) {
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

  /// Handle starting up the server isolate, sending the startup message to the init isolate.
  Future<void> handleStartup(SendPort managerSendPort) async {
    _clientSendPorts[IsolateManagerServer.id] = managerSendPort;
    _log.i("Server isolate $isolateId registering with manager isolate");
    managerSendPort.send(
      IsolateRegistrationRequest(
        sourceIsolateId: isolateId,
        destinationIsolateId: IsolateManagerServer.id,
        sendPort: _receivePort.sendPort,
      )
    );
    await _registeredCompleter.future;
  }
}
