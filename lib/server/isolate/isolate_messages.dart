
import 'dart:isolate';

sealed class IsolateMessage{
  String get sourceIsolateId;
  String get destinationIsolateId;
}

sealed class ClientRequest extends IsolateMessage{}
sealed class ClientResponse extends IsolateMessage{}

/// A request to register an isolate with the IsolateManagerServer, either a server or client.
///
/// [sourceIsolateId] is the isolate's ID.
/// [sendPort] is the port that connects to the isolate's receive port.
class IsolateRegistrationRequest extends ClientRequest {
  /// The isolate ID of the source isolate of this message.
  final String sourceIsolateId;
  /// The isolate ID of the destination isolate of this message.
  /// This should always be the manager isolate's ID.
  final String destinationIsolateId;
  /// The send port that connects to the isolate's receive port.
  final SendPort sendPort;

  IsolateRegistrationRequest({required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort});
}

/// A response to a [IsolateRegistrationRequest].
///
/// As isolates registering must receive the server's send port on registration, this
/// response is just a confirmation.
class IsolateRegistrationResponse extends ClientResponse {
  /// The isolate ID of the registered client.
  final String sourceIsolateId;
  /// The isolate ID of the destination isolate.
  final String destinationIsolateId;
  /// The send port that connects to the manager isolate's receive port.
  final SendPort sendPort;

  IsolateRegistrationResponse({required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort});
}

/// A request to connect to a server isolate.
///
/// [sourceIsolateId] specifies the isolate to connect to.
/// [sendPort] is the port used by the server isolate to send messages to the client isolate.
class IsolateConnectionRequest extends ClientRequest {
  final String sourceIsolateId;
  final String destinationIsolateId;
  final SendPort sendPort;

  IsolateConnectionRequest({required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort});
}

/// A response to a [IsolateConnectionRequest].
///
/// [sendPort] is the port used by the client isolate to send messages to the server isolate.
class IsolateConnectionResponse extends ClientResponse {
  final String sourceIsolateId;
  final String destinationIsolateId;
  final SendPort sendPort;

  IsolateConnectionResponse({required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort});
}

/// A command from a client isolate to a server isolate.
///
/// [sourceIsolateId] is the ID of the client isolate that sent the command.
/// [data] is the data of the command.
class ClientCommand<T> extends ClientRequest {
  final String sourceIsolateId;
  final String destinationIsolateId;
  final T data;

  ClientCommand({required this.sourceIsolateId, required this.destinationIsolateId, required this.data});
}

/// A response from a server isolate to a client isolate.
///
/// [sourceIsolateId] is the ID of the server isolate that sent the response.
/// [data] is the data of the response.
class ServerResponse<T> extends ClientResponse {
  final String sourceIsolateId;
  final String destinationIsolateId;
  final T data;

  ServerResponse({required this.sourceIsolateId, required this.destinationIsolateId, required this.data});
}

/// A convenience container for passing initial data to a managed isolate.
class IsolateStartData {
  /// The isolate ID of the isolate.
  final String isolateId;
  /// The send port to the logger isolate, for use in [SSALogger.setupSendPort].
  final SendPort logPort;
  /// The send port to the init isolate, for use in [ServerIsolateHelper.handleStartup].
  final SendPort initPort;
  /// The send port to the manager isolate, for use in [IsolateManagerServer.register].
  ///
  /// Not needed when starting the manager isolate, but required for all other isolates.
  final SendPort? managerPort;

  IsolateStartData({required this.isolateId, required this.logPort, required this.initPort, this.managerPort});

  IsolateStartData copyWithId(String newIsolateId) {
    return IsolateStartData(isolateId: newIsolateId, logPort: logPort, initPort: initPort, managerPort: managerPort);
  }
}