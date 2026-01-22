
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_server_helper.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

class HelloWorldServer {
  static const id = "hello_server";
  late final ServerIsolateHelper<HelloWorldServerCommand, HelloWorldServerResponse> helper;

  HelloWorldServer() {
    helper = ServerIsolateHelper<HelloWorldServerCommand, HelloWorldServerResponse>(isolateId: id, commandHandler: commandHandler);
  }

  Future<HelloWorldServerResponse> commandHandler(HelloWorldServerCommand command) async {
    return HelloWorldServerResponse(data: "Hello, world!");
  }

  static Future<void> entrypoint(IsolateStartData startData) async {
    FlutterOrNative.debugModeProvider = ServerDebugProvider();
    SSALogger.setupSendPort(startData.logPort, isolateName: id);
    var serverIsolate = HelloWorldServer();
    serverIsolate.helper.handleStartup(startData.managerPort!);
    await Future.delayed(Duration(days: 10000));
  }
}

class HelloWorldServerCommand {
  HelloWorldServerCommand();
}

class HelloWorldServerResponse {
  final String data;
  HelloWorldServerResponse({required this.data});
}