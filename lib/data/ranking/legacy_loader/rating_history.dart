// ignore_for_file: unused_local_variable

/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/old_rating_project.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/logger.dart';
// import 'package:shooting_sports_analyst/ui/widget/dialog/member_number_collision_dialog.dart';

var _log = SSALogger("RatingHistory");

/// RatingHistory turns a sequence of [PracticalMatch]es into a series of
/// [Rater]s.
class OldRatingHistory {
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
  List<PracticalMatch> ongoingMatches;

  List<PracticalMatch> get allMatches {
      return []..addAll(_matches);
  }

  late OldRatingProjectSettings _settings;
  OldRatingProjectSettings get settings => _settings;

  // Prime, so we skip around the list better
  static const int progressCallbackInterval = 7;

  List<OldRaterGroup> get groups => []..addAll(_settings.groups);

  late OldRatingProject project;
  bool verbose;

  /// Maps matches to a map of [Rater]s, which hold the incremental ratings
  /// after that match has been processed.
  Map<PracticalMatch, Map<OldRaterGroup, Rater>> _ratersByDivision = {};

  Future<void> Function(int currentSteps, int totalSteps, String? eventName)? progressCallback;

  OldRatingHistory({
    OldRatingProject? project,
    required List<PracticalMatch> matches,
    this.progressCallback,
    this.verbose = true,
    required this.ongoingMatches,
  }) : this._matches = matches {
    project ??= OldRatingProject(
      name: "Unnamed Project",
      settings: OldRatingProjectSettings(
        algorithm: MultiplayerPercentEloRater(settings: EloSettings(
          byStage: true,
        )),
      ),
      matchUrls: matches.map((m) => m.practiscoreId).toList(),
      ongoingMatchUrls: ongoingMatches.map((m) => m.practiscoreId).toList()
    );

    this.project = project;
    _settings = project.settings;
  }

  void resetRaters() {
    _lastMatch = null;
    _ratersByDivision.clear();
  }

  Future<RatingResult> processInitialMatches() async {
    if(_ratersByDivision.length > 0) throw StateError("Called processInitialMatches twice");
    return _processInitialMatches();
  }

  void loadRatings(Map<OldRaterGroup, Rater> ratings) {
    _ratersByDivision[_matches.last] = ratings;
  }

  // Returns false if the match already exists
  Future<bool> addMatch(PracticalMatch match) async {
    if(matches.contains(match)) return false;

    var oldMatch = _lastMatch;
    _matches.add(match);
    project.matchUrls.add("https://practiscore.com/results/new/${match.practiscoreId}");

    for(var group in _settings.groups) {
      // var raters = _ratersByDivision[oldMatch]!;
      // var rater = raters[group]!;

      // _lastMatch = match;
      // _ratersByDivision[_lastMatch!] ??= {};
      // var newRater = Rater.copy(rater);
      // newRater.addMatch(match);
      // _ratersByDivision[_lastMatch]![group] = newRater;
    }

    if(!_settings.preserveHistory) {
      _ratersByDivision.remove(oldMatch);
    }

    return true;
  }

  Rater latestRaterFor(OldRaterGroup group) {
    if(!_settings.groups.contains(group)) throw ArgumentError("Invalid group");
    var raters = _ratersByDivision[matches.last]!;

    return raters[group]!;
  }

  Rater raterFor(PracticalMatch match, OldRaterGroup group) {
    if(!_settings.groups.contains(group)) throw ArgumentError("Invalid group");
    if(!_matches.contains(match)) throw ArgumentError("Invalid match");

    var raters = _ratersByDivision[match]!;
    return raters[group]!;
  }

  int countUniqueShooters() {
    Set<String> memberNumbers = <String>{};
    for(var group in _settings.groups) {
      // var rater = _ratersByDivision[_matches.last]![group]!;
      // for(var num in rater.knownShooters.keys) {
      //   memberNumbers.add(num);
      // }
    }

    return memberNumbers.length;
  }

  /// Used to key the matches map for online match-adding
  PracticalMatch? _lastMatch;

  Future<RatingResult> _processInitialMatches() async {
    if(verbose) _log.v("Loading matches");

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

      if(verbose) _log.v("Total steps, history preserved: $totalSteps on ${_matches.length} matches and ${_settings.groups.length} groups");

      for (PracticalMatch match in _matches) {
        var m = match;
        currentMatches.add(m);
        _log.d("Considering match ${m.name}");
        var innerMatches = <PracticalMatch>[]..addAll(currentMatches);
        _ratersByDivision[m] ??= {};
        for (var group in _settings.groups) {
          // var divisionMap = <Division, bool>{};
          // group.divisions.forEach((element) => divisionMap[element] = true);

          // if (_lastMatch == null) {
          //   var r = _raterForGroup(innerMatches, group);
          //   // r.addAndDeduplicateShooters(_matches);
          //   _ratersByDivision[m]![group] = r;

          //   var result = await r.calculateInitialRatings();
          //   if(result.isErr()) return result;

          //   if(Timings.enabled) _log.i("Timings for $group: ${r.timings}");

          //   stepsFinished += 1;
          //   if(stepsFinished % progressCallbackInterval == 0) {
          //     await progressCallback?.call(stepsFinished ~/ progressCallbackInterval, totalSteps, "${group.uiLabel} - ${m.name}");
          //   }
          // }
          // else {
          //   Rater newRater = Rater.copy(_ratersByDivision[_lastMatch]![group]!);
          //   var result = newRater.addMatch(m);
          //   if(result.isErr()) return result;

          //   _ratersByDivision[m]![group] = newRater;

          //   stepsFinished += 1;
          //   if(stepsFinished % progressCallbackInterval == 0) {
          //     await progressCallback?.call(stepsFinished ~/ progressCallbackInterval, totalSteps, "${group.uiLabel} - ${m.name}");
          //   }
          // }
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
        // var r = _raterForGroup(_matches, group, (_1, _2, eventName) async {
        //   stepsFinished += 1;
        //   await progressCallback?.call(stepsFinished, totalSteps, "${group.uiLabel} - $eventName");
        // });
        // var result = await r.calculateInitialRatings();
        // if(result.isErr()) return result;
        // _ratersByDivision[_lastMatch]![group] = r;
        // if(Timings.enabled) _log.i("Timings for $group: ${r.timings}");
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

  void _raterForGroup(List<PracticalMatch> matches, OldRaterGroup group, [Future<void> Function(int, int, String?)? progressCallback]) {
    throw UnimplementedError("OldRatingHistory._raterForGroup is no longer implemented");
  }
}

enum OldRaterGroup {
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
  tenRounds,
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
      case OldRaterGroup.open:
        return [Division.open];
      case OldRaterGroup.limited:
        return [Division.limited];
      case OldRaterGroup.pcc:
        return [Division.pcc];
      case OldRaterGroup.carryOptics:
        return [Division.carryOptics];
      case OldRaterGroup.locap:
        return [Division.singleStack, Division.limited10, Division.production, Division.revolver];
      case OldRaterGroup.singleStack:
        return [Division.singleStack];
      case OldRaterGroup.production:
        return [Division.production];
      case OldRaterGroup.limited10:
        return [Division.limited10];
      case OldRaterGroup.revolver:
        return [Division.revolver];
      case OldRaterGroup.openPcc:
        return [Division.open, Division.pcc];
      case OldRaterGroup.limitedCO:
        return [Division.limited, Division.carryOptics];
      case OldRaterGroup.limitedOptics:
        return [Division.limitedOptics];
      case OldRaterGroup.limOpsCO:
        return [Division.limitedOptics, Division.carryOptics];
      case OldRaterGroup.limLoCo:
        return [Division.limited, Division.carryOptics, Division.limitedOptics];
      case OldRaterGroup.limitedLO:
        return [Division.limited, Division.limitedOptics];
      case OldRaterGroup.opticHandguns:
        return [Division.open, Division.carryOptics, Division.limitedOptics];
      case OldRaterGroup.ironsHandguns:
        return [Division.limited, Division.production, Division.singleStack, Division.revolver, Division.limited10];
      case OldRaterGroup.combined:
        return Division.values;
      case OldRaterGroup.tenRounds:
        return [Division.singleStack, Division.revolver, Division.limited10];
    }
  }

  String get uiLabel {
    switch(this) {
      case OldRaterGroup.open:
        return "Open";
      case OldRaterGroup.limited:
        return "Limited";
      case OldRaterGroup.pcc:
        return "PCC";
      case OldRaterGroup.carryOptics:
        return "Carry Optics";
      case OldRaterGroup.singleStack:
        return "Single Stack";
      case OldRaterGroup.production:
        return "Production";
      case OldRaterGroup.limited10:
        return "Limited 10";
      case OldRaterGroup.revolver:
        return "Revolver";
      case OldRaterGroup.locap:
        return "Locap";
      case OldRaterGroup.openPcc:
        return "Open/PCC";
      case OldRaterGroup.limitedCO:
        return "Limited/CO";
      case OldRaterGroup.limitedOptics:
        return "Limited Optics";
      case OldRaterGroup.limOpsCO:
        return "LO/CO";
      case OldRaterGroup.limLoCo:
        return "LO/CO/Limited";
      case OldRaterGroup.limitedLO:
        return "Limited/LO";
      case OldRaterGroup.opticHandguns:
        return "Optic Handguns";
      case OldRaterGroup.ironsHandguns:
        return "Irons Handguns";
      case OldRaterGroup.combined:
        return "Combined";
      case OldRaterGroup.tenRounds:
        return "10-Round";
    }
  }
}

class Rater {
  // placeholder; legacy_loader doesn't need to actually calculate ratings,
  // just load projects for migration
}
