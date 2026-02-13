/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';

final _log = SSALogger("IsolateManagerClient");

/// IsolateManagerClient is a singleton helper class for client isolates to communicate
/// with server isolates through the IsolateManagerServer. It provides a single point of
/// entry for client isolates (e.g. webserver isolates) to connect to server isolates
/// (e.g. the isolate match cache), exchanging send/receive ports to establish direct
/// communication without the main isolate having to pass in ports for every server isolate.
///
/// The client automatically registers with the IsolateManagerServer upon construction.
/// Server isolates should use [ServerIsolateHelper] to handle connection requests and
/// commands from client isolates.
///
/// Typical usage in a client isolate:
///
/// 1. Create an instance of IsolateManagerClient with the isolate ID and manager send port.
/// 2. Wait for [ready] to complete to ensure registration with the manager is finished.
/// 3. Call [connect] with a server isolate ID to establish a connection. The manager
///    will forward the connection request to the server isolate, which responds with
///    its receive port. The client stores this port for direct communication.
/// 4. Use [sendCommand] to send commands directly to the server isolate using the
///    stored send port. The server isolate processes the command and returns a
///    [ServerResponse] containing the result.
///
/// [C] is the command type.
/// [R] is the response type.
class IsolateManagerClient {
  /// The isolate ID of the current isolate.
  final String thisIsolateId;
  /// The send port to the manager isolate.
  final SendPort _managerSendPort;
  /// The receive port from all isolates.
  late final ReceivePort _serverReceivePort;
  /// Whether to fail if the isolate is already registered with the manager isolate.
  final bool failOnDuplicateRegistration;

  /// A map of isolate IDs to send ports used to send messages to those isolate IDs.
  final Map<String, SendPort> _serverSendPorts = {};

  Future<bool> get ready => _readyCompleter.future;
  Completer<bool> _readyCompleter = Completer();
  bool _registered = false;

  Map<int, Completer<ServerResponse?>> _commandCompleters = {};

  static IsolateManagerClient? _instance;
  static IsolateManagerClient? get instance => _instance;
  factory IsolateManagerClient(String isolateId, SendPort managerSendPort, {bool failOnDuplicateRegistration = true}) {
    if(_instance == null) {
      _instance = IsolateManagerClient._(isolateId, managerSendPort, failOnDuplicateRegistration: failOnDuplicateRegistration);
      IsolateMessage.seedRandom(isolateId.hashCode);
    }
    return _instance!;
  }

  IsolateManagerClient._(this.thisIsolateId, this._managerSendPort, {this.failOnDuplicateRegistration = true}) {
    _serverReceivePort = ReceivePort();
    _serverReceivePort.listen(_listen);
    _registerWithServer();
  }

  Future<ServerResponse?> _registerWithServer() async {
    _log.i("Client isolate $thisIsolateId registering with isolate manager server");
    var request = IsolateRegistrationRequest(
      sourceIsolateId: thisIsolateId,
      destinationIsolateId: IsolateManagerServer.id,
      sendPort: _serverReceivePort.sendPort,
      failOnDuplicateRegistration: failOnDuplicateRegistration,
    );
    _commandCompleters[request.id] = Completer();
    _managerSendPort.send(request);
    var response = await _commandCompleters[request.id]!.future;
    _commandCompleters.remove(request.id);
    _readyCompleter.complete(true);
    return response;
  }

  /// Manually handle a message received for this isolate. This is useful for handling
  /// messages when a given isolate is both a server and a client: IsolateServerHelper
  /// will forward messages to this method if the isolate has an IsolateManagerClient instance.
  void handleMessage(IsolateManagerMessage message) {
    _listen(message);
  }

  /// Handle messages received on the client's receive port.
  ///
  /// Processes messages from both the IsolateManagerServer (registration and connection
  /// responses) and from server isolates (command responses). Messages are:
  /// - [IsolateRegistrationResponse]: Confirms registration with the manager
  /// - [IsolateConnectionResponse]: Contains the server isolate's receive port after connection
  /// - [ServerResponse]: Contains the result of a command sent to a server isolate
  Future<void> _listen(dynamic message) async {
    if(IsolateCommon.verboseLogging) {
      _log.v("${message.sourceIsolateId} -> $thisIsolateId: ${message.runtimeType} (${message.id})");
    }
    if(message is! IsolateManagerMessage) {
      throw Exception("Invalid message type: ${message.runtimeType}");
    }
    if(message is IsolateRegistrationResponse) {
      _registered = true;
      _log.i("Client isolate $thisIsolateId registered with manager isolate");
      _commandCompleters[message.id]!.complete(null);
    }
    else if(message is IsolateConnectionResponse) {
      _serverSendPorts[message.sourceIsolateId] = message.sendPort;
      _log.i("Connected to server isolate ${message.sourceIsolateId}");
      _commandCompleters[message.id]!.complete(null);
    }
    else if(message is ServerResponse) {
      _commandCompleters[message.id]!.complete(message);
    }
    else {
      _log.w("Received unexpected message from server isolate: ${message.runtimeType}");
      _commandCompleters[message.id]!.complete(null);
    }
    _commandCompleters.remove(message.id);
  }

  /// Connect to a server isolate.
  ///
  /// Sends an [IsolateConnectionRequest] to the IsolateManagerServer, which forwards
  /// it to the target server isolate. The server isolate responds with an
  /// [IsolateConnectionResponse] containing its receive port, which is stored for
  /// future direct communication. If a connection to this server isolate already
  /// exists, the cached send port is returned immediately.
  ///
  /// [isolateId] specifies the server isolate to connect to.
  ///
  /// Returns a [SendPort] that can be used to send messages directly to the server
  /// isolate's receive port.
  Future<SendPort> connect({
    required String isolateId,
  }) async {
    if(!_registered) {
      throw Exception("Isolate not registered with IsolateManagerServer");
    }
    if(_serverSendPorts.containsKey(isolateId)) {
      _log.i("Reusing existing connection to server isolate $isolateId");
      return _serverSendPorts[isolateId]!;
    }
    _log.i("Client isolate $thisIsolateId connecting to server isolate $isolateId");
    var request = IsolateConnectionRequest(
      sourceIsolateId: thisIsolateId,
      destinationIsolateId: isolateId,
      sendPort: _serverReceivePort.sendPort,
    );
    _commandCompleters[request.id] = Completer();
    _managerSendPort.send(request);
    await _commandCompleters[request.id]!.future;
    _commandCompleters.remove(request.id);
    return _serverSendPorts[isolateId]!;
  }

  /// Send a command to a server isolate.
  ///
  /// [isolateId] specifies the isolate to send the command to.
  /// [command] is the command to send.
  ///
  /// The returned [ServerResponse] contains the response from the server isolate. Each server
  /// isolate will define client command types [C] and server response types [R].
  Future<ServerResponse<R>?> sendCommand<C, R>({
    required String isolateId,
    required C command,
  }) async {
    if(!_registered) {
      throw Exception("Isolate not registered with IsolateManagerServer");
    }
    if(!_serverSendPorts.containsKey(isolateId)) {
      throw Exception("Server isolate $isolateId not found");
    }

    var request = ClientCommand(
      sourceIsolateId: thisIsolateId,
      destinationIsolateId: isolateId,
      data: command,
    );
    if(IsolateCommon.verboseLogging) {
      _log.v("$thisIsolateId -> $isolateId: ClientCommand<${command.runtimeType}> (${request.id})");
    }
    _commandCompleters[request.id] = Completer();
    _serverSendPorts[isolateId]!.send(request);
    var response = await _commandCompleters[request.id]!.future;
    _commandCompleters.remove(request.id);
    if(response == null) {
      throw Exception("No response from server isolate $isolateId");
    }
    try {
      var typedResponse = response as ServerResponse<R>;
      if(IsolateCommon.verboseLogging) {
        _log.v("completed command ${request.id}: ${typedResponse.data.runtimeType} (${typedResponse.id})");
      }
      return typedResponse;
    }
    catch(e) {
      _log.e("Error casting response: $e");
      return null;
    }
  }
}
