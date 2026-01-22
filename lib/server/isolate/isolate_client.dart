import 'dart:async';
import 'dart:isolate';

import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_manager.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';

final _log = SSALogger("IsolateManagerClient");

/// IsolateManagerClient is a convenience function for inter-isolate communication
/// along server isolate/client isolate patterns. It provides a single point of
/// entry for client isolates (e.g. webserver isolates) to register with server
/// isolates (e.g. the isolate match cache), exchanging send/receive ports to
/// establish communications without the main isolate having to pass in ports
/// for every single server isolate.
///
/// Server isolates managed by the IsolateManager should handle messages of type
/// [IsolateConnectionRequest] and respond with messages of type [IsolateConnectionResponse].
///
/// IsolateManager should generally be used to implement type-safe client isolate
/// classes that communicate with their respective server isolates. The process
/// goes like this:
///
/// 1. ClientIsolate gets the IsolateManager in its internal code.
/// 2. ClientIsolate uses [IsolateManagerClient.ready] to verify that the manager
/// is ready to accept commands.
/// 3. ClientIsolate uses [IsolateManagerClient.connect] to connect to the server isolate
/// or isolate(s).
/// 4. ClientIsolate uses [IsolateManagerClient.sendCommand] to send commands to the server
/// isolate(s), and receives ServerResponse objects containing any desired data.
///
/// Server isolates
class IsolateManagerClient {
  /// The isolate ID of the current isolate.
  final String thisIsolateId;
  /// The send port to the manager isolate.
  final SendPort _managerSendPort;
  /// The receive port from all isolates.
  late final ReceivePort _serverReceivePort;

  /// A map of isolate IDs to send ports used to send messages to those isolate IDs.
  final Map<String, SendPort> _serverSendPorts = {};

  Future<bool> get ready => _readyCompleter.future;
  Completer<bool> _readyCompleter = Completer();
  bool _registered = false;
  bool get _commandInProgress => _commandCompleter != null;
  Completer<ServerResponse?>? _commandCompleter;

  static IsolateManagerClient? _instance;
  factory IsolateManagerClient(String isolateId, SendPort managerSendPort) {
    if(_instance == null) {
      _instance = IsolateManagerClient._(isolateId, managerSendPort);
    }
    return _instance!;
  }

  IsolateManagerClient._(this.thisIsolateId, this._managerSendPort) {
    _serverReceivePort = ReceivePort();
    _serverReceivePort.listen(_listen);
    _registerWithServer();
  }

  Future<ServerResponse?> _registerWithServer() async {
    if(_commandInProgress) {
      throw Exception("A command is already in progress");
    }
    _log.i("Client isolate $thisIsolateId registering with isolate manager server");
    _commandCompleter = Completer();
    _managerSendPort.send(IsolateRegistrationRequest(
      sourceIsolateId: thisIsolateId,
      destinationIsolateId: IsolateManagerServer.id,
      sendPort: _serverReceivePort.sendPort)
    );
    var response = await _commandCompleter!.future;
    _readyCompleter.complete(true);
    return response;
  }

  /// Handle messages from IsolateManagerServer, which will
  /// always be of type [IsolateConnectionResponse] or [IsolateRegistrationResponse].
  Future<void> _listen(dynamic message) async {
    if(message is! IsolateMessage) {
      throw Exception("Invalid message type: ${message.runtimeType}");
    }
    if(message is IsolateRegistrationResponse) {
      _registered = true;
      _log.i("Client isolate $thisIsolateId registered with manager isolate");
      _commandCompleter!.complete(null);
    }
    else if(message is IsolateConnectionResponse) {
      _serverSendPorts[message.sourceIsolateId] = message.sendPort;
      _log.i("Connected to server isolate ${message.sourceIsolateId}");
      _commandCompleter!.complete(null);
    }
    else if(message is ServerResponse) {
      _commandCompleter!.complete(message);
    }
    else {
      _log.w("Received unexpected message from server isolate: ${message.runtimeType}");
      _commandCompleter!.complete();
    }

    _commandCompleter = null;
  }

  /// Connect to a server isolate.
  ///
  /// [isolateId] specifies the isolate to connect to.
  ///
  /// The returned [SendPort] can be used to send messages to the server isolate.
  Future<SendPort> connect({
    required String isolateId,
  }) async {
    if(!_registered) {
      throw Exception("Isolate not registered with IsolateManagerServer");
    }
    if(_commandInProgress) {
      throw Exception("A command is already in progress");
    }
    if(_serverSendPorts.containsKey(isolateId)) {
      _log.i("Reusing existing connection to server isolate $isolateId");
      return _serverSendPorts[isolateId]!;
    }
    _log.i("Client isolate $thisIsolateId connecting to server isolate $isolateId");
    _commandCompleter = Completer();
    _managerSendPort.send(IsolateConnectionRequest(
      sourceIsolateId: thisIsolateId,
      destinationIsolateId: isolateId,
      sendPort: _serverReceivePort.sendPort)
    );
    await _commandCompleter!.future;
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
    if(_commandInProgress) {
      throw Exception("A command is already in progress");
    }
    if(!_serverSendPorts.containsKey(isolateId)) {
      throw Exception("Server isolate $isolateId not found");
    }

    _commandCompleter = Completer();
    _serverSendPorts[isolateId]!.send(ClientCommand(
      sourceIsolateId: thisIsolateId,
      destinationIsolateId: isolateId,
      data: command)
    );
    var response = await _commandCompleter!.future;
    if(response == null) {
      throw Exception("No response from server isolate $isolateId");
    }
    return response as ServerResponse<R>;
  }
}
