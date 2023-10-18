import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';

/// A Sport is a shooting sports discipline.
class Sport {
  /// The name of the sport, e.g. "PCSL"
  final String name;

  final MatchScoring matchScoring;
  final StageScoring stageScoring;

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

  bool get hasPowerFactors => powerFactors.length > 1;

  Sport(this.name, {
    required this.matchScoring,
    required this.stageScoring,
    this.hasStages = true,
    List<Classification> classifications = const [],
    List<Division> divisions = const [],
    required List<PowerFactor> powerFactors,
  }) :
        classifications = Map.fromEntries(classifications.map((e) => MapEntry(e.name, e))),
        divisions = Map.fromEntries(divisions.map((e) => MapEntry(e.name, e))),
        powerFactors = Map.fromEntries(powerFactors.map((e) => MapEntry(e.name, e)));
}

class PowerFactor {
  final String name;

  /// A map of names to scoring events.
  ///
  /// e.g. "A" -> ScoringEvent("A", pointChange: 5)
  final Map<String, ScoringEvent> targetEvents;

  /// A map of names to scoring events.
  ///
  /// e.g. "Procedural" -> ScoringEvent("Procedural", pointChange: -10)
  final Map<String, ScoringEvent> penaltyEvents;

  final List<String> alternateNames;

  PowerFactor(this.name, {
    required List<ScoringEvent> targetEvents,
    List<ScoringEvent> penaltyEvents = const [],
    this.alternateNames = const [],
  }) :
    targetEvents = Map.fromEntries(targetEvents.map((e) => MapEntry(e.name, e))),
    penaltyEvents = Map.fromEntries(penaltyEvents.map((e) => MapEntry(e.name, e)))
  ;
}

class Division {
  /// Name is the long display name for a division.
  final String name;
  /// Short name is the abbreviated display name for a division.
  final String shortName;

  /// Alternate names are names that may be used for this division when
  /// parsing match results.
  final List<String> alternateNames;

  const Division({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}

class Classification {
  final int index;
  final String name;
  final String shortName;

  final List<String> alternateNames;

  const Classification({
    required this.index,
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}