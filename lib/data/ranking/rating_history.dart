/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/member_number_collision_dialog.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart' as old;
import 'package:shooting_sports_analyst/data/match/shooter.dart' as olds;

var _log = SSALogger("RatingHistory");

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
  List<ShootingMatch> ongoingMatches;

  List<ShootingMatch> get allMatches {
      return []..addAll(_matches);
  }

  late RatingProjectSettings _settings;
  RatingProjectSettings get settings => _settings;

  // Prime, so we skip around the list better
  static const int progressCallbackInterval = 7;

  List<RatingGroup> get groups => []..addAll(project.groups);

  late DbRatingProject project;
  bool verbose;

  /// Maps matches to a map of [Rater]s, which hold the incremental ratings
  /// after that match has been processed.
  Map<ShootingMatch, Map<RatingGroup, Rater>> _ratersByDivision = {};

  Future<void> Function(int currentSteps, int totalSteps, String? eventName)? progressCallback;

  RatingHistory({
    required this.sport,
    DbRatingProject? project,
    required List<ShootingMatch> matches,
    required this.ongoingMatches,
    this.progressCallback,
    this.verbose = true
  }) : this._matches = matches {
    project ??= DbRatingProject(
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

  void loadRatings(Map<RatingGroup, Rater> ratings) {
    _ratersByDivision[_matches.last] = ratings;
  }
  
  // Returns false if the match already exists in the project,
  // or doesn't exist in the DB.
  Future<bool> addMatch(ShootingMatch match) async {
    var dbMatch = await AnalystDatabase().getMatchByAnySourceId(match.sourceIds);
    if(dbMatch == null) return false;

    if(matches.contains(match)) return false;

    var oldMatch = _lastMatch;
    _matches.add(match);
    if(!project.matches.isLoaded) {
      await project.matches.load();
    }
    project.matches.add(dbMatch);
    await project.matches.save();

    for(var group in project.groups) {
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

  Rater latestRaterFor(RatingGroup group) {
    if(!project.groups.contains(group)) throw ArgumentError("Invalid group");
    var raters = _ratersByDivision[matches.last]!;

    return raters[group]!;
  }

  Rater raterFor(ShootingMatch match, RatingGroup group) {
    if(!project.groups.contains(group)) throw ArgumentError("Invalid group");
    if(!_matches.contains(match)) throw ArgumentError("Invalid match");

    var raters = _ratersByDivision[match]!;
    return raters[group]!;
  }

  int countUniqueShooters() {
    Set<String> memberNumbers = <String>{};
    for(var group in project.groups) {
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
      int totalSteps = ((project.groups.length * _matches.length) / progressCallbackInterval).round();

      if(verbose) _log.v("Total steps, history preserved: $totalSteps on ${_matches.length} matches and ${project.groups.length} groups");

      for (ShootingMatch match in _matches) {
        var m = match;
        currentMatches.add(m);
        _log.d("Considering match ${m.name}");
        var innerMatches = <ShootingMatch>[]..addAll(currentMatches);
        _ratersByDivision[m] ??= {};
        for (var group in project.groups) {
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
      int totalSteps = ((project.groups.length * _matches.length) / progressCallbackInterval).round();

      if(verbose) _log.v("Total steps, history discarded: $totalSteps");

      _lastMatch = _matches.last;
      _ratersByDivision[_lastMatch!] ??= {};

      for (var group in project.groups) {
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
  
  Rater _raterForGroup(List<ShootingMatch> matches, RatingGroup group, [Future<void> Function(int, int, String?)? progressCallback]) {
    var divisionMap = <Division, bool>{};
    group.divisions.forEach((element) => divisionMap[element] = true);
    Timings().reset();
    var r = Rater(
      sport: sport,
      matches: matches,
      ongoingMatches: ongoingMatches,
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

  old.OldFilterSet get filters {
    return old.OldFilterSet(
      empty: true,
    )
      ..mode = FilterMode.or
      ..divisions = divisionMap
      ..reentries = false
      ..scoreDQs = false;
  }

  Map<olds.Division, bool> get divisionMap {
    var divisionMap = <olds.Division, bool>{};
    divisions.forEach((element) => divisionMap[element] = true);
    return divisionMap;
  }

  List<olds.Division> get divisions {
    switch(this) {
      case OldRaterGroup.open:
        return [olds.Division.open];
      case OldRaterGroup.limited:
        return [olds.Division.limited];
      case OldRaterGroup.pcc:
        return [olds.Division.pcc];
      case OldRaterGroup.carryOptics:
        return [olds.Division.carryOptics];
      case OldRaterGroup.locap:
        return [olds.Division.singleStack, olds.Division.limited10, olds.Division.production, olds.Division.revolver];
      case OldRaterGroup.singleStack:
        return [olds.Division.singleStack];
      case OldRaterGroup.production:
        return [olds.Division.production];
      case OldRaterGroup.limited10:
        return [olds.Division.limited10];
      case OldRaterGroup.revolver:
        return [olds.Division.revolver];
      case OldRaterGroup.openPcc:
        return [olds.Division.open, olds.Division.pcc];
      case OldRaterGroup.limitedCO:
        return [olds.Division.limited, olds.Division.carryOptics];
      case OldRaterGroup.limitedOptics:
        return [olds.Division.limitedOptics];
      case OldRaterGroup.limOpsCO:
        return [olds.Division.limitedOptics, olds.Division.carryOptics];
      case OldRaterGroup.limLoCo:
        return [olds.Division.limited, olds.Division.carryOptics, olds.Division.limitedOptics];
      case OldRaterGroup.limitedLO:
        return [olds.Division.limited, olds.Division.limitedOptics];
      case OldRaterGroup.opticHandguns:
        return [olds.Division.open, olds.Division.carryOptics, olds.Division.limitedOptics];
      case OldRaterGroup.ironsHandguns:
        return [olds.Division.limited, olds.Division.production, olds.Division.singleStack, olds.Division.revolver, olds.Division.limited10];
      case OldRaterGroup.combined:
        return olds.Division.values;
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
    }
  }
}