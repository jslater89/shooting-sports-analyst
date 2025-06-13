/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/matchups.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'roster.g.dart';

/// A team's monthly roster.
@collection
class MonthlyRoster {
  Id get id => combineHashList([teamId, monthId]);

  final team = IsarLink<Team>();
  final month = IsarLink<LeagueMonth>();

  int teamId;
  int monthId;

  // The actual assignments for this month
  final assignments = IsarLinks<RosterAssignment>();

  // When this roster was last edited
  DateTime lastModified;

  // Whether this roster is locked.
  bool isLocked;

  /// Whether this roster should be locked.
  ///
  /// Returns true when the current time is greater than or equal to the
  /// start date of the league month.
  Future<bool> shouldLock() async {
    var leagueMonth = await getLeagueMonth();
    var now = DateTime.now().toUtc();
    return now.isAfter(leagueMonth.startDate) || now.isAtSameMomentAs(leagueMonth.startDate);
  }

  Future<Team> getTeam() async {
    if(!team.isLoaded) {
      await team.load();
    }
    return team.value!;
  }

  Future<LeagueMonth> getLeagueMonth() async {
    if(!month.isLoaded) {
      await month.load();
    }
    return month.value!;
  }

  Future<List<RosterAssignment>> getAssignments() async {
    if(!assignments.isLoaded) {
      await assignments.load();
    }
    return assignments.toList();
  }

  Future<List<FantasyPlayer>> getPlayers() async {
    var assignments = await getAssignments();
    var players = <FantasyPlayer>[];
    for(var assignment in assignments) {
      players.add(await assignment.getPlayer());
    }
    return players;
  }

  Future<LeagueSeason> getLeagueSeason() async {
    return getLeagueMonth().then((month) => month.getSeason());
  }

  Future<League> getLeague() async {
    return getLeagueSeason().then((season) => season.getLeague());
  }

  Future<List<RosterSlot>> getSlots() async {
    return getLeague().then((league) => league.getRosterSlots());
  }

  /// The scores for each slot in this roster.
  List<SlotScore> slotScores;

  /// Get the score for a slot by index.
  SlotScore getSlotScoreByIndex(int index) {
    return slotScores.firstWhere((element) => element.slotIndex == index);
  }

  /// Get the player performance for a slot by index.
  Future<PlayerMonthlyPerformance?> getSlotPerformance(int index) async {
    var slotScore = getSlotScoreByIndex(index);
    var performance = await PlayerMonthlyPerformance.getByEntityIds(playerId: slotScore.playerId, monthId: monthId);
    return performance;
  }

  /// Get the score for a slot by slot type and index.
  SlotScore getSlotScore(FantasyRosterSlotType slotType, int index) {
    return slotScores.firstWhere((element) => element.slotIndex == index);
  }

  MonthlyRoster({
    required this.teamId,
    required this.monthId,
    required this.lastModified,
    required this.isLocked,
    this.slotScores = const [],
  });
}

/// An association between a player and a roster slot.
///
/// It may be a provisional assignment (i.e. what you see on a team's roster settings
/// page), in which case [month] and [monthId] will be null, or it may be a finalized
/// assignment (i.e. used, or in the process of being used, for scoring), in which case
/// [month] and [monthId] will be non-null.
///
/// The [id] is a combination of the [teamId], [slotId], and [monthId].
@collection
class RosterAssignment {
  static Id idForIds({required int teamId, required int slotId, int? monthId}) {
    List<int> ids = [teamId, slotId];
    if(monthId != null) {
      ids.add(monthId);
    }
    return combineHashList(ids);
  }

  Id get id => idForIds(teamId: teamId, slotId: slotId, monthId: monthId);

  final team = IsarLink<Team>();
  final slot = IsarLink<RosterSlot>();
  final player = IsarLink<FantasyPlayer>();
  final month = IsarLink<LeagueMonth>();

  int teamId;
  int slotId;
  int? monthId;

  Future<FantasyPlayer> getPlayer() async {
    if(!player.isLoaded) {
      await player.load();
    }
    return player.value!;
  }

  /// Create a roster assignment from raw IDs.
  ///
  /// This does not populate links or save the assignment to the database.
  RosterAssignment({
    required this.teamId,
    required this.slotId,
    this.monthId,
  });

  /// Create a roster assignment from database entities.
  ///
  /// This sets the values of the [team], [slot], and [player] links,
  /// but does not save the assignment to the database.
  RosterAssignment.fromEntities({
    required Team team,
    required RosterSlot slot,
    required FantasyPlayer player,
    LeagueMonth? month,
  }) : teamId = team.id,
       slotId = slot.id,
       monthId = month?.id
  {
    this.team.value = team;
    this.slot.value = slot;
    this.player.value = player;
    this.month.value = month;
  }
}

/// A slot in a [MonthlyRoster] with its display order.
@collection
class RosterSlot {
  Id id = Isar.autoIncrement;

  final slotType = IsarLink<FantasyRosterSlotType>();

  int index;

  RosterSlot({
    required this.index,
  });
}


/// A sport that can provide a list of roster slots.
///
/// This is used to determine what kinds of roster slots a
/// given fantasy league can have, based on its sport.
abstract interface class FantasyRosterSlotProvider {
  List<FantasyRosterSlotType> get slotTypes;
}

/// A type of roster slot, including a name and a definition
/// of what competitors are eligible to be assigned to it.
///
/// Roster slots are generally created by a [FantasyRosterSlotProvider].
///
/// The roster slot type's [id] is a combination of its [sportName] and [name];
/// [id] uniquely identifies the type by definition.
@collection
class FantasyRosterSlotType with DbSportEntity {
  Id get id => (sportName + name).stableHash;

  /// The sport that this slot is for.
  String sportName;

  /// The name of this slot type.
  String name;

  /// The divisions that can be assigned to this slot type.
  @ignore
  List<Division> divisions;
  List<String> get dbDivisions => divisions.map((e) => e.name).toList();
  set dbDivisions(List<String> value) {
    divisions = value.map((e) => sport.divisions.lookupByName(e)!).toList();
  }

  /// The age categories that can be assigned to this slot type.
  @ignore
  List<AgeCategory> ages;
  List<String> get dbAges => ages.map((e) => e.name).toList();
  set dbAges(List<String> value) {
    ages = value.map((e) => sport.ageCategories.lookupByName(e)!).toList();
  }

  /// Whether this slot type can only contain female shooters.
  bool femaleOnly;

  FantasyRosterSlotType({
    this.sportName = "",
    this.name = "",
    this.divisions = const [],
    this.ages = const [],
    this.femaleOnly = false,
  });

  FantasyRosterSlotType.create({
    required this.sportName,
    required this.name,
    this.divisions = const [],
    this.ages = const [],
    this.femaleOnly = false,
  });
}
