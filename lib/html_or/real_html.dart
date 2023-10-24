/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';

Controller _controller = Controller();
Controller get controller => _controller;

class Controller extends ControlInterface {
  @override
  void navigateTo(String namedRoute) {
    window.location.href = "$redirectRoot#$namedRoute";
  }

  @override
  Map<String, String> getQueryParams() {
    return Uri.parse(window.location.href).queryParameters;
  }

  @override
  void pickAndReadFile(Function(String? p1) onFileContents) async {
    var result = await FilePicker.platform.pickFiles();
    if(result != null) {
      var f = result.files[0];
      onFileContents(Utf8Decoder().convert(f.bytes?.toList() ?? []));
    }
    else {
    onFileContents(null);
    }
  }

  @override
  Future<String?> pickAndReadFileNow() async {
    var result = await FilePicker.platform.pickFiles();
    if(result != null) {
      var f = result.files[0];
      return Utf8Decoder().convert(f.bytes?.toList() ?? []);
    }
    else {
      return null;
    }
  }

  @override
  bool get needsProxy => true;

  @override
  void saveFile(String defaultName, String fileContents) {
    launch("data:application/octet-stream;base64,${base64Encode(utf8.encode(fileContents))}");
  }
}