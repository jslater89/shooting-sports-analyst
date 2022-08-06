import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

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

  late RatingHistorySettings _settings;

  /// Maps matches to a map of [Rater]s, which hold the incremental ratings
  /// after that match has been processed.
  Map<PracticalMatch, Map<RaterGroup, Rater>> _ratersByDivision = {};

  Future<void> Function(int, int)? progressCallback;

  RatingHistory({required List<PracticalMatch> matches, RatingHistorySettings? settings, this.progressCallback}) : this._matches = matches {
    if(settings != null) _settings = settings;
    else _settings = RatingHistorySettings(algorithm: MultiplayerPercentEloRater());
  }

  Future<void> processInitialMatches() async {
    if(_ratersByDivision.length > 0) throw StateError("Called processInitialMatches twice");
    return _processInitialMatches();
  }

  Rater raterFor(PracticalMatch match, RaterGroup group) {
    if(!_settings.groups.contains(group)) throw ArgumentError("Invalid group");
    if(!_matches.contains(match)) throw ArgumentError("Invalid match");

    return _ratersByDivision[match]![group]!;
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

    var currentMatches = <PracticalMatch>[];
    PracticalMatch? lastMatch;

    await progressCallback?.call(0, 1);

    if(_settings.preserveHistory) {
      int totalSteps = matches.length * _settings.groups.length;

      // debugPrint("Total steps, history preserved: $totalSteps");

      for (PracticalMatch match in _matches) {
        var m = match;
        currentMatches.add(m);
        debugPrint("Considering match ${m.name}");
        var innerMatches = <PracticalMatch>[]..addAll(currentMatches);
        _ratersByDivision[m] ??= {};
        for (var group in _settings.groups) {
          var divisionMap = <Division, bool>{};
          group.divisions.forEach((element) => divisionMap[element] = true);

          if (lastMatch == null) {
            _ratersByDivision[m]![group] = await _raterForGroup(innerMatches, group);

            stepsFinished += 1;
            await progressCallback?.call(stepsFinished, totalSteps);
          }
          else {
            Rater newRater = Rater.copy(_ratersByDivision[lastMatch]![group]!);
            newRater.addMatch(m);
            _ratersByDivision[m]![group] = newRater;

            stepsFinished += 1;
            await progressCallback?.call(stepsFinished, totalSteps);
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
        _ratersByDivision[m]![group] = await _raterForGroup(_matches, group, (_1, _2) async {
          stepsFinished += 1;
          await progressCallback?.call(stepsFinished, totalSteps);
          debugPrint("$stepsFinished/$totalSteps");
        });
      }
    }
  }
  
  Future<Rater> _raterForGroup(List<PracticalMatch> matches, RaterGroup group, [Future<void> Function(int, int)? progressCallback]) async {
    var divisionMap = <Division, bool>{};
    group.divisions.forEach((element) => divisionMap[element] = true);
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
}

extension _InternalUtilities on RaterGroup {
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
      default:
        throw StateError("Missing case clause");
    }
  }
}

class RatingHistorySettings {
  bool byStage;
  bool preserveHistory;
  List<RaterGroup> groups;
  RatingSystem algorithm;

  RatingHistorySettings({
    this.byStage = false,
    this.preserveHistory = false,
    this.groups = const [RaterGroup.open, RaterGroup.limited, RaterGroup.pcc, RaterGroup.carryOptics, RaterGroup.locap],
    required this.algorithm,
  });
}