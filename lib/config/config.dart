/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:toml/toml.dart';

part 'config.g.dart';

final _log = SSALogger("UIConfig");

/// ConfigLoader loads and saves the config.toml file, and notifies
/// listeners when the configuration is reloaded.
class ChangeNotifierConfigLoader extends ConfigLoader with ChangeNotifier {
  static ChangeNotifierConfigLoader? _instance;
  factory ChangeNotifierConfigLoader() {
    _instance ??= ChangeNotifierConfigLoader._();
    return _instance!;
  }

  ChangeNotifierConfigLoader._() : super.create();

  late SerializedConfig config;
  Future<void> get ready => _readyCompleter.future;
  Completer<void> _readyCompleter = Completer();

  late SerializedUIConfig uiConfig;

  @override
  Future<void> setConfig(SerializedConfig config) async {
    await super.setConfig(config);
    notifyListeners();
  }

  Future<void> setUIConfig(SerializedUIConfig config) async {
    uiConfig = config;
    notifyListeners();
  }

  @override
  Future<bool> reload() async {
    var result = await super.reload();
    if(!result) {
      return false;
    }
    File f = File("./ui_config.toml");
    if(!f.existsSync()) {
      f.createSync();
    }
    try {
      var doc = await TomlDocument.load("./ui_config.toml");
      var deserialized = SerializedUIConfig.fromJson(doc.toMap());
      uiConfig = deserialized;
      _log.i("Loaded ui config: $uiConfig");
      notifyListeners();
      return true;
    }
    catch(e, st) {
      print("error loading config: $e $st");
      return false;
    }
  }

  @override
  Future<void> save() async {
    var doc = TomlDocument.fromMap(uiConfig.toJson());
    var str = await doc.toString();
    File f = File("./ui_config.toml");
    await f.writeAsString(str);
    await super.save();
  }
}

@JsonSerializable()
class SerializedUIConfig {
  @JsonKey(defaultValue: ThemeMode.system)
  ThemeMode themeMode;

  SerializedUIConfig({required this.themeMode});

  Map<String, dynamic> toJson() => _$SerializedUIConfigToJson(this);
  factory SerializedUIConfig.fromJson(Map<String, dynamic> json) => _$SerializedUIConfigFromJson(json);
}
