import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/util.dart';

part 'match_cache.g.dart';

Future<void> Function(int, int)? matchCacheProgressCallback;

// TODO: migration2: back with the SQLite database
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

  /// Cache is the in-memory cache of matches. Matches are loaded into memory lazily.
  ///
  /// Matches known by multiple IDs (used as the key) point to the same cache entry.
  Map<String, _MatchCacheEntry> _cache = {};
  /// Index is the full index of the cache. The index is always fully loaded when
  /// loading the match cache.
  Map<String, MatchCacheIndexEntry> _index = {};
  late SharedPreferences _prefs;
  /// Box contains the full match files. Items are loaded from _box to _cache on demand.
  late Box<String> _box;
  /// IndexBox contains the match index, and is loaded on start.
  late Box<MatchCacheIndexEntry> _indexBox;
  static const _cachePrefix = "cache/";
  static const _cacheSeparator = "XxX";
  static const _migrated = "migrated?";

  void _init() async {
    Hive.registerAdapter(MatchCacheIndexEntryAdapter());
    _instance!.ready = _instance!._ready.future;
    _box = await Hive.openBox<String>("match-cache");
    _indexBox = await Hive.openBox<MatchCacheIndexEntry>("match-cache-index");

    if(!_box.containsKey(_migrated)) {
      _prefs = await SharedPreferences.getInstance();
      await _migrate();
    }
    
    if(_indexBox.isEmpty) {
      await _instance!._load();
      await _firstTimeIndex();
    }
    else {
      await _instance!._loadIndex();
    }

    _ready.complete(true);
  }

  String _removeQuery(String s) {
    return s.split("?").first;
  }

  Future<void> _firstTimeIndex() async {
    print("[MatchCache] Generating first-time index");
    for(var entry in _cache.values) {
      var idxEntry = MatchCacheIndexEntry.fromMatchEntry(entry);
      for(var id in idxEntry.ids) {
        _index[id] = idxEntry;
      }
      _indexBox.put(idxEntry.path, idxEntry);
    }
    print("[MatchCache] Generated ${_index.length} index entries from ${_cache.values.length} matches");
  }

  Future<void> _loadIndex() async {
    print("[MatchCache] Loading index");
    _index.clear();

    int i = 0;
    var paths = _indexBox.keys;
    for(var path in paths) {
      if(path.startsWith(_cachePrefix)) {
        var indexEntry = _indexBox.get(path);
        if(indexEntry != null) {
          print("[MatchCache] Loaded ${indexEntry.matchName} from ${indexEntry.ids}");
          for (var id in indexEntry.ids) {
            if(id.contains("?")) {
              id = _removeQuery(id);
            }
            _index[id] = indexEntry;
          }
        }
      }

      i += 1;
      if(i % 5 == 0) await matchCacheProgressCallback?.call(i, paths.length);
    }

    print("[MatchCache] Loaded ${_index.length} index entries from ${paths.length} paths");
  }

  Future<void> _load() async {
    print("[MatchCache] Loading full cache");
    _cache.clear();

    var paths = _box.keys;
    int i = 0;

    int matches = 0;
    int stages = 0;
    int shooters = 0;
    int stageScores = 0;

    for(var path in paths) {
      if(path.startsWith(_cachePrefix)) {
        var match = await _loadMatch(path);

        if(match != null) {
          matches += 1;
          stages += match.stages.length;
          shooters += match.shooters.length;
          stageScores += match.stageScoreCount;
        }

        i += 1;
        if(i % 5 == 0) await matchCacheProgressCallback?.call(i, paths.length);
      }
    }

    print("[MatchCache] Loaded $matches cached matches, with $stages stages, $shooters shooters, and $stageScores stage scores");
  }

  /// Loads a match from the local cache. Does not download.
  Future<PracticalMatch?> _loadMatch(String path) async {
    List<String> ids = path.replaceFirst(_cachePrefix, "").split(_cacheSeparator);
    var deduplicatedIds = Set<String>()..addAll(ids);
    ids = deduplicatedIds.toList();

    PracticalMatch? match;
    for(var id in ids) {
      var m = _cache[id]?.match;
      if(m != null) match = m;
    }

    if(match != null) return match;

    var reportContents = _box.get(path);

    if(reportContents != null) {
      // Anything that makes it to the cache is known good
      var match = (await processScoreFile(reportContents)).unwrap();
      var entry = _MatchCacheEntry(match: match, ids: ids);
      String? shortId;
      late String longId;
      for(var id in ids) {
        id = id.replaceAll("/","");
        if(id.contains("?")) id = _removeQuery(id);

        if(id.length > 10) {
          longId = id;
        }
        else {
          shortId = id;
        }

        // This is either a two-ID entry (short and UUID), or a one-ID entry
        // (UUID-only, because we always get the UUID if we only have the short ID).
        // If it's a UUID-only entry, only replace an entry in the cache if we haven't
        // already loaded a corresponding two-ID entry.
        if(ids.length == 1 && _cache.containsKey(id)) {
          if(verboseParse) print("[MatchCache] Skipping one-ID entry for $id: already loaded as two-ID entry");
          continue;
        }

        _cache[id] = entry;
      }

      match.practiscoreId = longId;
      match.practiscoreIdShort = shortId;

      if(verboseParse) print("[MatchCache] Loaded ${entry.match.name} from $path to $ids");
      return match;
    }
    else {
      print("[MatchCache] Failed to load $path!");
      return null;
    }
  }

  void clear() {
    _cache.clear();
    _index.clear();
    _clearPrefs();
  }

  void _clearPrefs() {
    var keys = _box.keys;
    for(var key in keys) {
      if(key.startsWith(_cachePrefix)) _box.delete(key);
    }

    keys = _indexBox.keys;
    for(var key in keys) {
      if(key.startsWith(_cachePrefix)) _indexBox.delete(key);
    }
  }

  int get length => _index.length;
  int get cacheLength => _cache.length;
  int? _cachedSize;
  int get size {
    if(_cachedSize != null) return _cachedSize!;

    // DB not used on web, so we can do this
    var dbFile = File(_box.path!);
    var indexFile = File(_indexBox.path!);

    if(dbFile.existsSync()) {
      _cachedSize = dbFile.statSync().size + indexFile.statSync().size;
      return _cachedSize!;
    }
    return 0;
  }

  int get uniqueMatches {
    Set<_MatchCacheEntry> entries = <_MatchCacheEntry>{};

    for(var e in _cache.values) {
      entries.add(e);
    }

    return entries.length;
  }

  int get uniqueIndexEntries {
    Set<MatchCacheIndexEntry> entries = <MatchCacheIndexEntry>{};

    for(var e in _index.values) {
      entries.add(e);
    }

    return entries.length;
  }

  /// Ensure that any previously-downloaded matches in the given list of URLs
  /// are fully loaded to memory.
  Future<void> ensureUrlsLoaded(List<String> matchUrls, [Future<void> Function(int, int)? progressCallback]) async {
    int i = 0;
    for(var url in matchUrls) {
      var idxEntry = getIndexImmediate(url);
      if(idxEntry != null) {
        await _loadMatch(idxEntry.path);
      }

      i += 1;
      if(i % 5 == 0) await progressCallback?.call(i, matchUrls.length);
    }
  }

  /// Ensure that the matches represented by the given index entries
  /// are fully loaded.
  Future<void> ensureLoaded(List<MatchCacheIndexEntry> entries, [Future<void> Function(int, int)? progressCallback]) async {
    int i = 0;
    for(var entry in entries) {
      await _loadMatch(entry.path);

      i += 1;
      if(i % 5 == 0) await matchCacheProgressCallback?.call(i, entries.length);
    }
  }

  /// Save a match to the cache.
  Future<void> save({Future<void> Function(int, int)? progressCallback, List<String> forceResave = const []}) async {
    Set<_MatchCacheEntry> alreadySaved = Set();
    int totalProgress = _cache.values.length;
    int currentProgress = 0;

    for(var entry in _cache.values) {
      var originalPath = entry.generatePath();

      List<String> ids = [];
      bool idsChanged = false;
      for(var id in entry.ids) {
        if(id.contains("?")) {
          id = _removeQuery(id);
          idsChanged = true;
        }
        ids.add(id);
      }
      if(idsChanged) {
        entry.ids.clear();
        entry.ids.addAll(ids);
      }

      if(alreadySaved.contains(entry)) {
        currentProgress += 1;
        await progressCallback?.call(currentProgress, totalProgress);
        continue;
      }

      var path = entry.generatePath();

      // If we already have the match saved to the full cache, and its IDs do not intersect
      // with the list of IDs to force-resave, and its IDs were not changed to remove query
      // strings, skip it.
      if(!idsChanged && _box.containsKey(path) && entry.ids.where((e) => forceResave.contains(e)).isEmpty) {
        currentProgress += 1;
        await progressCallback?.call(currentProgress, totalProgress);
        // print("[MatchCache] Not resaving ${entry.match.name}");
        continue; // No need to resave
      }

      // If the IDs changed to remove a query string, remove the original entry.
      if(idsChanged) {
        _box.delete(originalPath);
        _indexBox.delete(originalPath);
      }

      // Box saves in a background isolate
      _box.put(path, entry.match.reportContents);
      _indexBox.put(path, MatchCacheIndexEntry.fromMatchEntry(entry));
      _cachedSize = null;
      alreadySaved.add(entry);
      print("[MatchCache] Saved ${entry.match.name} to $path");

      currentProgress += 1;
      if(currentProgress % 5 == 0) await matchCacheProgressCallback?.call(currentProgress, totalProgress);
    }
  }

  Future<bool> deleteMatchByUrl(String matchUrl) {
    var id = matchUrl.split("/").last;
    var entry = _cache[id];

    return _deleteEntry(entry);
  }

  Future<bool> deleteMatch(PracticalMatch match) {
    var entry = _cache.entries.firstWhereOrNull((e) => e.value.match == match);
    return _deleteEntry(entry?.value);
  }

  Future<bool> deleteIndexEntry(MatchCacheIndexEntry entry) async {
    for(var id in entry.ids) {
      _index.remove(id);
      _cache.remove(id);
    }

    await _indexBox.delete(entry.generatePath());
    await _box.delete(entry.generatePath());

    return true;
  }

  Future<bool> _deleteEntry(_MatchCacheEntry? entry) async {
    if(entry != null) {
      for(var id in entry.ids) {
        print("[MatchCache] Deleted $id");
        _cache.remove(id);
        _index.remove(id);
      }
      await _box.delete(entry.generatePath());
      await _indexBox.delete(entry.generatePath());
      print("[MatchCache] Deleted cache and index entries from ${entry.generatePath()}");
      _cachedSize = null;
      return true;
    }
    return false;
  }

  void insert(PracticalMatch match) {
    String? shortId;
    if(match.practiscoreIdShort != null) {
      shortId = match.practiscoreIdShort!;
      if(shortId.contains("?")) shortId = _removeQuery(shortId);
    }

    var ids = [
      match.practiscoreId,
      if(shortId != null) shortId,
    ];
    var entry = _MatchCacheEntry(match: match, ids: ids);
    var index = MatchCacheIndexEntry.fromMatchEntry(entry);
    for(var id in ids) {
      _cache[id] = entry;
      _index[id] = index;
    }

    print("[MatchCache] Inserted cache and index entry for ${ids}");
  }

  String? getUrl(PracticalMatch match) {
    var entry = _cache.entries.firstWhereOrNull((element) => element.value.match == match);

    if(entry != null) {
      return "https://practiscore.com/results/new/${entry.key}";
    }
    return null;
  }

  String? getIndexUrl(MatchCacheIndexEntry indexEntry) {
    var entries = _index.entries.where((element) => element.value == indexEntry).toList();

    if(entries.isEmpty) return null;

    if(entries.length == 1) return "https://practiscore.com/results/new/${entries[0].key}";

    // Return the shorter ID, if present. That way, we never lose the short-id mapping
    // if we use this method to get a URL to re-fetch a match.
    var entry = entries.map((e) => e.key).reduce((a, b) => a.length < b.length ? a : b);

    return "https://practiscore.com/results/new/$entry";
  }

  MatchCacheIndexEntry? getIndexImmediate(String matchUrl) {
    var id = matchUrl.split("/").last;
    if(id.contains("?")) id = _removeQuery(id);
    return _index[id];
  }

  Future<PracticalMatch?> getMatchImmediate(String matchUrl) {
    var id = matchUrl.split("/").last;
    if(id.contains("?")) id = _removeQuery(id);
    return _loadIndexed(id);
  }

  Future<PracticalMatch> getByIndex(MatchCacheIndexEntry index) async {
    return (await _loadIndexed(index.ids.first))!;
  }

  Future<PracticalMatch?> _loadIndexed(String id) async {
    if(id.contains("?")) id = _removeQuery(id);

    if(_cache.containsKey(id)) {
      return _cache[id]!.match;
    }
    else if(_index.containsKey(id)) {
      return _loadMatch(_index[id]!.path);
    }
    else {
      return null;
    }
  }

  void _insert(_MatchCacheEntry entry) {
    var indexEntry = MatchCacheIndexEntry.fromMatchEntry(entry);
    for(var id in entry.ids) {
      if(id.contains("?")) id = _removeQuery(id);
      _cache[id] = entry;
      _index[id] = indexEntry;
    }

    print("[MatchCache] Inserted cache entry at ${entry.ids} ");
  }

  Future<Result<PracticalMatch, MatchGetError>> getMatch(String matchUrl, {bool forceUpdate = false, bool localOnly = false, bool checkCanonId = true}) async {
    var id = matchUrl.split("/").last;
    if(id.contains("?")) id = _removeQuery(id);

    if(!forceUpdate && _index.containsKey(id)) {
      // print("[MatchCache] Using local cache for $id");
      var match = await _loadIndexed(id);
      return Result.ok(match!);
    }

    if(localOnly && !checkCanonId) return Result.err(MatchGetError.notInCache);

    var canonId = await processMatchUrl(matchUrl);

    // If this ID corresponds to a known canonical ID, make a new
    // entry containing both.
    if(id != canonId && canonId != null && _cache.containsKey(canonId)) {
      var newEntry = _MatchCacheEntry(
        match: _cache[canonId]!.match,
        ids: [id, canonId]
      );
      _insert(newEntry);
      return Result.ok(_cache[id]!.match);
    }

    if(localOnly) return Result.err(MatchGetError.notInCache);

    if(canonId != null) {
      var result = await getPractiscoreMatchHeadless(canonId);
      if(result.isOk()) {
        var match = result.unwrap();
        match.practiscoreId = canonId;
        if(id != canonId) {
          match.practiscoreIdShort = id;
        }
        var ids = [canonId];
        if(id != canonId) ids.insert(0, id);

        insert(match);
        return result;
      }
      else {
        return result;
      }
    }
    else {
      print("[MatchCache] canon ID is null");
      return Result.err(MatchGetError.notHitFactor);
    }
  }

  Set<String> _urlsInFlight = {};
  Future<List<PracticalMatch>> batchGet(List<String> urls, {void Function(String, Result<PracticalMatch, MatchGetError>)? callback}) async {
    List<PracticalMatch> downloaded = [];
    while(urls.isNotEmpty) {
      int batchSize = 0;
      List<String> batchUrls = [];
      while(urls.isNotEmpty && batchSize < 5) {
        batchUrls.add(urls.removeLast());
        batchSize++;
      }

      Map<String, Future<Result<PracticalMatch, MatchGetError>>> futures = {};
      for(var url in batchUrls) {
        if(!_urlsInFlight.contains(url)) {
          _urlsInFlight.add(url);
          futures[url] = getMatch(url);
        }
      }

      await Future.wait(futures.values);
      for(var url in batchUrls) {
        _urlsInFlight.remove(url);
        if(callback != null && futures.containsKey(url)) {
          callback(url, await futures[url]!);
        }
      }
    }

    return downloaded;
  }

  MatchCacheIndexEntry? indexEntryFor(PracticalMatch match) {
    return _index[match.practiscoreId];
  }

  List<PracticalMatch> allMatches() {
    var matchSet = Set<PracticalMatch>()..addAll(_cache.values.map((e) => e.match));
    return matchSet.toList();
  }

  List<MatchCacheIndexEntry> allIndexEntries() {
    var idxSet = Set<MatchCacheIndexEntry>()..addAll(_index.values);
    return idxSet.toList();
  }

  Future<void> _migrate() async {
    print("[MatchCache] Migrating MatchCache to HiveDB");
    for(var key in _prefs.getKeys()) {
      if (key.startsWith(_cachePrefix)) {
        var string = _prefs.getString(key);
        if (string != null) {
          _box.put(key, string);
          print("[MatchCache] Moved $key to Hive");
        }
        _prefs.remove(key);
        print("[MatchCache] Deleted $key from shared prefs");
      }
    }

    _box.put(_migrated, "true");
    print("[MatchCache] Migration complete");
  }
}

@HiveType(typeId: 0)
class MatchCacheIndexEntry extends _PathedEntry {
  /// The path created by generatePath for this and the associated match.
  @HiveField(3)
  final String path;

  /// The name of the match.
  @HiveField(0)
  final String matchName;

  /// The date of the match.
  @HiveField(1)
  final DateTime matchDate;

  /// All IDs this match is known by.
  @HiveField(2)
  final List<String> ids;

  MatchCacheIndexEntry({required this.path, required this.matchName, required this.matchDate, required this.ids});

  MatchCacheIndexEntry.fromMatchEntry(_MatchCacheEntry entry) :
      path = entry.generatePath(),
      matchName = entry.match.name ?? "Unnamed Match",
      matchDate = entry.match.date ?? DateTime(2015, 1, 1),
      ids = entry.ids;

  @override
  String toString() {
    return "$matchName $ids";
  }
}

class _MatchCacheEntry extends _PathedEntry {
  final PracticalMatch match;
  final List<String> ids;

  _MatchCacheEntry({required this.match, required this.ids});
}

abstract class _PathedEntry {
  List<String> get ids;

  String generatePath() {
    var idString = this.ids.sorted((a,b) => a.compareTo(b)).join(MatchCache._cacheSeparator);
    return "${MatchCache._cachePrefix}$idString";
  }
}