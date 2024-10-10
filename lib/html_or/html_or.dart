/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'fake_html.dart' if(dart.library.html) 'real_html.dart';

const redirectRoot = kDebugMode ? "/" : "/uspsa-result-viewer/";

abstract class ControlInterface {
  void navigateTo(String namedRoute);
  Map<String, String> getQueryParams();
  Future<bool> saveFile(String defaultName, String fileContents);
  Future<bool> saveBuffer(String defaultName, List<int> buffer);
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

  static Future<bool> saveFile(String defaultName, String fileContents) async {
    return controller.saveFile(defaultName, fileContents);
  }

  static Future<bool> saveBuffer(String defaultName, List<int> buffer) async {
    return controller.saveBuffer(defaultName, buffer);
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