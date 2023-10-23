
import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/builtin_registry.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/util.dart';

part 'match.g.dart';

// Thinking: store various sport properties like PowerFactor etc. as

/// An Isar DB ID for parent/child entities in different collections.
typedef ExternalId = int;

@collection
class DbShootingMatch {
  Id id = Isar.autoIncrement;
  String eventName;
  String rawDate;
  DateTime date;
  String? matchLevelName;
  List<String> sourceIds;

  @enumerated
  EventLevel matchEventLevel;
  String sportName;

  DbShootingMatch({
    this.id = Isar.autoIncrement,
    required this.eventName,
    required this.rawDate,
    required this.date,
    required this.matchLevelName,
    required this.matchEventLevel,
    required this.sportName,
    required this.sourceIds,
  });

  DbShootingMatch.from(ShootingMatch match) :
    id = match.databaseId ?? Isar.autoIncrement,
    eventName = match.eventName,
    rawDate = match.rawDate,
    date = match.date,
    matchLevelName = match.level?.name,
    matchEventLevel = match.level?.eventLevel ?? EventLevel.local,
    sourceIds = []..addAll(match.sourceIds),
    sportName = match.sport.name;

  Result<ShootingMatch, Error> hydrate() {
    var sport = BuiltinSportRegistry().lookup(sportName);
    if(sport == null) {
      return Result.err(StringError("sport not found"));
    }

    MatchLevel? matchLevel = null;
    if(matchLevelName != null && sport.hasEventLevels) {
      matchLevel = sport.eventLevels.lookupByName(matchLevelName!);
    }

    return Result.ok(ShootingMatch(
      databaseId: this.id,
      eventName: this.eventName,
      rawDate: this.rawDate,
      date: this.date,
      stages: [],
      sport: sport,
      shooters: [],
      level: matchLevel,
      sourceIds: []..addAll(this.sourceIds),
    ));
  }
}

@collection
class DbMatchStage {
  Id? id;
  ExternalId match;

  DbMatchStage({
    required this.match,
  });
}

@collection
class DbShooter {
  Id? id;
  ExternalId match;

  DbShooter({
    required this.match,
  });
}

