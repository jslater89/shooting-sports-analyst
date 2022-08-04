import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';

class RatingProjectManager {
  static const projectPrefix = "project/";
  static const autosaveName = "autosave";

  static const combinedLocap = const [
    RaterGroup.open,
    RaterGroup.limited,
    RaterGroup.pcc,
    RaterGroup.carryOptics,
    RaterGroup.locap,
  ];

  static const splitLocap = const [
    RaterGroup.open,
    RaterGroup.limited,
    RaterGroup.pcc,
    RaterGroup.carryOptics,
    RaterGroup.production,
    RaterGroup.singleStack,
    RaterGroup.revolver,
    RaterGroup.limited10,
  ];
  
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
          var settings = RatingHistorySettings(
            algorithm: MultiplayerPercentEloRater(
              K: encodedProject[_kKey] as double,
              percentWeight: encodedProject[_pctWeightKey] as double,
              scale: encodedProject[_scaleKey] as double,
            ),
            preserveHistory: encodedProject[_keepHistoryKey] as bool,
            byStage: encodedProject[_byStageKey] as bool,
            groups: (encodedProject[_combineLocapKey] as bool) ? combinedLocap : splitLocap,
          );
          var matchUrls = (encodedProject[_urlsKey] as List<dynamic>).map((item) => item as String).toList();
          var name = encodedProject[_nameKey] as String;

          _projects[name] = RatingProject(name: name, settings: settings, matchUrls: matchUrls);
        }
        catch(e) {
          debugPrint("Error decoding project $key: $e");
          debugPrint(_prefs.getString(key));
        }
      }
    }
  }
  
  // Maps project name to a project
  Map<String, RatingProject> _projects = {};
  
  bool projectExists(String name) {
    return _projects.containsKey(name);
  }
  
  Future<void> saveProject(RatingProject project) async {
    _projects[project.name] = project;

    var algorithm = project.settings.algorithm as MultiplayerPercentEloRater;

    Map<String, dynamic> map = {};
    map[_nameKey] = project.name;
    map[_kKey] = algorithm.K;
    map[_pctWeightKey] = algorithm.percentWeight;
    map[_scaleKey] = algorithm.scale;
    map[_combineLocapKey] = project.settings.groups.contains(RaterGroup.locap);
    map[_byStageKey] = project.settings.byStage;
    map[_keepHistoryKey] = project.settings.preserveHistory;
    map[_urlsKey] = project.matchUrls;

    var encoded = jsonEncode(map);

    await _prefs.setString("$projectPrefix${project.name}", encoded);
  }

  List<String> savedProjects() {
    return _projects.keys.toList();
  }
  
  RatingProject? loadProject(String name) {
    return _projects[name];
  }

  static const _nameKey = "name";
  static const _kKey = "k";
  static const _pctWeightKey = "pctWt";
  static const _scaleKey = "scale";
  static const _combineLocapKey = "combineLocap";
  static const _byStageKey = "byStage";
  static const _keepHistoryKey = "keepHistory";
  static const _urlsKey = "urls";
}

class RatingProject {
  String name;
  RatingHistorySettings settings;
  List<String> matchUrls;
  
  RatingProject({
    required this.name,
    required this.settings,
    required this.matchUrls,
  });
}