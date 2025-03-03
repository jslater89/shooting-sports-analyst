
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

part 'scoring_events.g.dart';

/// A DbScoringEvent is a database representation of a [ScoringEvent].
///
/// This is used to store match-specific scoring events in the database, and may
/// be used to store user-defined sport scoring information in the future.
@embedded
class DbScoringEvent {
  String name;
  String shortName;
  List<String> alternateNames;

  int pointChange;
  double timeChange;
  bool displayInOverview;

  bool variableValue;
  bool nondefaultPoints;
  bool nondefaultTime;

  int sortOrder;

  bool bonus;
  String bonusLabel;
  
  bool dynamic;

  DbScoringEvent({
    this.name = "",
    this.shortName = "",
    this.alternateNames = const [],
    this.pointChange = 0,
    this.timeChange = 0,
    this.displayInOverview = true,
    this.variableValue = false,
    this.nondefaultPoints = false,
    this.nondefaultTime = false,
    this.bonus = false,
    this.bonusLabel = "",
    this.dynamic = false,
    this.sortOrder = 0,
  });

  ScoringEvent toScoringEvent() {
    return ScoringEvent(
      name,
      shortName: shortName,
      alternateNames: alternateNames,
      pointChange: pointChange,
      timeChange: timeChange,
      displayInOverview: displayInOverview,
      variableValue: variableValue,
      nondefaultPoints: nondefaultPoints,
      nondefaultTime: nondefaultTime,
      bonus: bonus,
      bonusLabel: bonusLabel,
      dynamic: dynamic,
      sortOrder: sortOrder,
    );
  }

  factory DbScoringEvent.fromScoringEvent(ScoringEvent event) {
    return DbScoringEvent(
      name: event.name,
      shortName: event.shortName,
      alternateNames: event.alternateNames,
      pointChange: event.pointChange,
      timeChange: event.timeChange,
      displayInOverview: event.displayInOverview,
      variableValue: event.variableValue,
      nondefaultPoints: event.nondefaultPoints,
      nondefaultTime: event.nondefaultTime,
      bonus: event.bonus,
      bonusLabel: event.bonusLabel,
      dynamic: event.dynamic,
      sortOrder: event.sortOrder,
    );
  }
}