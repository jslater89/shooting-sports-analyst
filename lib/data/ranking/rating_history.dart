import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/member_number_correction.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_error.dart';
import 'package:uspsa_result_viewer/data/ranking/timings.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/filter_dialog.dart';
import 'package:uspsa_result_viewer/data/ranking/shooter_aliases.dart' as defaultAliases;
import 'package:uspsa_result_viewer/ui/widget/dialog/member_number_collision_dialog.dart';

/// RatingHistory turns a sequence of [PracticalMatch]es into a series of
/// [Rater]s.
class RatingHistory {
  /// The [PracticalMatch]es this rating history contains
  List<PracticalMatch> _matches;
  List<PracticalMatch> get matches {
    if(_settings.preserveHistory) {
      return []..addAll(_matches);
    }
    else {
      return [_matches.last];
    }
  }

  List<PracticalMatch> get allMatches {
      return []..addAll(_matches);
  }

  late RatingHistorySettings _settings;
  RatingHistorySettings get settings => _settings;

  // Prime, so we skip around the list better
  static const int progressCallbackInterval = 7;

  List<RaterGroup> get groups => []..addAll(_settings.groups);

  late RatingProject project;
  bool verbose;

  /// Maps matches to a map of [Rater]s, which hold the incremental ratings
  /// after that match has been processed.
  Map<PracticalMatch, Map<RaterGroup, Rater>> _ratersByDivision = {};

  Future<void> Function(int currentSteps, int totalSteps, String? eventName)? progressCallback;

  RatingHistory({RatingProject? project, required List<PracticalMatch> matches, this.progressCallback, this.verbose = true}) : this._matches = matches {
    project ??= RatingProject(name: "Unnamed Project", settings: RatingHistorySettings(
      algorithm: MultiplayerPercentEloRater(settings: EloSettings(
        byStage: true,
      )),
    ), matchUrls: matches.map((m) => m.practiscoreId).toList());

    this.project = project;
    _settings = project.settings;
  }

  void resetRaters() {
    _lastMatch = null;
    _ratersByDivision.clear();
  }

  void applyFix(CollisionFix fix) {
    _settings.applyFix(fix);
  }

  Future<RatingResult> processInitialMatches() async {
    if(_ratersByDivision.length > 0) throw StateError("Called processInitialMatches twice");
    return _processInitialMatches();
  }

  void loadRatings(Map<RaterGroup, Rater> ratings) {
    _ratersByDivision[_matches.last] = ratings;
  }
  
  // Returns false if the match already exists
  Future<bool> addMatch(PracticalMatch match) async {
    if(matches.contains(match)) return false;

    var oldMatch = _lastMatch;
    _matches.add(match);
    project.matchUrls.add("https://practiscore.com/results/new/${match.practiscoreId}");

    for(var group in _settings.groups) {
      var raters = _ratersByDivision[oldMatch]!;
      var rater = raters[group]!;

      _lastMatch = match;
      _ratersByDivision[_lastMatch!] ??= {};
      var newRater = Rater.copy(rater);
      newRater.addMatch(match);
      _ratersByDivision[_lastMatch]![group] = newRater;
    }

    if(!_settings.preserveHistory) {
      _ratersByDivision.remove(oldMatch);
    }

    return true;
  }

  Rater raterFor(PracticalMatch match, RaterGroup group) {
    if(!_settings.groups.contains(group)) throw ArgumentError("Invalid group");
    if(!_matches.contains(match)) throw ArgumentError("Invalid match");

    var raters = _ratersByDivision[match]!;
    return raters[group]!;
  }

  int countUniqueShooters() {
    Set<String> memberNumbers = <String>{};
    for(var group in _settings.groups) {
      var rater = _ratersByDivision[_matches.last]![group]!;
      for(var num in rater.knownShooters.keys) {
        memberNumbers.add(num);
      }
    }

    return memberNumbers.length;
  }

  /// Used to key the matches map for online match-adding
  PracticalMatch? _lastMatch;
  
  Future<RatingResult> _processInitialMatches() async {
    if(verbose) debugPrint("Loading matches");

    int stepsFinished = 0;

    _matches.sort((a, b) {
      if(a.date == null && b.date == null) {
        return 0;
      }
      if(a.date == null) return -1;
      if(b.date == null) return 1;

      return a.date!.compareTo(b.date!);
    });

    var currentMatches = <PracticalMatch>[];

    await progressCallback?.call(0, 1, null);

    if(_settings.preserveHistory) {
      int totalSteps = ((_settings.groups.length * _matches.length) / progressCallbackInterval).round();

      if(verbose) print("Total steps, history preserved: $totalSteps on ${_matches.length} matches and ${_settings.groups.length} groups");

      for (PracticalMatch match in _matches) {
        var m = match;
        currentMatches.add(m);
        debugPrint("Considering match ${m.name}");
        var innerMatches = <PracticalMatch>[]..addAll(currentMatches);
        _ratersByDivision[m] ??= {};
        for (var group in _settings.groups) {
          var divisionMap = <Division, bool>{};
          group.divisions.forEach((element) => divisionMap[element] = true);

          if (_lastMatch == null) {
            var r = _raterForGroup(innerMatches, group);
            // r.addAndDeduplicateShooters(_matches);
            _ratersByDivision[m]![group] = r;

            var result = await r.calculateInitialRatings();
            if(result.isErr()) return result;

            if(Timings.enabled) print("Timings for $group: ${r.timings}");

            stepsFinished += 1;
            if(stepsFinished % progressCallbackInterval == 0) {
              await progressCallback?.call(stepsFinished ~/ progressCallbackInterval, totalSteps, "${group.uiLabel} - ${m.name}");
            }
          }
          else {
            Rater newRater = Rater.copy(_ratersByDivision[_lastMatch]![group]!);
            var result = newRater.addMatch(m);
            if(result.isErr()) return result;

            _ratersByDivision[m]![group] = newRater;

            stepsFinished += 1;
            if(stepsFinished % progressCallbackInterval == 0) {
              await progressCallback?.call(stepsFinished ~/ progressCallbackInterval, totalSteps, "${group.uiLabel} - ${m.name}");
            }
          }
        }

        _lastMatch = m;
      }
    }
    else {
      int totalSteps = ((_settings.groups.length * _matches.length) / progressCallbackInterval).round();

      if(verbose) debugPrint("Total steps, history discarded: $totalSteps");

      _lastMatch = _matches.last;
      _ratersByDivision[_lastMatch!] ??= {};

      for (var group in _settings.groups) {
        var r = _raterForGroup(_matches, group, (_1, _2, eventName) async {
          stepsFinished += 1;
          await progressCallback?.call(stepsFinished, totalSteps, "${group.uiLabel} - $eventName");
        });
        var result = await r.calculateInitialRatings();
        if(result.isErr()) return result;
        _ratersByDivision[_lastMatch]![group] = r;
        if(Timings.enabled) print("Timings for $group: ${r.timings}");
      }
    }

    int stageCount = 0;
    // int scoreCount = 0;
    for(var m in _matches) {
      stageCount += m.stages.length;
      // scoreCount += m.getScores().length;
    }
    print("Total of ${countUniqueShooters()} shooters, ${_matches.length} matches, and $stageCount stages");
    return RatingResult.ok();
  }
  
  Rater _raterForGroup(List<PracticalMatch> matches, RaterGroup group, [Future<void> Function(int, int, String?)? progressCallback]) {
    var divisionMap = <Division, bool>{};
    group.divisions.forEach((element) => divisionMap[element] = true);
    Timings().reset();
    var r = Rater(
      matches: matches,
      ratingSystem: _settings.algorithm,
      byStage: _settings.byStage,
      checkDataEntryErrors: _settings.checkDataEntryErrors && !_settings.transientDataEntryErrorSkip,
      filters: group.filters,
      progressCallback: progressCallback,
      progressCallbackInterval: progressCallbackInterval,
      shooterAliases: _settings.shooterAliases,
      memberNumberMappingBlacklist: _settings.memberNumberMappingBlacklist,
      userMemberNumberMappings: _settings.userMemberNumberMappings,
      dataCorrections: _settings.memberNumberCorrections,
      recognizedDivisions: _settings.recognizedDivisions,
      verbose: verbose,
    );

    return r;
  }
}

enum RaterGroup {
  open,
  limited,
  pcc,
  carryOptics,
  limitedOptics,
  singleStack,
  production,
  limited10,
  revolver,
  locap,
  openPcc,
  limitedCO,
  limitedLO,
  limOpsCO,
  limLoCo;

  FilterSet get filters {
    return FilterSet(
      empty: true,
    )
      ..mode = FilterMode.or
      ..divisions = divisionMap
      ..reentries = false
      ..scoreDQs = false;
  }

  Map<Division, bool> get divisionMap {
    var divisionMap = <Division, bool>{};
    divisions.forEach((element) => divisionMap[element] = true);
    return divisionMap;
  }

  List<Division> get divisions {
    switch(this) {
      case RaterGroup.open:
        return [Division.open];
      case RaterGroup.limited:
        return [Division.limited];
      case RaterGroup.pcc:
        return [Division.pcc];
      case RaterGroup.carryOptics:
        return [Division.carryOptics];
      case RaterGroup.locap:
        return [Division.singleStack, Division.limited10, Division.production, Division.revolver];
      case RaterGroup.singleStack:
        return [Division.singleStack];
      case RaterGroup.production:
        return [Division.production];
      case RaterGroup.limited10:
        return [Division.limited10];
      case RaterGroup.revolver:
        return [Division.revolver];
      case RaterGroup.openPcc:
        return [Division.open, Division.pcc];
      case RaterGroup.limitedCO:
        return [Division.limited, Division.carryOptics];
      case RaterGroup.limitedOptics:
        return [Division.limitedOptics];
      case RaterGroup.limOpsCO:
        return [Division.limitedOptics, Division.carryOptics];
      case RaterGroup.limLoCo:
        return [Division.limited, Division.carryOptics, Division.limitedOptics];
      case RaterGroup.limitedLO:
        return [Division.limited, Division.limitedOptics];
    }
  }

  String get uiLabel {
    switch(this) {
      case RaterGroup.open:
        return "Open";
      case RaterGroup.limited:
        return "Limited";
      case RaterGroup.pcc:
        return "PCC";
      case RaterGroup.carryOptics:
        return "Carry Optics";
      case RaterGroup.singleStack:
        return "Single Stack";
      case RaterGroup.production:
        return "Production";
      case RaterGroup.limited10:
        return "Limited 10";
      case RaterGroup.revolver:
        return "Revolver";
      case RaterGroup.locap:
        return "Locap";
      case RaterGroup.openPcc:
        return "Open/PCC";
      case RaterGroup.limitedCO:
        return "Limited/CO";
      case RaterGroup.limitedOptics:
        return "Limited Optics";
      case RaterGroup.limOpsCO:
        return "LO/CO";
      case RaterGroup.limLoCo:
        return "LO/CO/Limited";
      case RaterGroup.limitedLO:
        return "Limited/LO";
    }
  }
}

class RatingHistorySettings {
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

  RatingHistorySettings({
    this.preserveHistory = false,
    this.checkDataEntryErrors = true,
    this.transientDataEntryErrorSkip = false,
    this.groups = const [RaterGroup.open, RaterGroup.limited, RaterGroup.pcc, RaterGroup.carryOptics, RaterGroup.locap],
    required this.algorithm,
    this.memberNumberWhitelist = const [],
    this.shooterAliases = defaultAliases.defaultShooterAliases,
    this.userMemberNumberMappings = const {},
    this.memberNumberMappingBlacklist = const {},
    this.hiddenShooters = const [],
    this.recognizedDivisions = const {
      "433b1840-0e57-4397-8dae-1107bfe468a7": [Division.production, Division.pcc],
    },
    MemberNumberCorrectionContainer? memberNumberCorrections
  }) {
    if(memberNumberCorrections != null) this.memberNumberCorrections = memberNumberCorrections;
    else this.memberNumberCorrections = MemberNumberCorrectionContainer();
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