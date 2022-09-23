import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';

Future<void> Function(int, int)? matchCacheProgressCallback;

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
  late Box<String> _box;
  static const _cachePrefix = "cache/";
  static const _cacheSeparator = "XxX";
  static const _migrated = "migrated?";

  void _init() async {
    _instance!.ready = _instance!._ready.future;
    _box = await Hive.openBox<String>("match-cache");

    if(!_box.containsKey(_migrated)) {
      _prefs = await SharedPreferences.getInstance();
      await _migrate();
    }

    await _instance!.load();

    _ready.complete(true);
  }

  Future<void> load() async {
    _cache.clear();

    var paths = _box.keys;
    int i = 0;

    int matches = 0;
    int stages = 0;
    int shooters = 0;
    int stageScores = 0;

    for(var path in paths) {
      if(path.startsWith(_cachePrefix)) {
        var reportContents = _box.get(path);

        var ids = path.replaceFirst(_cachePrefix, "").split(_cacheSeparator);

        if(reportContents != null) {
          var match = await processScoreFile(reportContents);
          var entry = _MatchCacheEntry(match: match, ids: ids);
          for(var id in ids) {
            id = id.replaceAll("/","");
            _cache[id] = entry;
          }

          matches += 1;
          stages += match.stages.length;
          shooters += match.shooters.length;
          stageScores += match.stageScoreCount;

          if(verboseParse) print("Loaded ${entry.match.name} from $path to $ids");
        }

        i += 1;
        await matchCacheProgressCallback?.call(i, paths.length);
      }
    }

    print("Loaded $matches cached matches, with $stages stages, $shooters shooters, and $stageScores stage scores");
  }

  void clear() {
    _cache.clear();
    _clearPrefs();
  }

  void _clearPrefs() {
    var keys = _box.keys;
    for(var key in keys) {
      if(key.startsWith(_cachePrefix)) _box.delete(key);
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
      if(_box.containsKey(path)) {
        currentProgress += 1;
        await progressCallback?.call(currentProgress, totalProgress);
        continue; // No need to resave
      }

      // Box saves in a background isolate
      _box.put(path, entry.match.reportContents);
      alreadySaved.add(entry);
      print("Saved ${entry.match.name} to $path");

      currentProgress += 1;
      await progressCallback?.call(currentProgress, totalProgress);
    }
  }

  Future<bool> deleteMatch(String matchUrl) async {
    var id = matchUrl.split("/").last;
    var entry = _cache[id];

    if(entry != null) {
      for(var id in entry.ids) {
        _cache.remove(id);
      }
      await _box.delete(_generatePath(entry));
      return true;
    }

    return false;
  }

  PracticalMatch? getMatchImmediate(String matchUrl) {
    var id = matchUrl.split("/").last;
    if(_cache.containsKey(id)) {
      return _cache[id]!.match;
    }

    return null;
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
        var ids = [canonId];
        if(id != canonId) ids.insert(0, id);

        var cacheEntry = _MatchCacheEntry(
          ids: ids,
          match: match,
        );

        if(id != canonId) _cache[id] = cacheEntry;

        _cache[canonId] = cacheEntry;
        return match;
      }
      print("Match is null");
    }
    else {
      print("canon ID is null");
    }

    return null;
  }

  Future<void> _migrate() async {
    print("Migrating MatchCache to HiveDB");
    for(var key in _prefs.getKeys()) {
      if (key.startsWith(_cachePrefix)) {
        var string = _prefs.getString(key);
        if (string != null) {
          _box.put(key, string);
          print("Moved $key to Hive");
        }
        _prefs.remove(key);
        print("Deleted $key from shared prefs");
      }
    }

    _box.put(_migrated, "true");
    print("Migration complete");
  }
}

class _MatchCacheEntry {
  final PracticalMatch match;
  final List<String> ids;

  _MatchCacheEntry({required this.match, required this.ids});
}