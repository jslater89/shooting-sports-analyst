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
  /// A sport scored like USPSA: points divided by time is a hit factor for stage score,
  /// match score is a percentage of stage points based on stage finish.
  hitFactor,
  /// A sport scored like IDPA or multigun: score is raw time, plus penalties.
  timePlus,
  /// A sport scored like sporting clays or bullseye: score is determined entirely by hits on target.
  points,
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
  final String name;

  final int pointChange;
  final double timeChange;

  /// bonus indicates that this hit is a bonus/tiebreaker score with no other scoring implications:
  ///
  /// An ICORE stage with a time bonus for a X-ring hits is _not_ a bonus like this, because it scores
  /// differently than an A. A Bianchi X hit _is_ a bonus: it scores 10 points, but also increments
  /// your X count.
  final bool bonus;
  final String bonusLabel;

  const ScoringEvent(this.name, {this.pointChange = 0, this.timeChange = 0, this.bonus = false, this.bonusLabel = "X"});
}

class SportDivision {
  final String name;
  final String shortName;

  final List<String> alternateNames;

  const SportDivision({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}

class SportClassification {
  final String name;
  final String shortName;

  final List<String> alternateNames;

  const SportClassification({
    required this.name,
    required this.shortName,
    this.alternateNames = const [],
  });
}