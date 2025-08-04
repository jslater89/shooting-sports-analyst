/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:toml/toml.dart';


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

  @override
  Future<bool> reload() async {
    var result = await super.reload();
    notifyListeners();
    return result;
  }

  @override
  Future<void> setConfig(SerializedConfig config) async {
    await super.setConfig(config);
    notifyListeners();
  }
}
