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

  Future<void> _init() async {
    _log.i("Initializing registration cache");
    Directory dbPath = Directory("./db/registration_cache");
    if(!dbPath.existsSync()) {
      dbPath.createSync(recursive: true);
    }

    _box = await Hive.openLazyBox(
      "registration_cache",
      path: dbPath.path
    );

    _ready.complete(true);
  }

  /// Contains match registration HTML. The key is the match URL.
  late LazyBox<String> _box;

  Future<void> put(String url, String html) async {
    _box.put(url, html);
  }

  Future<String?> get(String url) async {
    return _box.get(url);
  }
}
