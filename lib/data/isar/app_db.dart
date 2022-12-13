import 'dart:async';

import 'package:isar/isar.dart';

class Storage {
  static Storage? _instance;

  factory Storage() {
    if(_instance == null) {
      _instance = Storage._();
      _instance!._init();
    }

    return _instance!;
  }

  Storage._();

  Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;
  
  late Isar db;

  Future<void> _init() async {
    db = await Isar.open(schemas: [], name: "appStorage");
  }
}