/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

part 'shooter_rating.g.dart';

/// DbSportRating is the database embodiment of shooter ratings. It should almost always
/// be wrapped by one of the subclasses of ShooterRating, which will wrap the various generic
/// data variables on this class.
@collection
class DbShooterRating extends Shooter with DbSportEntity {
  String sportName;

  Id id = Isar.autoIncrement;

  @ignore
  bool get isPersisted => id != Isar.autoIncrement;

  @Index(type: IndexType.hashElements)
  List<String> get dbKnownMemberNumbers => List<String>.from(knownMemberNumbers);

  @Index()
  String firstName;
  @Index()
  String lastName;


  @Index()
  List<String> get firstNameParts => firstName.split(RegExp(r'\w+'));
  @Index()
  List<String> get lastNameParts => lastName.split(RegExp(r'\w+'));

  @Index()
  String get deduplicatorName {
    var processedFirstName = firstName.toLowerCase().replaceAll(RegExp(r"\s+"), "");
    var processedLastName = lastName.toLowerCase().replaceAll(RegExp(r"\s+"), "");

    return "$processedFirstName$processedLastName";
  }

  // Additional biographical information
  String? ageCategoryName;

  @ignore
  AgeCategory? get ageCategory => sport.ageCategories.lookupByName(ageCategoryName);
  set ageCategory(AgeCategory? value) => ageCategoryName = value?.name;

  String? lastClassificationName;

  @ignore
  Classification? get lastClassification => sport.classifications.lookupByName(lastClassificationName);
  set lastClassification(Classification? c) => lastClassificationName = c?.name;

  String? divisionName;

  @ignore
  Division? get division => sport.divisions.lookupByName(divisionName);
  set division(Division? d) => divisionName = d?.name;

  @Index(composite: [CompositeIndex("group")], unique: true)
  @Backlink(to: "ratings")
  final project = IsarLink<DbRatingProject>();
  final group = IsarLink<DbRatingGroup>();

  /// All events belonging to this rating.
  final events = IsarLinks<DbRatingEvent>();

  int get length => events.countSync();

  double rating;
  double error;
  double connectedness;

  /// Use to store algorithm-specific double data.
  List<double> doubleData = [];
  /// Use to store algorithm-specific integer data.
  List<int> intData = [];

  DateTime firstSeen;
  DateTime lastSeen;

  List<DbRatingEvent> getEventsInWindowSync({int window = 0, int offset = 0}) {
    return AnalystDatabase().getRatingEventsForSync(this, limit: window, offset: offset);
  }

  DbShooterRating({
    required this.sportName,
    required this.firstName,
    required this.lastName,
    required super.memberNumber,
    required super.female,
    required this.rating,
    required this.error,
    required this.connectedness,
    required this.firstSeen,
    required this.lastSeen,
  }) : super(firstName: firstName, lastName: lastName);

  DbShooterRating.empty({
    required Sport sport,
    this.firstName = "",
    this.lastName = "",
    super.memberNumber = "",
    super.female = false,
    this.rating = 0.0,
    this.error = 0.0,
    this.connectedness = 0.0,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int doubleDataLength = 0,
    int intDataLength = 0,
  }) :
        this.firstSeen = firstSeen ?? DateTime(0),
        this.lastSeen = lastSeen ?? DateTime(0),
        this.sportName = sport.name,
        this.doubleData = List.filled(doubleDataLength, 0, growable: true),
        this.intData = List.filled(intDataLength, 0, growable: true),
        super(firstName: firstName, lastName: lastName);
}
