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
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
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

  // TODO: generic typo-detection implementation for ICORE/IDPA/PCSL/etc.
  /// The deduplication logic used for this sport. Leave null if deduplication
  /// is unnecessary.
  final ShooterDeduplicator? shooterDeduplicator;
  /// 
  final RatingStrengthProvider? ratingStrengthProvider;
  final PubstompProvider? pubstompProvider;
  final RatingGroupsProvider? builtinRatingGroupsProvider;
  final FantasyScoringCalculator? fantasyScoresProvider;
  final ConnectivityCalculator? connectivityCalculator;

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
    /// If present, the caller does not want the default display settings, but
    /// cannot provide them as a constructor argument (e.g. because the display
    /// settings require knowledge of the sport). This will be called by [Sport]'s
    /// constructor body to retrieve display settings, if present.
    SportDisplaySettings Function(Sport)? displaySettingsBuilder,
    this.shooterDeduplicator,
    this.initialEloRatings = const {},
    this.initialOpenskillRatings = const {},
    this.ratingStrengthProvider,
    this.pubstompProvider,
    this.builtinRatingGroupsProvider,
    this.fantasyScoresProvider,
    this.connectivityCalculator,
  }) :
        classifications = Map.fromEntries(classifications.map((e) => MapEntry(e.name, e))),
        divisions = Map.fromEntries(divisions.map((e) => MapEntry(e.name, e))),
        powerFactors = Map.fromEntries(powerFactors.map((e) => MapEntry(e.name, e))),
        eventLevels = Map.fromEntries(eventLevels.map((e) => MapEntry(e.name, e))),
        ageCategories = Map.fromEntries(ageCategories.map((e) => MapEntry(e.name, e))) {
    if(displaySettings != null) {
      this.displaySettings = displaySettings;
    }
    else if(displaySettingsBuilder != null) {
      this.displaySettings = displaySettingsBuilder(this);
    }
    else {
      this.displaySettings = SportDisplaySettings.defaultForSport(this, powerFactor: displaySettingsPowerFactor);
    }
  }
}

class PowerFactor extends NameLookupEntity {
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

  Map<String, ScoringEvent> get allEvents => {...targetEvents, ...penaltyEvents};

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
    penaltyEvents = Map.fromEntries(penaltyEvents.map((e) => MapEntry(e.name, e)));

  const PowerFactor.constant(this.name, {
    this.shortName = "",
    this.alternateNames = const [],
    this.fallback = false,
    this.doesNotScore = false,
    required this.targetEvents,
    this.penaltyEvents = const {},
  });

  @override
  String toString() {
    return displayName;
  }
}

class Division extends NameLookupEntity {
  String get longName => _longName ?? name;
  final String? _longName;
  /// Name is the long display name for a division.
  final String name;
  /// Short name is the abbreviated display name for a division.
  final String shortName;

  /// Alternate names are names that may be used for this division when
  /// parsing match results.
  final List<String> alternateNames;

  /// The full display name for this division.
  String get displayName => name;
  /// The short or abbreviated display name for this division.
  String get shortDisplayName => shortName.isNotEmpty ? shortName : name;

  /// If non-null, this division always uses the specified power factor for scoring.
  final PowerFactor? powerFactorOverride;

  final bool fallback;

  const Division({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
    this.fallback = false,
    this.powerFactorOverride,
    String? longName
  }) : _longName = longName;

  @override
  String toString() {
    return displayName;
  }
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

  bool matches(String value) {
    String lower = value.toLowerCase();
    if(shortName.toLowerCase() == lower) {
        return true;
      }

      if(name.toLowerCase() == lower) {
        return true;
      }

      if(longName.toLowerCase() == lower) {
        return true;
      }

      if(alternateNames.any((alternateName) => alternateName.toLowerCase() == lower)) {
        return true;
      }

      return false;
  }
}

extension LookupNameInList<T extends NameLookupEntity> on Iterable<T> {
  T? lookupByName(String name, {bool fallback = true}) {
    name = name.toLowerCase();
    T? found = this.firstWhereOrNull((entity) => _matches(entity, name));

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

  List<T> lookupAllByName(String name, {bool fallback = true}) {
    name = name.toLowerCase();
    var found = this.where((entity) => _matches(entity, name)).toList();

    if(found.isNotEmpty) {
      return found;
    }
    else if(fallback) {
      var fallback = this.fallback();
      if(fallback != null) {
        return [fallback];
      }
    }

    return [];
  }

  bool _matches(T entity, String query) {
    query = query.toLowerCase();
    // Put short name first, because it's more likely to show up in
    // encodings
    if(entity.shortName.toLowerCase() == query) {
        return true;
      }

    if(entity.name.toLowerCase() == query) {
      return true;
    }

    if(entity.longName.toLowerCase() == query) {
      return true;
    }

    if(entity.alternateNames.any((alternateName) => alternateName.toLowerCase() == query)) {
      return true;
    }

    return false;
  }

  bool containsAll(List<String> values) {
    return !values.any((v) => lookupByName(v) == null);
  }

  T? fallback() {
    return this.firstWhereOrNull((entity) => entity.fallback);
  }
}

extension LookupNameInMap<T extends NameLookupEntity> on Map<String, T> {
  T? lookupByName(String? name, {bool fallback = true}) {
    if(name == null) {
      if(fallback) return this.fallback();
      else return null;
    }

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

class Classification extends NameLookupEntity {
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

  @override
  String toString() {
    return displayName;
  }
}

enum EventLevel {
  local,
  regional,
  area,
  national,
  international;
}

class MatchLevel extends NameLookupEntity {
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

  @override
  String toString() {
    return displayName;
  }
}