/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart' as defaultAliases;
import 'package:shooting_sports_analyst/ui/widget/dialog/member_number_collision_dialog.dart';

var _log = SSALogger("RatingHistory");

/// RatingHistory turns a sequence of [PracticalMatch]es into a series of
/// [Rater]s.
class RatingHistory {
  Sport sport;

  /// The [ShootingMatch]es this rating history contains
  List<ShootingMatch> _matches;
  List<ShootingMatch> get matches {
    if(_settings.preserveHistory) {
      return []..addAll(_matches);
    }
    else {
      return [_matches.last];
    }
  }

  List<ShootingMatch> get allMatches {
      return []..addAll(_matches);
  }

  late RatingProjectSettings _settings;
  RatingProjectSettings get settings => _settings;

  // Prime, so we skip around the list better
  static const int progressCallbackInterval = 7;

  List<RaterGroup> get groups => []..addAll(_settings.groups);

  late RatingProject project;
  bool verbose;

  /// Maps matches to a map of [Rater]s, which hold the incremental ratings
  /// after that match has been processed.
  Map<ShootingMatch, Map<RaterGroup, Rater>> _ratersByDivision = {};

  Future<void> Function(int currentSteps, int totalSteps, String? eventName)? progressCallback;

  RatingHistory({
    required this.sport,
    RatingProject? project,
    required List<ShootingMatch> matches,
    this.progressCallback,
    this.verbose = true
  }) : this._matches = matches {
    project ??= RatingProject(
      sportName: sport.name,
      name: "Unnamed Project", settings: RatingProjectSettings(
      algorithm: MultiplayerPercentEloRater(settings: EloSettings(
        byStage: true,
      )),
    ));

    this.project = project;
    this.sport = this.project.sport;
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
  Future<bool> addMatch(ShootingMatch match) async {
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

  Rater latestRaterFor(RaterGroup group) {
    if(!_settings.groups.contains(group)) throw ArgumentError("Invalid group");
    var raters = _ratersByDivision[matches.last]!;

    return raters[group]!;
  }

  Rater raterFor(ShootingMatch match, RaterGroup group) {
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
  ShootingMatch? _lastMatch;
  
  Future<RatingResult> _processInitialMatches() async {
    if(verbose) _log.v("Loading matches");

    int stepsFinished = 0;

    _matches.sort((a, b) {
      return a.date.compareTo(b.date);
    });

    var currentMatches = <ShootingMatch>[];

    await progressCallback?.call(0, 1, null);

    if(_settings.preserveHistory) {
      int totalSteps = ((_settings.groups.length * _matches.length) / progressCallbackInterval).round();

      if(verbose) _log.v("Total steps, history preserved: $totalSteps on ${_matches.length} matches and ${_settings.groups.length} groups");

      for (ShootingMatch match in _matches) {
        var m = match;
        currentMatches.add(m);
        _log.d("Considering match ${m.name}");
        var innerMatches = <ShootingMatch>[]..addAll(currentMatches);
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

            if(Timings.enabled) _log.i("Timings for $group: ${r.timings}");

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

      if(verbose) _log.v("Total steps, history discarded: $totalSteps");

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
        if(Timings.enabled) _log.i("Timings for $group: ${r.timings}");
      }
    }

    int stageCount = 0;
    // int scoreCount = 0;
    for(var m in _matches) {
      stageCount += m.stages.length;
      // scoreCount += m.getScores().length;
    }
    _log.i("Total of ${countUniqueShooters()} shooters, ${_matches.length} matches, and $stageCount stages");
    return RatingResult.ok();
  }
  
  Rater _raterForGroup(List<ShootingMatch> matches, RaterGroup group, [Future<void> Function(int, int, String?)? progressCallback]) {
    var divisionMap = <Division, bool>{};
    group.divisions.forEach((element) => divisionMap[element] = true);
    Timings().reset();
    var r = Rater(
      sport: sport,
      matches: matches,
      ratingSystem: _settings.algorithm,
      byStage: _settings.byStage,
      checkDataEntryErrors: _settings.checkDataEntryErrors && !_settings.transientDataEntryErrorSkip,
      group: group,
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
  pcc,
  limited,
  carryOptics,
  limitedOptics,
  singleStack,
  production,
  revolver,
  limited10,
  locap,
  openPcc,
  limitedCO,
  limitedLO,
  limOpsCO,
  limLoCo,
  opticHandguns,
  ironsHandguns,
  combined;

  static get defaultGroups => [
    open,
    limited,
    pcc,
    carryOptics,
    limitedOptics,
    locap,
  ];

  static get divisionGroups => [
    open,
    limited,
    pcc,
    carryOptics,
    limitedOptics,
    singleStack,
    production,
    limited10,
    revolver,
  ];

  OldFilterSet get filters {
    return OldFilterSet(
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
      case RaterGroup.opticHandguns:
        return [Division.open, Division.carryOptics, Division.limitedOptics];
      case RaterGroup.ironsHandguns:
        return [Division.limited, Division.production, Division.singleStack, Division.revolver, Division.limited10];
      case RaterGroup.combined:
        return Division.values;
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
      case RaterGroup.opticHandguns:
        return "Optic Handguns";
      case RaterGroup.ironsHandguns:
        return "Irons Handguns";
      case RaterGroup.combined:
        return "Combined";
    }
  }
}