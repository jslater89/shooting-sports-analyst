/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';

/// A Sport is a shooting sports discipline.
class Sport {
  /// The name of the sport, e.g. "PCSL"
  final String name;

  final SportType type;

  /// How scores from various stages are totaled to produce a final match score.
  ///
  /// Sports without stages (see [hasStages]) should set this to [CumulativeScoring],
  /// probably.
  final MatchScoring matchScoring;

  /// The default method by which stages are scored in this sport.
  ///
  /// For sports without stages, this is how total scores are tallied.
  final StageScoring defaultStageScoring;

  /// Whether a match in the sport has distinct stages/courses of fire with
  /// scoring implications (USPSA, IDPA, etc.), or is simply scored overall
  /// (shotgun sports).
  final bool hasStages;

  /// The classifications in the sport. Provide them in order.
  ///
  /// Classifications should be const.
  final Map<String, Classification> classifications;

  /// The divisions (equipment classes/categories) in the sport.
  ///
  /// Sports with no divisions can leave this empty. Divisions should be const.
  final Map<String, Division> divisions;

  /// The power factors in the sport. For sports without distinct scoring by
  /// power factor, provide an 'all' power factor containing the scoring information.
  ///
  /// Power factors should be const.
  final Map<String, PowerFactor> powerFactors;
  
  final Map<String, MatchLevel> eventLevels;

  bool get hasPowerFactors => powerFactors.length > 1; // All sports have one default PF
  bool get hasDivisions => divisions.length > 0;
  bool get hasClassifications => classifications.length > 0;
  bool get hasEventLevels => eventLevels.length > 0;

  Sport(this.name, {
    required this.matchScoring,
    required this.defaultStageScoring,
    required this.type,
    this.hasStages = true,
    List<Classification> classifications = const [],
    List<Division> divisions = const [],
    List<MatchLevel> eventLevels = const [],
    required List<PowerFactor> powerFactors,
  }) :
        classifications = Map.fromEntries(classifications.map((e) => MapEntry(e.name, e))),
        divisions = Map.fromEntries(divisions.map((e) => MapEntry(e.name, e))),
        powerFactors = Map.fromEntries(powerFactors.map((e) => MapEntry(e.name, e))),
        eventLevels = Map.fromEntries(eventLevels.map((e) => MapEntry(e.name, e)))
  ;
}

class PowerFactor implements NameLookupEntity {
  final String name;
  final String shortName;

  /// A map of names to scoring events.
  ///
  /// e.g. "A" -> ScoringEvent("A", pointChange: 5)
  final Map<String, ScoringEvent> targetEvents;

  /// A map of names to scoring events.
  ///
  /// e.g. "Procedural" -> ScoringEvent("Procedural", pointChange: -10)
  final Map<String, ScoringEvent> penaltyEvents;

  final List<String> alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  PowerFactor(this.name, {
    this.shortName = "",
    required List<ScoringEvent> targetEvents,
    List<ScoringEvent> penaltyEvents = const [],
    this.alternateNames = const [],
  }) :
    targetEvents = Map.fromEntries(targetEvents.map((e) => MapEntry(e.name, e))),
    penaltyEvents = Map.fromEntries(penaltyEvents.map((e) => MapEntry(e.name, e)))
  ;
}

class Division implements NameLookupEntity {
  /// Name is the long display name for a division.
  final String name;
  /// Short name is the abbreviated display name for a division.
  final String shortName;

  /// Alternate names are names that may be used for this division when
  /// parsing match results.
  final List<String> alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  const Division({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}

abstract class NameLookupEntity {
  /// The long name
  String get name;
  String get shortName;
  List<String> get alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;
}

extension LookupNameInList<T extends NameLookupEntity> on Iterable<T> {
  T? lookupByName(String name) {
    name = name.toLowerCase();
    return this.firstWhereOrNull((entity) {
      // Put short name first, because it's more likely to show up in
      // encodings
      if(entity.shortName.toLowerCase() == name) {
        return true;
      }

      if(entity.name.toLowerCase() == name) {
        return true;
      }

      if(entity.alternateNames.any((alternateName) => alternateName.toLowerCase() == name)) {
        return true;
      }

      return false;
    });
  }
}

extension LookupNameInMap<T extends NameLookupEntity> on Map<String, T> {
  T? lookupByName(String name) {
    name = name.trim();
    var byKey = this[name];
    if(byKey != null) return byKey;

    return this.values.lookupByName(name);
  }
}

class Classification implements NameLookupEntity {
  final int index;
  final String name;
  final String shortName;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final List<String> alternateNames;

  const Classification({
    required this.index,
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}

enum EventLevel {
  local,
  regional,
  area,
  national,
  international;
}

class MatchLevel implements NameLookupEntity {
  final String name;
  final String shortName;
  final EventLevel eventLevel;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final List<String> alternateNames;

  const MatchLevel({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
    this.eventLevel = EventLevel.local,
  });
}

/// Sports a match source can provide.
///
/// The first group of values in the definition are hardcoded/built-in sports.
/// They're included because certain official scoring sources may not provide
/// data for other sports: if I ever get leave to write an official uspsa.org
/// match source, it will support USPSA only, not USPSA and other generic hit
/// factor matches.
/// 
/// The second group ('userDefined') is for non-hardcoded but still predefined
/// sports. If [I write a sport editor and] a user defines a sport with it, it
/// gets one of these types, and match sources declaring those types can parse
/// it to a ShootingMatch.
///
/// The final group ('dynamic') is for match sources whose fetch process also
/// fetches a sport definition, and that furthermore support generating an ad
/// hoc sport for displaying/filtering those scores.
enum SportType {
  uspsa,
  ipsc,
  idpa,
  icore,
  pcsl,

  userDefinedPoints,
  userDefinedHitFactor,
  userDefinedTimePlusPenalties,
  userDefinedTimePlusPointsDown,

  dynamicPoints,
  dynamicHitFactor,
  dynamicTimePlusPenalties,
  dynamicTimePlusPointsDown,
}