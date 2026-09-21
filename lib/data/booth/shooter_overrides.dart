/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("ShooterOverrides");

/// Copy [match] before a booth edit.
///
/// [AnalystDatabase.saveMatch] keeps the downloaded instance in the hydrated
/// match cache. Editing that instance would show the local power factor to
/// ratings, the result page, and anything else that reads the cache.
ShootingMatch copyMatchForLocalEdit(ShootingMatch match) {
  var copy = match.copy();
  copy.endDate = match.endDate;
  copy.sourceLastUpdated = match.sourceLastUpdated;
  return copy;
}

/// Local, match-scoped edits to competitor fields (power factor, division).
///
/// Broadcast refresh replaces the whole match from the server, so these
/// overrides are reapplied after every reload and persisted to disk.
class ShooterOverride {
  final String? sourceId;
  final int? entryId;
  final String? memberNumber;
  final String? firstName;
  final String? lastName;
  final String? powerFactorName;
  final String? divisionName;
  final String? originalPowerFactorName;
  final String? originalDivisionName;

  const ShooterOverride({
    this.sourceId,
    this.entryId,
    this.memberNumber,
    this.firstName,
    this.lastName,
    this.powerFactorName,
    this.divisionName,
    this.originalPowerFactorName,
    this.originalDivisionName,
  });

  bool get hasEdits => powerFactorName != null || divisionName != null;

  /// True when the stored power factor or division differs from the server values.
  bool get differsFromOriginal {
    var pfDiffers =
        powerFactorName != null && powerFactorName != originalPowerFactorName;
    var divDiffers =
        divisionName != null && divisionName != originalDivisionName;
    return pfDiffers || divDiffers;
  }

  factory ShooterOverride.fromJson(Map<String, dynamic> json) {
    return ShooterOverride(
      sourceId: json["sourceId"] as String?,
      entryId: json["entryId"] as int?,
      memberNumber: json["memberNumber"] as String?,
      firstName: json["firstName"] as String?,
      lastName: json["lastName"] as String?,
      powerFactorName: json["powerFactor"] as String?,
      divisionName: json["division"] as String?,
      originalPowerFactorName: json["originalPowerFactor"] as String?,
      originalDivisionName: json["originalDivision"] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (sourceId != null) "sourceId": sourceId,
      if (entryId != null) "entryId": entryId,
      if (memberNumber != null) "memberNumber": memberNumber,
      if (firstName != null) "firstName": firstName,
      if (lastName != null) "lastName": lastName,
      if (powerFactorName != null) "powerFactor": powerFactorName,
      if (divisionName != null) "division": divisionName,
      if (originalPowerFactorName != null)
        "originalPowerFactor": originalPowerFactorName,
      if (originalDivisionName != null)
        "originalDivision": originalDivisionName,
    };
  }

  bool matches(MatchEntry shooter) {
    if (sourceId != null &&
        sourceId!.isNotEmpty &&
        shooter.sourceId != null &&
        shooter.sourceId!.isNotEmpty) {
      return sourceId == shooter.sourceId;
    }
    if (entryId != null && entryId != 0 && shooter.entryId == entryId) {
      return true;
    }
    if (memberNumber != null &&
        memberNumber!.isNotEmpty &&
        shooter.memberNumber.isNotEmpty) {
      if (Shooter.normalizeNumber(memberNumber!) ==
          Shooter.normalizeNumber(shooter.memberNumber)) {
        return true;
      }
    }
    if (firstName != null && lastName != null) {
      return firstName!.toLowerCase() == shooter.firstName.toLowerCase() &&
          lastName!.toLowerCase() == shooter.lastName.toLowerCase();
    }
    return false;
  }

  ShooterOverride forShooter(MatchEntry shooter) {
    return ShooterOverride(
      sourceId: shooter.sourceId ?? sourceId,
      entryId: shooter.entryId,
      memberNumber: shooter.memberNumber.isNotEmpty
          ? shooter.memberNumber
          : memberNumber,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      powerFactorName: powerFactorName,
      divisionName: divisionName,
      originalPowerFactorName:
          originalPowerFactorName ?? shooter.powerFactor.name,
      originalDivisionName: originalDivisionName ?? shooter.division?.name,
    );
  }
}

class ShooterOverrideStore {
  static final ShooterOverrideStore instance = ShooterOverrideStore._();
  ShooterOverrideStore._();

  final Map<String, List<ShooterOverride>> _byMatch = {};
  Future<void>? _loadFuture;

  /// Same working directory as config.toml.
  File get _file => File("shooter_overrides.json");

  String matchKey(ShootingMatch match) {
    if (match.sourceIds.isNotEmpty) {
      return "${match.sourceCode}:${match.sourceIds.first}";
    }
    return "${match.sourceCode}:${match.name}";
  }

  Future<void> ensureLoaded() {
    var pending = _loadFuture;
    if (pending != null) return pending;
    final future = _load();
    _loadFuture = future;
    return future;
  }

  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      var decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) return;
      var matches = decoded["matches"];
      if (matches is! Map) return;
      matches.forEach((key, value) {
        if (value is List) {
          _byMatch[key.toString()] = value
              .whereType<Map>()
              .map(
                (e) => ShooterOverride.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
      });
      _log.i("Loaded shooter overrides for ${_byMatch.length} matches");
    } catch (e, st) {
      _loadFuture = null;
      _log.e("Failed to load shooter overrides", error: e, stackTrace: st);
    }
  }

  Future<void> _save() async {
    var encoded = const JsonEncoder.withIndent("  ").convert({
      "matches": {
        for (var entry in _byMatch.entries)
          if (entry.value.isNotEmpty)
            entry.key: entry.value.map((e) => e.toJson()).toList(),
      },
    });
    await _file.writeAsString(encoded);
  }

  List<ShooterOverride> overridesFor(ShootingMatch match) {
    return _byMatch[matchKey(match)] ?? const [];
  }

  ShooterOverride? find(ShootingMatch match, MatchEntry shooter) {
    return overridesFor(match).firstWhereOrNull((o) => o.matches(shooter));
  }

  Future<void> upsert(ShootingMatch match, ShooterOverride override) async {
    await ensureLoaded();
    var key = matchKey(match);
    var list = [...(_byMatch[key] ?? const <ShooterOverride>[])];
    list.removeWhere((o) => _sameIdentity(o, override));
    list.add(override);
    _byMatch[key] = list;
    await _save();
  }

  Future<void> remove(ShootingMatch match, MatchEntry shooter) async {
    await ensureLoaded();
    var key = matchKey(match);
    var list = [...(_byMatch[key] ?? const <ShooterOverride>[])];
    list.removeWhere((o) => o.matches(shooter));
    if (list.isEmpty) {
      _byMatch.remove(key);
    } else {
      _byMatch[key] = list;
    }
    await _save();
  }

  bool _sameIdentity(ShooterOverride a, ShooterOverride b) {
    if (a.sourceId != null &&
        a.sourceId!.isNotEmpty &&
        b.sourceId != null &&
        b.sourceId!.isNotEmpty) {
      return a.sourceId == b.sourceId;
    }
    if (a.entryId != null &&
        b.entryId != null &&
        a.entryId != 0 &&
        a.entryId == b.entryId) {
      return true;
    }
    if (a.memberNumber != null &&
        a.memberNumber!.isNotEmpty &&
        b.memberNumber != null &&
        b.memberNumber!.isNotEmpty) {
      return Shooter.normalizeNumber(a.memberNumber!) ==
          Shooter.normalizeNumber(b.memberNumber!);
    }
    if (a.firstName != null &&
        a.lastName != null &&
        b.firstName != null &&
        b.lastName != null) {
      return a.firstName!.toLowerCase() == b.firstName!.toLowerCase() &&
          a.lastName!.toLowerCase() == b.lastName!.toLowerCase();
    }
    return false;
  }

  /// Apply stored overrides to [match], mutating shooters in place.
  ///
  /// Returns the number of shooters changed.
  int applyToMatch(ShootingMatch match) {
    var overrides = overridesFor(match);
    if (overrides.isEmpty) return 0;
    var applied = 0;
    for (var shooter in match.shooters) {
      var override = overrides.firstWhereOrNull((o) => o.matches(shooter));
      if (override == null) continue;
      if (applyOverride(match.sport, shooter, override)) {
        applied++;
      }
    }
    if (applied > 0) {
      _log.i("Applied $applied shooter override(s) to ${match.name}");
    }
    return applied;
  }

  /// Mutate [shooter] to match [override]. Remaps stage scoring events when PF changes.
  bool applyOverride(
    Sport sport,
    MatchEntry shooter,
    ShooterOverride override,
  ) {
    var changed = false;

    if (override.powerFactorName != null) {
      var pf = sport.powerFactors.lookupByName(
        override.powerFactorName,
        fallback: false,
      );
      if (pf != null && pf != shooter.powerFactor) {
        _remapScoresToPowerFactor(shooter, pf);
        shooter.powerFactor = pf;
        changed = true;
      }
    }

    if (override.divisionName != null && sport.hasDivisions) {
      var division = sport.divisions.lookupByName(
        override.divisionName,
        fallback: false,
      );
      if (division != null && division != shooter.division) {
        shooter.division = division;
        changed = true;
      }
    }

    return changed;
  }

  /// Put [shooter] back on the server power factor and division recorded in [override].
  bool revert(Sport sport, MatchEntry shooter, ShooterOverride override) {
    return applyOverride(
      sport,
      shooter,
      ShooterOverride(
        powerFactorName: override.originalPowerFactorName,
        divisionName: override.originalDivisionName,
      ),
    );
  }

  void _remapScoresToPowerFactor(MatchEntry shooter, PowerFactor newPf) {
    for (var score in shooter.scores.values) {
      Map<ScoringEvent, int> targetEvents = {};
      Map<ScoringEvent, int> penaltyEvents = {};
      for (var event in score.targetEvents.keys) {
        var mapped = newPf.targetEvents.lookupByName(
          event.name,
          fallback: false,
        );
        if (mapped != null) {
          targetEvents[mapped] = score.targetEvents[event] ?? 0;
        } else {
          _log.w(
            "Unknown target event ${event.name} in power factor ${newPf.name}",
          );
        }
      }
      for (var event in score.penaltyEvents.keys) {
        var mapped = newPf.penaltyEvents.lookupByName(
          event.name,
          fallback: false,
        );
        if (mapped != null) {
          penaltyEvents[mapped] = score.penaltyEvents[event] ?? 0;
        } else {
          _log.w(
            "Unknown penalty event ${event.name} in power factor ${newPf.name}",
          );
        }
      }
      score.targetEvents = targetEvents;
      score.penaltyEvents = penaltyEvents;
      score.clearCache();
    }
  }
}
