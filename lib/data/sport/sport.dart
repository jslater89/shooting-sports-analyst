/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interfaces.dart';
import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/sport/display_settings.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';

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

  /// The power factors in the sport. All sports must provide at least one
  /// power factor. If the sport scores all competitors the same regardless
  /// of power, provide an 'all' power factor containing the scoring. If the
  /// sport has meaningfully distinct power factors, provide multiples.
  ///
  /// Power factors should be const.
  final Map<String, PowerFactor> powerFactors;

  /// The age categories in this sport.
  ///
  /// Leave this empty if the sport does not recognize age categories.
  final Map<String, AgeCategory> ageCategories;

  /// Sort modes that are meaningful for this sport.
  final List<SortMode> resultSortModes;

  /// The deduplication logic used for this sport. Leave null if deduplication
  /// is unnecessary, or specify an instance of ManualDeduplicator to use the
  /// user mappings and mapping blacklist in rater settings.
  final ShooterDeduplicator? shooterDeduplicator;

  /// Initial ratings for the Elo rating engine.
  Map<Classification, double> initialEloRatings;

  /// Initial rating for the OpenSkill rating engine.
  Map<Classification, List<double>> initialOpenskillRatings;

  PowerFactor get defaultPowerFactor {
    if(powerFactors.length == 1) {
      return powerFactors.values.first;
    }
    else {
      var pf = powerFactors.values.firstWhereOrNull((element) => element.fallback);
      if(pf != null) {
        return pf;
      }
    }

    throw StateError("sport with power factors is missing default power factor");
  }
  
  final Map<String, MatchLevel> eventLevels;

  bool get hasPowerFactors => powerFactors.length > 1; // All sports have one default PF
  bool get hasDivisions => divisions.length > 0;
  bool get hasDivisionFallback => divisions.values.any((element) => element.fallback);
  bool get hasClassifications => classifications.length > 0;
  bool get hasAgeCategories => ageCategories.length > 0;
  bool get hasClassificationFallback => classifications.values.any((element) => element.fallback);
  bool get hasEventLevels => eventLevels.length > 0;

  late final SportDisplaySettings displaySettings;

  final RatingStrengthProvider? ratingStrengthProvider;
  final PubstompProvider? pubstompProvider;
  final RatingGroupsProvider? builtinRatingGroupsProvider;

  Sport(this.name, {
    required this.matchScoring,
    required this.defaultStageScoring,
    required this.type,
    this.hasStages = true,
    this.resultSortModes = const [
      SortMode.score,
      SortMode.time,
      SortMode.lastName,
      SortMode.classification,
    ],
    List<Classification> classifications = const [],
    List<Division> divisions = const [],
    List<MatchLevel> eventLevels = const [],
    List<AgeCategory> ageCategories = const [],
    required List<PowerFactor> powerFactors,
    SportDisplaySettings? displaySettings,
    /// The power factor to use when generating default display settings.
    /// No effect if [displaySettings] is provided.
    PowerFactor? displaySettingsPowerFactor,
    this.shooterDeduplicator,
    this.initialEloRatings = const {},
    this.initialOpenskillRatings = const {},
    this.ratingStrengthProvider,
    this.pubstompProvider,
    this.builtinRatingGroupsProvider,
  }) :
        classifications = Map.fromEntries(classifications.map((e) => MapEntry(e.name, e))),
        divisions = Map.fromEntries(divisions.map((e) => MapEntry(e.name, e))),
        powerFactors = Map.fromEntries(powerFactors.map((e) => MapEntry(e.name, e))),
        eventLevels = Map.fromEntries(eventLevels.map((e) => MapEntry(e.name, e))),
        ageCategories = Map.fromEntries(ageCategories.map((e) => MapEntry(e.name, e))) {
    if(displaySettings != null) {
      this.displaySettings = displaySettings;
    }
    else {
      this.displaySettings = SportDisplaySettings.defaultForSport(this, powerFactor: displaySettingsPowerFactor);
    }
  }
}

class PowerFactor implements NameLookupEntity {
  String get longName => name;
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

  final bool fallback;

  /// If true, this power factor does not score, like subminor in USPSA.
  ///
  /// Rating engines will treat match results with a doesNotScore power factor as a
  /// DNF, and ignore them for rating purposes.
  final bool doesNotScore;

  PowerFactor(this.name, {
    this.shortName = "",
    required List<ScoringEvent> targetEvents,
    List<ScoringEvent> penaltyEvents = const [],
    this.alternateNames = const [],
    this.fallback = false,
    this.doesNotScore = false,
  }) :
    targetEvents = Map.fromEntries(targetEvents.map((e) => MapEntry(e.name, e))),
    penaltyEvents = Map.fromEntries(penaltyEvents.map((e) => MapEntry(e.name, e)))
  ;
}

class Division implements NameLookupEntity {
  String get longName => _longName ?? name;
  final String? _longName;
  /// Name is the long display name for a division.
  final String name;
  /// Short name is the abbreviated display name for a division.
  final String shortName;

  /// Alternate names are names that may be used for this division when
  /// parsing match results.
  final List<String> alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final bool fallback;

  const Division({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
    this.fallback = false,
    String? longName
  }) : _longName = longName;
}

abstract class NameLookupEntity {
  /// A long name, to be used in contexts where space doesn't matter
  /// and clarity is maximally important, such as the match score filter
  /// dialog.
  String get longName;
  /// A medium-length name, to be used in context where a balance between
  /// space and clarity is important, such as the division column of the
  /// match score page.
  String get name;
  /// A short name, to be used where space is maximally important, like
  /// the division tabs in the rater view.
  String get shortName;
  /// Additional names that match this entity.
  List<String> get alternateNames;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  bool get fallback => false;

  const NameLookupEntity();
}

extension LookupNameInList<T extends NameLookupEntity> on Iterable<T> {
  T? lookupByName(String name, {bool fallback = true}) {
    name = name.toLowerCase();
    T? found = this.firstWhereOrNull((entity) {
      // Put short name first, because it's more likely to show up in
      // encodings
      if(entity.shortName.toLowerCase() == name) {
        return true;
      }

      if(entity.name.toLowerCase() == name) {
        return true;
      }

      if(entity.longName.toLowerCase() == name) {
        return true;
      }

      if(entity.alternateNames.any((alternateName) => alternateName.toLowerCase() == name)) {
        return true;
      }

      return false;
    });

    if(found != null) {
      return found;
    }
    else if(fallback) {
      return this.fallback();
    }
    else {
      return null;
    }
  }

  bool containsAll(List<String> values) {
    return !values.any((v) => lookupByName(v) == null);
  }

  T? fallback() {
    return this.firstWhereOrNull((entity) => entity.fallback);
  }
}

extension LookupNameInMap<T extends NameLookupEntity> on Map<String, T> {
  T? lookupByName(String name, {bool fallback = true}) {
    name = name.trim();
    var byKey = this[name];
    if(byKey != null) return byKey;

    return this.values.lookupByName(name, fallback: fallback);
  }

  bool containsAll(List<String> values) {
    return !values.any((v) => lookupByName(v) == null);
  }

  T? fallback() {
    return this.values.fallback();
  }
}

class Classification implements NameLookupEntity {
  final int index;
  String get longName => name;
  final String name;
  final String shortName;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final List<String> alternateNames;

  final bool fallback;

  const Classification({
    required this.index,
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
    this.fallback = false,
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
  String get longName => name;
  final String name;
  final String shortName;
  final EventLevel eventLevel;

  String get displayName => name;
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  final List<String> alternateNames;

  final bool fallback;

  const MatchLevel({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
    this.eventLevel = EventLevel.local,
    this.fallback = false,
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
/// sports. If (I write a sport editor and) a user defines a sport with it, it
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
  dynamicTimePlusPointsDown;

  /// Does this sport display results like a USPSA match, or like an IDPA match?
  ///
  /// USPSA-style display has 1-3-letter abbreviations for every scoring event, and displays
  /// all of the hits and penalties for a given score in a short string, e.g.
  /// 123A 23C 3D
  ///
  /// IDPA-style display condenses scoring events into one column (e.g., 'points down'), and shows
  /// several penalties of different values separately ('PE', 'Non-Threat', 'FTDR').
  ///
  /// This is advisory/informational: sports may define their own [ScoreDisplaySettings] to control
  /// score column layout more precisely, but the value here will define how the default is generated.
  bool get uspsaStyleDisplay =>
      this == uspsa ||
      this == ipsc ||
      this == icore ||
      this == pcsl ||
      this == userDefinedHitFactor ||
      this == dynamicHitFactor;

  bool get isHitFactor =>
    this == uspsa ||
    this == ipsc ||
    this == pcsl ||
    this == userDefinedHitFactor ||
    this == dynamicHitFactor;

  bool get isPoints =>
      this == userDefinedPoints ||
      this == dynamicPoints;

  bool get isTimePlus =>
      this == idpa ||
      this == icore ||
      this == userDefinedTimePlusPenalties ||
      this == userDefinedTimePlusPointsDown ||
      this == dynamicTimePlusPenalties ||
      this == dynamicTimePlusPointsDown;
}

class AgeCategory extends NameLookupEntity {
  final String name;
  final List<String> alternateNames;

  @override
  bool get fallback => false;

  @override
  String get longName => name;

  @override
  String get shortName => name;

  const AgeCategory({
    required this.name, this.alternateNames = const [],
  });
}