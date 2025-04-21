/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
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
  Id id = Isar.autoIncrement;

  final team = IsarLink<Team>();
  final month = IsarLink<LeagueMonth>();

  // The actual assignments for this month
  final assignments = IsarLinks<RosterAssignment>();

  // When this roster was last edited
  DateTime lastModified;

  // Whether this roster is locked (happens automatically on 1st)
  bool isLocked;

  /// The scores for each slot in this roster.
  List<SlotScore> slotScores;

  /// Get the score for a slot by index.
  SlotScore getSlotScoreByIndex(int index) {
    return slotScores.firstWhere((element) => element.slotIndex == index);
  }

  /// Get the score for a slot by slot type and index.
  SlotScore getSlotScore(FantasyRosterSlotType slotType, int index) {
    return slotScores.firstWhere((element) => element.slotIndex == index);
  }

  MonthlyRoster({
    required this.lastModified,
    required this.isLocked,
    this.slotScores = const [],
  });
}

/// A player in a MonthlyRoster on a team.
@collection
class RosterAssignment {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'rosterAssignments')
  final team = IsarLink<Team>();
  final slot = IsarLink<RosterSlot>();
  final player = IsarLink<FantasyPlayer>();

  RosterAssignment();
}

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
