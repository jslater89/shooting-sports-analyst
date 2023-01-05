import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:sanitize_filename/sanitize_filename.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/ranking/shooter_aliases.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';

class RatingProjectManager {
  static const projectPrefix = "project/";
  static const autosaveName = "autosave";

  static RatingProjectManager? _instance;
  factory RatingProjectManager() {
    if(_instance == null) {
      _instance = RatingProjectManager._();
      _instance!._init();
    }
    
    return _instance!;
  }
  
  RatingProjectManager._() : _readyCompleter = Completer() {
    ready = _readyCompleter.future;
  }
  
  late Future<bool> ready;
  Completer<bool> _readyCompleter;
  static bool get readyNow => _instance != null && _instance!._readyCompleter.isCompleted;

  late SharedPreferences _prefs;
  late Box<String> _box;
  static const String _migrated = "migrated?";
  
  Future<void> _init() async {
    _box = await Hive.openBox<String>("rating-projects");

    if(!_box.containsKey(_migrated)) {
      _prefs = await SharedPreferences.getInstance();
      await _migrate();
    }
    await _loadFromPrefs();

    _readyCompleter.complete(true);
  }

  Future<void> _loadFromPrefs() async {
    for(var key in _box.keys) {
      if(key.startsWith(projectPrefix)) {
        try {
          Map<String, dynamic> encodedProject = jsonDecode(_box.get(key) ?? "");

          var project = RatingProject.fromJson(encodedProject);

          var mapName = key.replaceFirst(projectPrefix, "");
          if(mapName != project.name) {
            _projects[mapName] = project;
            debugPrint("Inflating $key (${project.name}) to $mapName");
          }
          else {
            _projects[project.name] = project;
            debugPrint("Inflating $key to ${project.name}");
          }
        }
        catch(e) {
          debugPrint("Error decoding project $key: $e");
          debugPrint(_box.get(key));
        }
      }
    }
  }

  Future<void> _migrate() async {
    print("Migrating ProjectManager to HiveDB");
    for(var key in _prefs.getKeys()) {
      if (key.startsWith(projectPrefix)) {
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

  Future<void> exportToFile(RatingProject project) async {
    await HtmlOr.saveFile("${sanitizeFilename(project.name, replacement: "-").replaceAll(RegExp(r"\s+"), "-")}.json", project.toJson());
  }

  Future<RatingProject?> importFromFile() async {
    var fileContents = await HtmlOr.pickAndReadFileNow();

    if(fileContents != null) {
      try {
        var encodedProject = jsonDecode(fileContents);
        var project =  RatingProject.fromJson(encodedProject);
        project.name = "${project.name}";
        return project;
      } catch(e) {
        print("Error loading file: $e");
      }
    }

    return null;
  }
  
  // Maps project name to a project
  Map<String, RatingProject> _projects = {};
  
  bool projectExists(String name) {
    return _projects.containsKey(name);
  }
  
  Future<void> saveProject(RatingProject project, {String? mapName}) async {
    _projects[project.name] = project;
    if(mapName != null && mapName != project.name) {
      _projects[mapName] = project;
    }

    var encoded = project.toJson();

    await _box.put("$projectPrefix${project.name}", encoded);
    if(mapName != null && mapName != project.name) {
      await _box.put("$projectPrefix$mapName", encoded);
    }

    var projectNames = [project.name];
    if(mapName != null && mapName != project.name) {
      projectNames.add(mapName);
    }
    debugPrint("Saved project ${project.name} to: $projectNames");
  }

  Future<void> deleteProject(String name) async {
    _projects.remove(name);
    await _box.delete("$projectPrefix$name");
  }

  List<String> savedProjects() {
    return _projects.keys.toList();
  }
  
  RatingProject? loadProject(String name) {
    var project = _projects[name];
    if(project != null) {
      print("Returning ${project.name} from $name");
    }
    else {
      print("No project for $name");
    }
    return project;
  }
}

const _nameKey = "name";
const _combineLocapKey = "combineLocap";
const _combineLimitedCOKey = "combineLimCO";
const _combineOpenPCCKey = "combineOpPCC";
const _keepHistoryKey = "keepHistory";
const _urlsKey = "urls";
const _whitelistKey = "memNumWhitelist";
const _aliasesKey = "aliases";
const _memberNumberMappingsKey = "numMappings";
const _memberNumberMappingBlacklistKey = "numMapBlacklist";

// Values for the multiplayer percent elo rater.

class RatingProject {
  static const byStageKey = "byStage";
  static const algorithmKey = "algo";
  static const multiplayerEloValue = "multiElo";
  static const openskillValue = "openskill";
  static const pointsValue = "points";

  String name;
  RatingHistorySettings settings;
  List<String> matchUrls;

  RatingProject({
    required this.name,
    required this.settings,
    required this.matchUrls,
  });

  factory RatingProject.fromJson(Map<String, dynamic> encodedProject) {
    var combineOpenPCC = (encodedProject[_combineOpenPCCKey] ?? false) as bool;
    var combineLimitedCO = (encodedProject[_combineLimitedCOKey] ?? false) as bool;
    var combineLocap = (encodedProject[_combineLocapKey] ?? true) as bool;

    var algorithmName = (encodedProject[algorithmKey] ?? multiplayerEloValue) as String;
    var algorithm = _algorithmForName(algorithmName, encodedProject);

    var settings = RatingHistorySettings(
      algorithm: algorithm,
      preserveHistory: encodedProject[_keepHistoryKey] as bool,
      groups: RatingHistorySettings.groupsForSettings(
        combineOpenPCC: combineOpenPCC,
        combineLimitedCO: combineLimitedCO,
        combineLocap: combineLocap,
      ),
      memberNumberWhitelist: ((encodedProject[_whitelistKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      shooterAliases: ((encodedProject[_aliasesKey] ?? defaultShooterAliases) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      memberNumberMappings: ((encodedProject[_memberNumberMappingsKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      memberNumberMappingBlacklist: ((encodedProject[_memberNumberMappingBlacklistKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
          MapEntry(k, v as String)
      ),
    );
    var matchUrls = (encodedProject[_urlsKey] as List<dynamic>).map((item) => item as String).toList();
    var name = encodedProject[_nameKey] as String;

    var rp = RatingProject(name: name, settings: settings, matchUrls: matchUrls);
    settings.project = rp;
    return rp;
  }

  static RatingSystem _algorithmForName(String name, Map<String, dynamic> encodedProject) {
    switch(name) {
      case multiplayerEloValue:
        return MultiplayerPercentEloRater.fromJson(encodedProject);
      case pointsValue:
        return PointsRater.fromJson(encodedProject);
      case openskillValue:
        return OpenskillRater.fromJson(encodedProject);
      default:
        throw ArgumentError();
    }
  }

  String toJson() {
    Map<String, dynamic> map = {};
    map[_nameKey] = name;
    map[_combineLocapKey] = settings.groups.contains(RaterGroup.locap);
    map[_combineOpenPCCKey] = settings.groups.contains(RaterGroup.openPcc);
    map[_combineLimitedCOKey] = settings.groups.contains(RaterGroup.limitedCO);
    map[_keepHistoryKey] = settings.preserveHistory;
    map[_urlsKey] = matchUrls;
    map[_whitelistKey] = settings.memberNumberWhitelist;
    map[_aliasesKey] = settings.shooterAliases;
    map[_memberNumberMappingsKey] = settings.memberNumberMappings;
    map[_memberNumberMappingBlacklistKey] = settings.memberNumberMappingBlacklist;

    /// Alg-specific settings
    settings.algorithm.encodeToJson(map);

    var encoded = jsonEncode(map);
    return encoded;
  }
}