/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:isar/isar.dart';
import 'package:sanitize_filename/sanitize_filename.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/member_number_collision_dialog.dart';

var _log = SSALogger("RatingProjectMgr");

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
            _log.v("Inflating $key (${project.name}) to $mapName");
          }
          else {
            _projects[project.name] = project;
            _log.v("Inflating $key to ${project.name}");
          }
        }
        catch(e, st) {
          _log.e("Error decoding project $key", error: e, stackTrace: st);
          _log.i("Content: ${_box.get(key)}");
        }
      }
    }
  }

  Future<void> _migrate() async {
    _log.i("Migrating ProjectManager to HiveDB");
    for(var key in _prefs.getKeys()) {
      if (key.startsWith(projectPrefix)) {
        var string = _prefs.getString(key);
        if (string != null) {
          _box.put(key, string);
          _log.v("Moved $key to Hive");
        }
        _prefs.remove(key);
        _log.v("Deleted $key from shared prefs");
      }
    }

    _box.put(_migrated, "true");
    _log.i("Migration complete");
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
      } catch(e, st) {
        _log.e("Error loading file", error: e, stackTrace: st);
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
    _log.d("Saved project ${project.name} to: $projectNames");
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
      _log.d("Returning ${project.name} from $name");
    }
    else {
      _log.w("No project for $name");
    }
    return project;
  }
}

const _sportKey = "sport";
const _nameKey = "name";
const _combineLocapKey = "combineLocap";
const _combineLimitedCOKey = "combineLimCO";
const _limitedLoCoCombineModeKey = "combineLimLoCo";
const _combineOpenPCCKey = "combineOpPCC";
const _keepHistoryKey = "keepHistory";
const _urlsKey = "urls";
const _whitelistKey = "memNumWhitelist";
const _aliasesKey = "aliases";
const _memberNumberMappingsKey = "numMappings";
const _memberNumberMappingBlacklistKey = "numMapBlacklist";
const _hiddenShootersKey = "hiddenShooters";
const _memberNumberCorrectionsKey = "memNumCorrections";
const _recognizedDivisionsKey = "recDivs";
const _checkDataEntryKey = "checkDataEntry";
const _groupsKey = "groups";

// Values for the multiplayer percent elo rater.

class RatingProject with DbSportEntity {
  Id id = Isar.autoIncrement;

  static const byStageKey = "byStage";
  static const algorithmKey = "algo";
  static const multiplayerEloValue = "multiElo";
  static const openskillValue = "openskill";
  static const pointsValue = "points";

  String sportName;
  String name;
  RatingProjectSettings settings;
  final matches = IsarLinks<DbShootingMatch>;

  RatingProject({
    required this.sportName,
    required this.name,
    required this.settings,
  });

  RatingProject copy() {
    return RatingProject.fromJson(jsonDecode(this.toJson()));
  }

  factory RatingProject.fromJson(Map<String, dynamic> encodedProject) {
    var sportName = (encodedProject[_sportKey] ?? "uspsa") as String;
    var sport = SportRegistry().lookup(sportName)!;
    var combineOpenPCC = (encodedProject[_combineOpenPCCKey] ?? false) as bool;
    var combineLocap = (encodedProject[_combineLocapKey] ?? true) as bool;

    List<RaterGroup> groups;
    if(!encodedProject.containsKey(_groupsKey)) {
      LimLoCoCombination limLoCoMode;
      if(encodedProject.containsKey(_combineLimitedCOKey)) {
        // old project
        var combineLimitedCO = (encodedProject[_combineLimitedCOKey] ?? false) as bool;
        if(combineLimitedCO) {
          limLoCoMode = LimLoCoCombination.limCo;
        }
        else {
          limLoCoMode = LimLoCoCombination.none;
        }
      }
      else {
        limLoCoMode = LimLoCoCombination.values.byName(encodedProject[_limitedLoCoCombineModeKey] ?? LimLoCoCombination.none.name);
      }

      groups = RatingProjectSettings.groupsForSettings(
        combineOpenPCC: combineOpenPCC,
        limLoCo: limLoCoMode,
        combineLocap: combineLocap,
      );
    }
    else {
      groups = []..addAll(((encodedProject[_groupsKey] ?? []) as List<dynamic>).map((s) => RaterGroup.values.byName(s)));
    }

    var algorithmName = (encodedProject[algorithmKey] ?? multiplayerEloValue) as String;
    var algorithm = algorithmForName(algorithmName, encodedProject);

    var recognizedDivisions = <String, List<Division>>{};
    var recDivJson = (encodedProject[_recognizedDivisionsKey] ?? <String, dynamic>{}) as Map<String, dynamic>;
    for(var key in recDivJson.keys) {
      recognizedDivisions[key] = []..addAll(((recDivJson[key] ?? []) as List<dynamic>).map((s) => sport.divisions.lookupByName(s as String)!));
    }

    var settings = RatingProjectSettings(
      algorithm: algorithm,
      checkDataEntryErrors: (encodedProject[_checkDataEntryKey] ?? true) as bool,
      preserveHistory: encodedProject[_keepHistoryKey] as bool,
      groups: groups,
      memberNumberWhitelist: ((encodedProject[_whitelistKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      shooterAliases: ((encodedProject[_aliasesKey] ?? defaultShooterAliases) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      userMemberNumberMappings: ((encodedProject[_memberNumberMappingsKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      memberNumberMappingBlacklist: ((encodedProject[_memberNumberMappingBlacklistKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
          MapEntry(k, v as String)
      ),
      hiddenShooters: ((encodedProject[_hiddenShootersKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      memberNumberCorrections: MemberNumberCorrectionContainer.fromJson((encodedProject[_memberNumberCorrectionsKey] ?? []) as List<dynamic>),
      recognizedDivisions: recognizedDivisions,
    );
    var matchUrls = (encodedProject[_urlsKey] as List<dynamic>).map((item) => item as String).toList();
    var name = encodedProject[_nameKey] as String;

    var rp = RatingProject(sportName: sportName, name: name, settings: settings);
    return rp;
  }

  static RatingSystem algorithmForName(String name, Map<String, dynamic> encodedProject) {
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
    settings.encodeToJson(map);

    var encoded = jsonEncode(map);
    return encoded;
  }
}

enum LimLoCoCombination {
  none,
  limCo,
  limLo,
  loCo,
  all;

  List<RaterGroup> groups() {
    switch(this) {
      case LimLoCoCombination.none:
        return [
          RaterGroup.limited,
          RaterGroup.carryOptics,
          RaterGroup.limitedOptics,
        ];
      case LimLoCoCombination.limCo:
        return [
          RaterGroup.limitedCO,
          RaterGroup.limitedOptics,
        ];
      case LimLoCoCombination.limLo:
        return [
          RaterGroup.limitedLO,
          RaterGroup.carryOptics,
        ];
      case LimLoCoCombination.loCo:
        return [
          RaterGroup.limOpsCO,
          RaterGroup.limited,
        ];
      case LimLoCoCombination.all:
        return [
          RaterGroup.limLoCo,
        ];
    }
  }

  static LimLoCoCombination fromGroups(List<RaterGroup> groups) {
    if(groups.contains(RaterGroup.limLoCo)) {
      return LimLoCoCombination.all;
    }
    else if(groups.contains(RaterGroup.limOpsCO)) {
      return LimLoCoCombination.loCo;
    }
    else if(groups.contains(RaterGroup.limitedLO)) {
      return LimLoCoCombination.limLo;
    }
    else if(groups.contains(RaterGroup.limitedCO)) {
      return LimLoCoCombination.limCo;
    }
    else {
      return none;
    }
  }

  String get uiLabel {
    switch(this) {

      case LimLoCoCombination.none:
        return "All separate";
      case LimLoCoCombination.limCo:
        return "Combine LIM/CO";
      case LimLoCoCombination.limLo:
        return "Combine LIM/LO";
      case LimLoCoCombination.loCo:
        return "Combine LO/CO";
      case LimLoCoCombination.all:
        return "Combine all";
    }
  }
}

class RatingProjectSettings {
  // All of the below are serialized
  bool get byStage => algorithm.byStage;
  bool preserveHistory;

  /// If true, ignore data entry errors for this run only.
  bool transientDataEntryErrorSkip;

  bool checkDataEntryErrors;
  List<RaterGroup> groups;
  List<String> memberNumberWhitelist;
  late MemberNumberCorrectionContainer memberNumberCorrections;

  RatingSystem algorithm;
  /// A map of shooter name changes, used to backstop automatic shooter number change detection.
  ///
  /// Number change detection looks through a map of shooters-to-member-numbers after adding
  /// shooters, and tries to determine if any name maps to more than one member number. If it
  /// does, the rater combines the two ratings.
  Map<String, String> shooterAliases;

  /// A map of user-specified member number mappings. Should be in [Rater.processMemberNumber] format.
  ///
  /// Mappings may be made in either direction, but will preferentially be made from key to value:
  /// map[A1234] = L123 will try to map A1234 to L123 first. If L123 has rating events but A1234 doesn't,
  /// when both numbers are encountered for the first time, it will make the mapping in the other direction.
  Map<String, String> userMemberNumberMappings;

  /// A map of member number mappings that should _not_ be made automatically.
  ///
  /// If a candidate member number change appears in this map, in either direction
  /// (i.e., map[old] = new or map[new] = old), the shooter ratings corresponding
  /// to those numbers will not be merged.
  ///
  /// Should be in [Rater.processMemberNumber] format.
  Map<String, String> memberNumberMappingBlacklist;

  /// A list of shooters to hide from the rating display, based on member number.
  ///
  /// They are still used to calculate ratings, but not shown in the UI or exported
  /// to CSV, so that users can generate e.g. a club or section leaderboard, without
  /// having a bunch of traveling L2 shooters in the mix.
  ///
  /// Should be in [Rater.processMemberNumber] format.
  List<String> hiddenShooters;

  /// A list of match IDs that only recognize certain divisions, mapped to the divisions
  /// they recognize.
  ///
  /// If a match ID occurs in the keys of this map, then only the divisions in the associated
  /// entry will be used for rating updates. Use it so JJ doesn't get a huge Open boost from
  /// winning Open at Prod/PCC Nationals, or other similar cases.
  ///
  /// Match IDs should be PracticalMatch.practiscoreId.
  Map<String, List<Division>> recognizedDivisions;

  RatingProjectSettings({
    this.preserveHistory = false,
    this.checkDataEntryErrors = true,
    this.transientDataEntryErrorSkip = false,
    this.groups = const [RaterGroup.open, RaterGroup.limited, RaterGroup.pcc, RaterGroup.carryOptics, RaterGroup.locap],
    required this.algorithm,
    this.memberNumberWhitelist = const [],
    this.shooterAliases = defaultShooterAliases,
    this.userMemberNumberMappings = const {},
    this.memberNumberMappingBlacklist = const {},
    this.hiddenShooters = const [],
    this.recognizedDivisions = const {
      "433b1840-0e57-4397-8dae-1107bfe468a7": [uspsaProduction, uspsaPcc],
    },
    MemberNumberCorrectionContainer? memberNumberCorrections
  }) {
    if(memberNumberCorrections != null) this.memberNumberCorrections = memberNumberCorrections;
    else this.memberNumberCorrections = MemberNumberCorrectionContainer();
  }

  void encodeToJson(Map<String, dynamic> map) {
    map[_checkDataEntryKey] = checkDataEntryErrors;
    map[_keepHistoryKey] = preserveHistory;
    map[_whitelistKey] = memberNumberWhitelist;
    map[_aliasesKey] = shooterAliases;
    map[_memberNumberMappingsKey] = userMemberNumberMappings;
    map[_memberNumberMappingBlacklistKey] = memberNumberMappingBlacklist;
    map[_hiddenShootersKey] = hiddenShooters;
    map[_memberNumberCorrectionsKey] = memberNumberCorrections.toJson();
    map[_recognizedDivisionsKey] = <String, dynamic>{}..addEntries(recognizedDivisions.entries.map((e) =>
        MapEntry(e.key, e.value.map((e) => e.name).toList())
    ));
    map[_groupsKey] = groups.map((e) => e.name).toList();

    /// Alg-specific settings
    algorithm.encodeToJson(map);
  }

  factory RatingProjectSettings.decodeFromJson(Sport sport, RatingSystem algorithm, Map<String, dynamic> encodedProject) {
    Map<String, List<Division>> recognizedDivisions = {};
    var recDivJson = (encodedProject[_recognizedDivisionsKey] ?? <String, dynamic>{}) as Map<String, dynamic>;
    for(var key in recDivJson.keys) {
      recognizedDivisions[key] = []..addAll(((recDivJson[key] ?? []) as List<dynamic>).map((s) => sport.divisions.lookupByName(s as String)!));
    }

    return RatingProjectSettings(
      algorithm: algorithm,
      checkDataEntryErrors: (encodedProject[_checkDataEntryKey] ?? true) as bool,
      preserveHistory: encodedProject[_keepHistoryKey] as bool,
      groups: [], // stored in DB
      memberNumberWhitelist: ((encodedProject[_whitelistKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      shooterAliases: ((encodedProject[_aliasesKey] ?? defaultShooterAliases) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      userMemberNumberMappings: ((encodedProject[_memberNumberMappingsKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      memberNumberMappingBlacklist: ((encodedProject[_memberNumberMappingBlacklistKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      hiddenShooters: ((encodedProject[_hiddenShootersKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      memberNumberCorrections: MemberNumberCorrectionContainer.fromJson((encodedProject[_memberNumberCorrectionsKey] ?? []) as List<dynamic>),
      recognizedDivisions: recognizedDivisions,
    );
  }

  void applyFix(CollisionFix fix) {
    switch(fix.action) {
      case CollisionFixAction.mapping:
        userMemberNumberMappings[fix.memberNumber1] = fix.memberNumber2;
        break;
      case CollisionFixAction.blacklist:
        memberNumberMappingBlacklist[fix.memberNumber1] = fix.memberNumber2;
        break;
      case CollisionFixAction.dataFix:
        memberNumberCorrections.add(MemberNumberCorrection(
            name: fix.name1!,
            invalidNumber: fix.memberNumber1,
            correctedNumber: fix.memberNumber2
        ));
        break;
      case CollisionFixAction.abort:
        throw StateError("can't apply 'abort'");
      case CollisionFixAction.skipRemainingDataErrors:
        transientDataEntryErrorSkip = true;
        break;
    }
  }

  static List<RaterGroup> groupsForSettings({bool combineOpenPCC = false, LimLoCoCombination limLoCo = LimLoCoCombination.none, bool combineLocap = true}) {
    var groups = <RaterGroup>[];

    if(combineOpenPCC) groups.add(RaterGroup.openPcc);
    else groups.addAll([RaterGroup.open, RaterGroup.pcc]);

    groups.addAll(limLoCo.groups());

    if(combineLocap) groups.add(RaterGroup.locap);
    else groups.addAll([RaterGroup.production, RaterGroup.singleStack, RaterGroup.revolver, RaterGroup.limited10]);

    return groups;
  }
}