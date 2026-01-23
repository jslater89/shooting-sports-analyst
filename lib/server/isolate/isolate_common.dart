import 'dart:isolate';

import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/server/isolate/isolate_messages.dart';
import 'package:shooting_sports_analyst/server/providers.dart';

class IsolateCommon {
  static String isolateId = "unset";
  static SendPort? managerSendPort;

  static void setup(IsolateStartData startData) {
    FlutterOrNative.debugModeProvider = ServerDebugProvider();
    SSALogger.setupSendPort(startData.logPort, isolateName: startData.isolateId);
    managerSendPort = startData.managerPort;
    isolateId = startData.isolateId;
  }
}