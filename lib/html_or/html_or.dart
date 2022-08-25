import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'fake_html.dart' if(dart.library.html) 'real_html.dart';

const redirectRoot = kDebugMode ? "/" : "/uspsa-result-viewer/";

abstract class ControlInterface {
  void navigateTo(String namedRoute);
  Map<String, String> getQueryParams();
  void saveFile(String defaultName, String fileContents);
  void pickAndReadFile(Function(String?) onFileContents);
  Future<String?> pickAndReadFileNow();
  bool get needsProxy;
}

class HtmlOr {
  static late BuildContext lastContext;

  static void navigateTo(BuildContext context, String path) {
    lastContext = context;
    controller.navigateTo(path);
  }

  static void pickAndReadFile(BuildContext context, Function(String?) onFileContents) async {
    lastContext = context;
    controller.pickAndReadFile(onFileContents);
  }

  static Future<String?> pickAndReadFileNow() async {
    return controller.pickAndReadFileNow();
  }

  static Future<void> saveFile(String defaultName, String fileContents) async {
    return controller.saveFile(defaultName, fileContents);
  }

  static Map<String, String> getQueryParams() {
    return controller.getQueryParams();
  }

  static void openLink(String url) {
    launch(url);
  }

  static bool get needsProxy => controller.needsProxy;

  static bool get isWeb => needsProxy;
  static bool get isDesktop => !needsProxy;
}