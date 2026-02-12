/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/server/isolate/isolate_common.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_server_helper.dart';

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
    IsolateCommon.setup(startData);
    var serverIsolate = HelloWorldServer();
    serverIsolate.helper.handleStartup(startData: startData);
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