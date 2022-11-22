import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/timings.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/filter_dialog.dart';
import 'package:uspsa_result_viewer/data/ranking/shooter_aliases.dart' as defaultAliases;

/// RatingHistory turns a sequence of [HitFactorMatch]es into a series of
/// [Rater]s.
class RatingHistory {
  /// The [HitFactorMatch]es this rating history contains
  List<HitFactorMatch> _matches;
  List<HitFactorMatch> get matches {
    if(_settings.preserveHistory) {
      return []..addAll(_matches);
    }
    else {
      return [_matches.last];
    }
  }

  List<HitFactorMatch> get allMatches {
      return []..addAll(_matches);
  }

  late RatingHistorySettings _settings;

  /// Maps matches to a map of [Rater]s, which hold the incremental ratings
  /// after that match has been processed.
  Map<HitFactorMatch, Map<RaterGroup, Rater>> _ratersByDivision = {};

  Future<void> Function(int currentSteps, int totalSteps, String? eventName)? progressCallback;

  RatingHistory({required List<HitFactorMatch> matches, RatingHistorySettings? settings, this.progressCallback}) : this._matches = matches {
    if(settings != null) _settings = settings;
    else _settings = RatingHistorySettings(
      algorithm: MultiplayerPercentEloRater(settings: EloSettings(
        byStage: true,
      )),
    );
  }

  Future<void> processInitialMatches() async {
    if(_ratersByDivision.length > 0) throw StateError("Called processInitialMatches twice");
    return _processInitialMatches();
  }

  Rater raterFor(HitFactorMatch match, RaterGroup group) {
    if(!_settings.groups.contains(group)) throw ArgumentError("Invalid group");
    if(!_matches.contains(match)) throw ArgumentError("Invalid match");

    return _ratersByDivision[match]![group]!;
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

  Future<void> _processInitialMatches() async {
    debugPrint("Loading matches");

    int stepsFinished = 0;

    _matches.sort((a, b) {
      if(a.date == null && b.date == null) {
        return 0;
      }
      if(a.date == null) return -1;
      if(b.date == null) return 1;

      return a.date!.compareTo(b.date!);
    });

    var currentMatches = <HitFactorMatch>[];
    HitFactorMatch? lastMatch;

    await progressCallback?.call(0, 1, null);

    if(_settings.preserveHistory) {
      int totalSteps = matches.length * _settings.groups.length;

      // debugPrint("Total steps, history preserved: $totalSteps");

      for (HitFactorMatch match in _matches) {
        var m = match;
        currentMatches.add(m);
        debugPrint("Considering match ${m.name}");
        var innerMatches = <HitFactorMatch>[]..addAll(currentMatches);
        _ratersByDivision[m] ??= {};
        for (var group in _settings.groups) {
          var divisionMap = <USPSADivision, bool>{};
          group.divisions.forEach((element) => divisionMap[element] = true);

          if (lastMatch == null) {
            _ratersByDivision[m]![group] = await _raterForGroup(innerMatches, group);

            stepsFinished += 1;
            await progressCallback?.call(stepsFinished, totalSteps, "${group.uiLabel} - ${m.name}");
          }
          else {
            Rater newRater = Rater.copy(_ratersByDivision[lastMatch]![group]!);
            newRater.addMatch(m);
            _ratersByDivision[m]![group] = newRater;

            stepsFinished += 1;
            await progressCallback?.call(stepsFinished, totalSteps, "${group.uiLabel} - ${m.name}");
          }
        }

        lastMatch = m;
      }
    }
    else {
      int totalSteps = _settings.groups.length * _matches.length;

      // debugPrint("Total steps, history discarded: $totalSteps");

      var m = _matches.last;
      _ratersByDivision[m] ??= {};

      for (var group in _settings.groups) {
        _ratersByDivision[m]![group] = await _raterForGroup(_matches, group, (_1, _2, eventName) async {
          stepsFinished += 1;
          await progressCallback?.call(stepsFinished, totalSteps, "${group.uiLabel} - $eventName");
        });
      }
    }

    int stageCount = 0;
    // int scoreCount = 0;
    for(var m in _matches) {
      stageCount += m.stages.length;
      // scoreCount += m.getScores().length;
    }
    print("Total of ${countUniqueShooters()} shooters, ${_matches.length} matches, and $stageCount stages");
  }
  
  Future<Rater> _raterForGroup(List<HitFactorMatch> matches, RaterGroup group, [Future<void> Function(int, int, String?)? progressCallback]) async {
    var divisionMap = <USPSADivision, bool>{};
    group.divisions.forEach((element) => divisionMap[element] = true);
    Timings().reset();
    var r = Rater(
        matches: matches,
        ratingSystem: _settings.algorithm,
        byStage: _settings.byStage,
        filters: FilterSet(
          empty: true,
        )
          ..mode = FilterMode.or
          ..divisions = divisionMap
          ..reentries = false
          ..scoreDQs = false,
        progressCallback: progressCallback,
    );

    await r.calculateInitialRatings();

    if(Timings.enabled) print("Timings for $group: ${r.timings}");

    return r;
  }
}

enum RaterGroup {
  open,
  limited,
  pcc,
  carryOptics,
  singleStack,
  production,
  limited10,
  revolver,
  locap,
  openPcc,
  limitedCO,
}

extension RaterGroupUtilities on RaterGroup {
  List<USPSADivision> get divisions {
    switch(this) {
      case RaterGroup.open:
        return [USPSADivision.open];
      case RaterGroup.limited:
        return [USPSADivision.limited];
      case RaterGroup.pcc:
        return [USPSADivision.pcc];
      case RaterGroup.carryOptics:
        return [USPSADivision.carryOptics];
      case RaterGroup.locap:
        return [USPSADivision.singleStack, USPSADivision.limited10, USPSADivision.production, USPSADivision.revolver];
      case RaterGroup.singleStack:
        return [USPSADivision.singleStack];
      case RaterGroup.production:
        return [USPSADivision.production];
      case RaterGroup.limited10:
        return [USPSADivision.limited10];
      case RaterGroup.revolver:
        return [USPSADivision.revolver];
      case RaterGroup.openPcc:
        return [USPSADivision.open, USPSADivision.pcc];
      case RaterGroup.limitedCO:
        return [USPSADivision.limited, USPSADivision.carryOptics];
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
    }
  }
}

class RatingHistorySettings {
  bool get byStage => algorithm.byStage;
  bool preserveHistory;
  List<RaterGroup> groups;
  List<String> memberNumberWhitelist;
  RatingSystem algorithm;
  Map<String, String> shooterAliases;

  RatingHistorySettings({
    this.preserveHistory = false,
    this.groups = const [RaterGroup.open, RaterGroup.limited, RaterGroup.pcc, RaterGroup.carryOptics, RaterGroup.locap],
    required this.algorithm,
    this.memberNumberWhitelist = const [],
    this.shooterAliases = defaultAliases.defaultShooterAliases,
  });

  static List<RaterGroup> groupsForSettings({bool combineOpenPCC = false, bool combineLimitedCO = false, bool combineLocap = true}) {
    var groups = <RaterGroup>[];

    if(combineOpenPCC) groups.add(RaterGroup.openPcc);
    else groups.addAll([RaterGroup.open, RaterGroup.pcc]);

    if(combineLimitedCO) groups.add(RaterGroup.limitedCO);
    else groups.addAll([RaterGroup.limited, RaterGroup.carryOptics]);

    if(combineLocap) groups.add(RaterGroup.locap);
    else groups.addAll([RaterGroup.production, RaterGroup.singleStack, RaterGroup.revolver, RaterGroup.limited10]);

    return groups;
  }
}