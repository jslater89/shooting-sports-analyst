/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:toml/toml.dart';

part 'config.g.dart';

var _log = SSALogger("Config");

class ConfigLoader with ChangeNotifier {
  static ConfigLoader? _instance;
  factory ConfigLoader() {
    _instance ??= ConfigLoader._();
    return _instance!;
  }
  
  late SerializedConfig config;
  Future<void> get ready => _readyCompleter.future;
  Completer<void> _readyCompleter = Completer();

  ConfigLoader._() {
    _init();
  }
  
  Future<void> _init() async {
    await reload();
    _readyCompleter.complete();
  }
  
  Future<void> reload() async {
    try {
      var doc = await TomlDocument.load("./config.toml");
      var deserialized = SerializedConfig.fromToml(doc.toMap());
      config = deserialized;
      notifyListeners();
    }
    catch(e, st) {
      print("error loading config: $e $st");
    }
  }

  Future<void> save() async {

  }
}

@JsonSerializable()
class SerializedConfig {
  @JsonKey(defaultValue: Level.info)
  Level logLevel;
  
  factory SerializedConfig.fromToml(Map<String, dynamic> json) => _$SerializedConfigFromJson(json);
  Map<String, dynamic> toToml() => _$SerializedConfigToJson(this);

  SerializedConfig({required this.logLevel});
}