/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:isolate';
import 'dart:math';


abstract interface class IsolateMessage {
  int get id;

  static var _messageIdGenerator = Random();
  static void seedRandom(int seed) {
    _messageIdGenerator = Random(seed);
  }

  static int generateId() => (_messageIdGenerator.nextInt(1<<32) << 32) | _messageIdGenerator.nextInt(1<<32);
}

sealed class IsolateManagerMessage implements IsolateMessage {
  String get sourceIsolateId;
  String get destinationIsolateId;
}

sealed class ClientRequest extends IsolateManagerMessage{}
sealed class ClientResponse extends IsolateManagerMessage{}

/// A message from an isolate to the init isolate, indicating that the new isolate
/// has completed its startup process.
class StartupCompleteResponse extends ClientResponse {
  @override
  int get id => 0;

  /// The isolate ID of the source isolate of this message.
  final String sourceIsolateId;
  final String destinationIsolateId = "init";

  StartupCompleteResponse({required this.sourceIsolateId});
}

/// A request to register an isolate with the IsolateManagerServer, either a server or client.
///
/// [sourceIsolateId] is the isolate's ID.
/// [sendPort] is the port that connects to the isolate's receive port.
class IsolateRegistrationRequest extends ClientRequest {
  @override
  final int id;

  /// The isolate ID of the source isolate of this message.
  final String sourceIsolateId;
  /// The isolate ID of the destination isolate of this message.
  /// This should always be the manager isolate's ID.
  final String destinationIsolateId;
  /// The send port that connects to the isolate's receive port.
  final SendPort sendPort;
  /// Whether to fail if the isolate is already registered.
  final bool failOnDuplicateRegistration;

  IsolateRegistrationRequest({
    required this.sourceIsolateId,
    required this.destinationIsolateId,
    required this.sendPort,
    this.failOnDuplicateRegistration = true,
  }) : id = IsolateMessage.generateId();
}

/// A response to a [IsolateRegistrationRequest].
///
/// As isolates registering must receive the server's send port on registration, this
/// response is just a confirmation.
class IsolateRegistrationResponse extends ClientResponse {
  @override
  final int id;

  /// The isolate ID of the registered client.
  final String sourceIsolateId;
  /// The isolate ID of the destination isolate.
  final String destinationIsolateId;
  /// The send port that connects to the manager isolate's receive port.
  final SendPort sendPort;

  IsolateRegistrationResponse({required this.id, required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort});
}

/// A request to connect to a server isolate.
///
/// [sourceIsolateId] specifies the isolate to connect to.
/// [sendPort] is the port used by the server isolate to send messages to the client isolate.
class IsolateConnectionRequest extends ClientRequest {
  @override
  final int id;

  final String sourceIsolateId;
  final String destinationIsolateId;
  final SendPort sendPort;

  IsolateConnectionRequest({required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort}) : id = IsolateMessage.generateId();
  IsolateConnectionRequest.forwarded({
    required this.id,
    required this.sourceIsolateId,
    required this.destinationIsolateId,
    required this.sendPort,
  });
}

/// A response to a [IsolateConnectionRequest].
///
/// [sendPort] is the port used by the client isolate to send messages to the server isolate.
class IsolateConnectionResponse extends ClientResponse {
  @override
  final int id;

  final String sourceIsolateId;
  final String destinationIsolateId;
  final SendPort sendPort;

  IsolateConnectionResponse({required this.id, required this.sourceIsolateId, required this.destinationIsolateId, required this.sendPort});
}

/// A request to subscribe to broadcast messages from a server isolate.
///
/// The client must be connected to the server isolate already to subscribe to broadcast messages.
///
/// [sourceIsolateId] specifies the isolate to subscribe to.
/// [destinationIsolateId] specifies the isolate to subscribe to.
/// [status] specifies the desired subscription status—[subscribed] to receive broadcast messages, or [unsubscribed] to stop receiving broadcast messages.
///
/// [T] is the expected type of the broadcast message. Servers should reject requests
/// with unexpected types.
class IsolateBroadcastSubscribeRequest<T> extends ClientRequest {
  @override
  final int id;
  final String sourceIsolateId;
  final String destinationIsolateId;
  final IsolateBroadcastSubscriptionStatus status;

  IsolateBroadcastSubscribeRequest({
    required this.sourceIsolateId,
    required this.destinationIsolateId,
    this.status = IsolateBroadcastSubscriptionStatus.subscribed,
  }) : id = IsolateMessage.generateId();
}

enum IsolateBroadcastSubscriptionStatus {
  subscribed,
  unsubscribed,
}

/// A response to a [IsolateBroadcastSubscribeRequest].
///
/// [sourceIsolateId] specifies the isolate that is subscribed to broadcast messages.
/// [destinationIsolateId] specifies the isolate that is subscribed to broadcast messages.
/// [status] specifies the actual subscription status after the request was processed.
class IsolateBroadcastSubscribeResponse extends ClientResponse {
  @override
  final int id;
  final String sourceIsolateId;
  final String destinationIsolateId;
  final IsolateBroadcastSubscriptionStatus status;

  IsolateBroadcastSubscribeResponse({
    required this.id,
    required this.sourceIsolateId,
    required this.destinationIsolateId,
    required this.status,
  });
}

/// A command from a client isolate to a server isolate.
///
/// [sourceIsolateId] is the ID of the client isolate that sent the command.
/// [data] is the data of the command.
class ClientCommand<T> extends ClientRequest {
  @override
  final int id;

  final String sourceIsolateId;
  final String destinationIsolateId;
  final T data;

  ClientCommand({required this.sourceIsolateId, required this.destinationIsolateId, required this.data}) : id = IsolateMessage.generateId();
}

/// A response from a server isolate to a client isolate.
///
/// [sourceIsolateId] is the ID of the server isolate that sent the response.
/// [data] is the data of the response.
class ServerResponse<T> extends ClientResponse {
  @override
  final int id;

  final String sourceIsolateId;
  final String destinationIsolateId;
  final T data;

  ServerResponse({required this.id, required this.sourceIsolateId, required this.destinationIsolateId, required this.data});
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

/// A broadcast message from a server isolate to a client isolate.
///
/// [T] is the type of the broadcast message.
/// [sourceIsolateId] is the ID of the server isolate that sent the broadcast.
/// [data] is the data of the broadcast.
class ServerBroadcast<T> extends ServerResponse<T> {
  ServerBroadcast({required super.sourceIsolateId, required super.data}) : super(id: 0, destinationIsolateId: "broadcast");
}