/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

part 'ratings.g.dart';

// DbRatingProject hasMany DbRatingGroups hasMany DbShooterRatings hasMany DbRatingEvents.

mixin DbSportEntity {
  String get sportName;

  @ignore
  Sport get sport => SportRegistry().lookup(sportName)!;
}

@collection
class DbRatingProject with DbSportEntity {
  Id id = Isar.autoIncrement;

  String sportName;

  final groups = IsarLinks<DbRatingGroup>();

  DbRatingProject({
    required this.sportName,
  });
}

@collection
class DbRatingGroup with DbSportEntity {
  Id id = Isar.autoIncrement;

  String sportName;
  String name;

  List<String> divisionNames;
  List<Division> get divisions =>
      divisionNames.map((name) => sport.divisions.lookupByName(name))
      .where((result) => result != null)
      .cast<Division>()
      .toList();

  DbRatingGroup({
    required this.sportName,
    required this.name,
    this.divisionNames = const [],
  });
}

@collection

@collection
class DbRatingEvent {

}