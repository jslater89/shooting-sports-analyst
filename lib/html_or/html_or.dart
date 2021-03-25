import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'fake_html.dart' if(dart.library.html) 'real_html.dart';

const redirectRoot = kDebugMode ? "/" : "/uspsa-result-viewer/";

abstract class ControlInterface {
  void navigateTo(String namedRoute);
  Map<String, String> getQueryParams();
  void pickAndReadFile(Function(String?) onFileContents);
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

  static Map<String, String> getQueryParams() {
    return controller.getQueryParams();
  }

  static void openLink(String url) {
    launch(url);
  }

  static bool get needsProxy => controller.needsProxy;
}