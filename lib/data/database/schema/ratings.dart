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

  @Backlink(to: 'project')
  final groups = IsarLinks<DbRatingGroup>();

  DbRatingProject({
    required this.sportName,
  });
}

@collection
class DbRatingGroup {
  Id id = Isar.autoIncrement;

  final project = IsarLink<DbRatingProject>();
  @Backlink(to: 'group')
  final ratings = IsarLinks<DbShooterRating>();
}

@collection
class DbShooterRating extends Shooter with DbSportEntity {
  DbShooterRating({
    required this.sportName,
    required super.firstName,
    required super.lastName,
  });

  String sportName;

  /// Internal, for DB serialization only.
  List<String> get knownMemberNumberList => knownMemberNumbers.toList();
  /// Internal, for DB serialization only.
  set knownMemberNumberList(List<String> v) {
    knownMemberNumbers.clear();
    knownMemberNumbers.addAll(v);
  }

  final group = IsarLink<DbRatingGroup>();
}

@collection
class DbRatingEvent {

}