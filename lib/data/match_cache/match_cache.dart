import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';

class MatchCache {
  static MatchCache? _instance;
  factory MatchCache() {
    if(_instance == null) {
      _instance = MatchCache._();
      _instance!._init();

    }

    return _instance!;
  }
  MatchCache._();

  var _ready = Completer<bool>();
  late Future<bool> ready;

  Map<String, PracticalMatch> _cache = {};
  late SharedPreferences _prefs;

  void _init() async {
    _instance!.ready = _instance!._ready.future;
    _prefs = await SharedPreferences.getInstance();
    await _instance!.load();

    _ready.complete(true);
  }

  Future<void> load() async {

  }

  void clear() {
    _cache.clear();
    // TODO: clear prefs?
  }

  void save() async {

  }

  Future<PracticalMatch?> getMatch(String matchUrl, {bool forceUpdate = false}) async {
    var id = matchUrl.split("/").last;
    if(!forceUpdate && _cache.containsKey(id)) {
      debugPrint("Using cache for $id");
      return _cache[id];
    }

    var canonId = await processMatchUrl(matchUrl);

    if(canonId != null) {
      var match = await getPractiscoreMatchHeadless(canonId);
      if(match != null) {
        _cache[id] = match;
        _cache[canonId] = match;
        return match;
      }
      debugPrint("Match is null");
    }
    else {
      debugPrint("canon ID is null");
    }

    return null;
  }
}