/// A Sport is a shooting sports discipline.
class Sport {
  /// The name of the sport, e.g. "PCSL"
  final String name;

  final SportScoring scoring;

  /// Whether a match in the sport has distinct stages/courses of fire with
  /// scoring implications (USPSA, IDPA, etc.), or is simply scored overall
  /// (shotgun sports).
  final bool hasStages;

  /// The classifications in the
  final Map<String, SportClassification> classifications;

  /// The divisions (equipment classes/categories) in the sport.
  ///
  /// Sports with no divisions can leave this empty.
  final Map<String, SportDivision> divisions;

  /// The power factors in the sport. For sports without distinct scoring by
  /// power factor, provide an 'all' power factor containing the scoring information.
  final Map<String, PowerFactor> powerFactors;

  bool get hasPowerFactors => powerFactors.length > 1;

  Sport(this.name, {
    required this.scoring,
    this.hasStages = true,
    List<SportClassification> classifications = const [],
    List<SportDivision> divisions = const [],
    required List<PowerFactor> powerFactors,
  }) :
        classifications = Map.fromEntries(classifications.map((e) => MapEntry(e.name, e))),
        divisions = Map.fromEntries(divisions.map((e) => MapEntry(e.name, e))),
        powerFactors = Map.fromEntries(powerFactors.map((e) => MapEntry(e.name, e)));
}

enum SportScoring {
  hitFactor,
  timePlus,
  points,
}

class PowerFactor {
  String name;

  /// A map of names to scoring events.
  ///
  /// e.g. "A" -> ScoringEvent("A", pointChange: 5)
  final Map<String, ScoringEvent> targetEvents;

  /// A map of names to scoring events.
  ///
  /// e.g. "Procedural" -> ScoringEvent("Procedural", pointChange: -10)
  final Map<String, ScoringEvent> penaltyEvents;

  PowerFactor(this.name, {
    required List<ScoringEvent> targetEvents,
    List<ScoringEvent> penaltyEvents = const [],
  }) :
    targetEvents = Map.fromEntries(targetEvents.map((e) => MapEntry(e.name, e))),
    penaltyEvents = Map.fromEntries(penaltyEvents.map((e) => MapEntry(e.name, e)))
  ;
}

/// A ScoringEvent is the minimal unit of score change in a shooting sports
/// discipline, based on a hit on target.
class ScoringEvent {
  String name;

  int pointChange;
  double timeChange;

  ScoringEvent(this.name, {this.pointChange = 0, this.timeChange = 0});
}

class SportDivision {
  String name;
  String shortName;

  List<String> alternateNames;

  SportDivision({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}

class SportClassification {
  String name;
  String shortName;

  List<String> alternateNames;

  SportClassification({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}