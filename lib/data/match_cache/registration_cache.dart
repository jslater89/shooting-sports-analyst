/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("RegistrationCache");

class RegistrationCache {
  static final RegistrationCache _instance = RegistrationCache._();
  factory RegistrationCache() => _instance;
  RegistrationCache._() {
    _init();
  }

  static Future<void> waitReady() async {
    await _instance.ready;
  }

  var _ready = Completer<bool>();
  Future<bool> get ready => _ready.future;

  late final Directory dbPath;

  Future<void> _init() async {
    _log.i("Initializing registration cache");
    dbPath = Directory("./db/registration_cache");
    if(!dbPath.existsSync()) {
      dbPath.createSync(recursive: true);
    }

    await _openBox();
    await _box.close();

    _ready.complete(true);
  }

  Future<void> _openBox() async {
    _box = await Hive.openLazyBox(
      "registration_cache",
      path: dbPath.path
    );
  }

  /// Contains match registration HTML. The key is the match URL.
  late LazyBox<String> _box;

  Future<void> put(String url, String html) async {
    await _openBox();
    await _box.put(url, html);
    await _box.close();
  }

  Future<String?> get(String url) async {
    await _openBox();
    var html = await _box.get(url);
    await _box.close();
    return html;
  }
}
