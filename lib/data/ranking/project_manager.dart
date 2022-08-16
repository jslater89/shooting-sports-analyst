import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
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
  
  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromPrefs();

    _readyCompleter.complete(true);
  }

  Future<void> _loadFromPrefs() async {
    for(var key in _prefs.getKeys()) {
      if(key.startsWith(projectPrefix)) {
        try {
          Map<String, dynamic> encodedProject = jsonDecode(_prefs.getString(key) ?? "");

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
          debugPrint(_prefs.getString(key));
        }
      }
    }
  }

  Future<void> exportToFile(RatingProject project) async {
    await HtmlOr.saveFile("${project.name.replaceAll(RegExp(r"[ ,+]+"), "-")}.json", project.toJson());
  }

  Future<RatingProject?> importFromFile() async {
    var fileContents = await HtmlOr.pickAndReadFileNow();

    if(fileContents != null) {
      try {
        var encodedProject = jsonDecode(fileContents);
        var project =  RatingProject.fromJson(encodedProject);
        project.name = "${project.name} (imported)";
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

    await _prefs.setString("$projectPrefix${project.name}", encoded);
    if(mapName != null && mapName != project.name) {
      await _prefs.setString("$projectPrefix$mapName", encoded);
    }

    var projectNames = [project.name];
    if(mapName != null && mapName != project.name) {
      projectNames.add(mapName);
    }
    debugPrint("Saved project ${project.name} to: $projectNames");
  }

  Future<void> deleteProject(String name) async {
    _projects.remove(name);
    await _prefs.remove("$projectPrefix$name");
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
const _kKey = "k";
const _pctWeightKey = "pctWt";
const _scaleKey = "scale";
const _combineLocapKey = "combineLocap";
const _combineLimitedCOKey = "combineLimCO";
const _combineOpenPCCKey = "combineOpPCC";
const _byStageKey = "byStage";
const _keepHistoryKey = "keepHistory";
const _urlsKey = "urls";
const _whitelistKey = "memNumWhitelist";
const _aliasesKey = "aliases";

class RatingProject {
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

    var settings = RatingHistorySettings(
      algorithm: MultiplayerPercentEloRater(
        K: encodedProject[_kKey] as double,
        percentWeight: encodedProject[_pctWeightKey] as double,
        scale: encodedProject[_scaleKey] as double,
      ),
      preserveHistory: encodedProject[_keepHistoryKey] as bool,
      byStage: encodedProject[_byStageKey] as bool,
      groups: RatingHistorySettings.groupsForSettings(
        combineOpenPCC: combineOpenPCC,
        combineLimitedCO: combineLimitedCO,
        combineLocap: combineLocap,
      ),
      memberNumberWhitelist: ((encodedProject[_whitelistKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      shooterAliases: ((encodedProject[_aliasesKey] ?? defaultShooterAliases) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      )
    );
    var matchUrls = (encodedProject[_urlsKey] as List<dynamic>).map((item) => item as String).toList();
    var name = encodedProject[_nameKey] as String;

    return RatingProject(name: name, settings: settings, matchUrls: matchUrls);
  }

  String toJson() {
    var algorithm = settings.algorithm as MultiplayerPercentEloRater;

    Map<String, dynamic> map = {};
    map[_nameKey] = name;
    map[_kKey] = algorithm.K;
    map[_pctWeightKey] = algorithm.percentWeight;
    map[_scaleKey] = algorithm.scale;
    map[_combineLocapKey] = settings.groups.contains(RaterGroup.locap);
    map[_combineOpenPCCKey] = settings.groups.contains(RaterGroup.openPcc);
    map[_combineLimitedCOKey] = settings.groups.contains(RaterGroup.limitedCO);
    map[_byStageKey] = settings.byStage;
    map[_keepHistoryKey] = settings.preserveHistory;
    map[_urlsKey] = matchUrls;
    map[_whitelistKey] = settings.memberNumberWhitelist;
    map[_aliasesKey] = settings.shooterAliases;

    var encoded = jsonEncode(map);
    return encoded;
  }
}