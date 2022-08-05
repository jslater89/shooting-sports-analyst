import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';

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
  static bool get readyNow => _instance != null && _instance!._ready.isCompleted;

  Map<String, _MatchCacheEntry> _cache = {};
  late SharedPreferences _prefs;
  static const _cachePrefix = "cache/";
  static const _cacheSeparator = "XxX";

  void _init() async {
    _instance!.ready = _instance!._ready.future;
    _prefs = await SharedPreferences.getInstance();
    await _instance!.load();

    _ready.complete(true);
  }

  Future<void> load() async {
    _cache.clear();

    var paths = _prefs.getKeys();
    for(var path in paths) {
      if(path.startsWith(_cachePrefix)) {
        var reportContents = _prefs.getString(path);

        var ids = path.replaceFirst(_cachePrefix, "").split(_cacheSeparator);

        if(reportContents != null) {
          var match = await processScoreFile(reportContents);
          var entry = _MatchCacheEntry(match: match, ids: ids);
          for(var id in ids) {
            id = id.replaceAll("/","");
            _cache[id] = entry;
          }

          debugPrint("Loaded ${entry.match.name} from $path to $ids");
        }
      }
    }
  }

  void clear() {
    _cache.clear();
    _clearPrefs();
  }

  void _clearPrefs() {
    var keys = _prefs.getKeys();
    for(var key in keys) {
      if(key.startsWith(_cachePrefix)) _prefs.remove(key);
    }
  }

  String _generatePath(_MatchCacheEntry entry) {
    var idString = entry.ids.sorted((a,b) => a.compareTo(b)).join(_cacheSeparator);
    return "$_cachePrefix$idString";
  }

  Future<void> save([Future<void> Function(int, int)? progressCallback]) async {
    Set<_MatchCacheEntry> alreadySaved = Set();
    int totalProgress = _cache.values.length;
    int currentProgress = 0;

    for(var entry in _cache.values) {
      if(alreadySaved.contains(entry)) {
        currentProgress += 1;
        await progressCallback?.call(currentProgress, totalProgress);
        continue;
      }

      var path = _generatePath(entry);
      if(_prefs.containsKey(path)) {
        currentProgress += 1;
        await progressCallback?.call(currentProgress, totalProgress);
        continue; // No need to resave
      }

      await _prefs.setString(path, entry.match.reportContents);
      alreadySaved.add(entry);
      debugPrint("Saved ${entry.match.name} to $path");

      currentProgress += 1;
      await progressCallback?.call(currentProgress, totalProgress);
    }
  }

  Future<PracticalMatch?> getMatch(String matchUrl, {bool forceUpdate = false, bool localOnly = false}) async {
    var id = matchUrl.split("/").last;
    if(!forceUpdate && _cache.containsKey(id)) {
      // debugPrint("Using cache for $id");
      return _cache[id]!.match;
    }

    if(localOnly) return null;

    var canonId = await processMatchUrl(matchUrl);

    if(canonId != null) {
      var match = await getPractiscoreMatchHeadless(canonId);
      if(match != null) {
        var cacheEntry = _MatchCacheEntry(
          ids: [id, canonId],
          match: match,
        );
        _cache[id] = cacheEntry;
        _cache[canonId] = cacheEntry;
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

class _MatchCacheEntry {
  final PracticalMatch match;
  final List<String> ids;

  _MatchCacheEntry({required this.match, required this.ids});
}