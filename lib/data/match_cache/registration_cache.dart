/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';

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

  /// Contains match registration HTML. The key is the match ID.
  late LazyBox<String> _box;

  Future<List<String>> getMatchIds({String? prefix, int? limit}) async {
    if(prefix != null) {
      if(prefix.contains("http") || prefix.contains("practiscore.com")) {
        prefix = extractMatchIdFromUrl(prefix);
      }
    }
    await _openBox();
    var keys = await _box.keys;
    await _box.close();
    var iterator = keys.map((k) => k as String).where((k) => prefix == null || k.toLowerCase().startsWith(prefix.toLowerCase())).toList();
    if(limit != null) {
      iterator = iterator.take(limit).toList();
    }
    return iterator.toList();
  }

  Future<void> put(String matchId, String html) async {
    await _openBox();
    await _box.put(matchId, html);
    await _box.close();
  }

  Future<String?> get(String matchId) async {
    await _openBox();
    var html = await _box.get(matchId);
    await _box.close();
    return html;
  }
}
