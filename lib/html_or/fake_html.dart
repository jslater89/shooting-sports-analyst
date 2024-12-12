/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("NativeHtmlOr");

Controller _controller = Controller();
Controller get controller => _controller;

class Controller extends ControlInterface {
  @override
  void navigateTo(String namedRoute) {
    Navigator.of(HtmlOr.lastContext).pushNamed(namedRoute);
  }

  @override
  Map<String, String> getQueryParams() {
    return {};
  }

  @override
  void pickAndReadFile(Function(String? p1) onFileContents) async {
    var result = await FilePicker.platform.pickFiles();
    if(result != null) {
      var f = result.files[0];
      var nativeFile = File(f.path ?? "/error!");
      _log.d("File: ${nativeFile.path} ${await nativeFile.length()}");
      onFileContents(await nativeFile.readAsString());
    }
    else {
      onFileContents(null);
    }
  }

  @override
  Future<String?> pickAndReadFileNow() async {
    var result = await FilePicker.platform.pickFiles(initialDirectory: Directory.current.absolute.path + Platform.pathSeparator);
    if(result != null) {
      var f = result.files[0];
      var nativeFile = File(f.path ?? "/error!");
      _log.d("File: ${nativeFile.path} ${await nativeFile.length()}");
      return await nativeFile.readAsString();
    }
    else {
      return null;
    }
  }

  @override
  bool get needsProxy => false;

  String? lastDirectoryPath;

  @override
  Future<bool> saveFile(String defaultName, String fileContents) async {
    _log.d("Last directory? $lastDirectoryPath");
    try {
      var path = await FilePicker.platform.saveFile(fileName: defaultName, initialDirectory: lastDirectoryPath ?? Directory.current.absolute.path + Platform.pathSeparator);
      if(path != null) {
        var file = File(path);
        lastDirectoryPath = file.parent.absolute.path;
        await file.writeAsString(fileContents);
        return true;
      }
      else {
        return false;
      }
    }
    catch(e) {
      _log.e("Error saving file: $e");
      return false;
    }
  }

  @override
  Future<bool> saveBuffer(String defaultName, List<int> buffer) async {
    _log.d("Last directory? $lastDirectoryPath");
    try {
      var path = await FilePicker.platform.saveFile(fileName: defaultName, initialDirectory: lastDirectoryPath ?? Directory.current.absolute.path + Platform.pathSeparator);
      if(path != null) {
        var file = File(path);
        lastDirectoryPath = file.parent.absolute.path;
        await file.writeAsBytes(buffer);
        return true;
      }
      else {
        return false;
      }
    }
    catch(e) {
      _log.e("Error saving file: $e");
      return false;
    }
  }
}