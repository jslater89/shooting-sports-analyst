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

  late SerializedUIConfig uiConfig;

  @override
  Future<void> setConfig(SerializedConfig config) async {
    await super.setConfig(config);
    notifyListeners();
  }

  Future<void> setUIConfig(SerializedUIConfig config) async {
    uiConfig = config;
    await save();
    notifyListeners();
  }

  Future<void> setConfigs((SerializedConfig config, SerializedUIConfig uiConfig) configs) async {
    config = configs.$1;
    uiConfig = configs.$2;
    await save();
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
    _log.d("Saved UI config: $uiConfig");
    await super.save();
  }
}

@JsonSerializable()
class SerializedUIConfig {
  @JsonKey(defaultValue: ThemeMode.system)
  ThemeMode themeMode;

  @JsonKey(defaultValue: 1.0)
  double uiScaleFactor;

  SerializedUIConfig({required this.themeMode, required this.uiScaleFactor});

  Map<String, dynamic> toJson() => _$SerializedUIConfigToJson(this);
  factory SerializedUIConfig.fromJson(Map<String, dynamic> json) => _$SerializedUIConfigFromJson(json);

  SerializedUIConfig copy() => SerializedUIConfig(themeMode: themeMode, uiScaleFactor: uiScaleFactor);

  @override
  String toString() {
    var builder = StringBuffer();
    builder.writeln("UIConfig:");
    builder.writeln("\tthemeMode = ${themeMode.name}");
    builder.writeln("\tuiScaleFactor = $uiScaleFactor");
    return builder.toString();
  }
}
