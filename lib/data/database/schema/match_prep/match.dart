/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match.g.dart';

/// A FutureMatch is a match that has not yet occurred, including information about registration
/// and predictions. Its database ID is a stable hash of the match ID string, so it is stable
/// as long as the string match ID is stable.
@collection
class FutureMatch {
  Id get id => matchId.stableHash;
  @Index()
  String matchId;

  /// The name of the event.
  String eventName;

  @Index(name: AnalystDatabase.eventNamePartsIndex, type: IndexType.value, caseSensitive: false)
  /// The event name, split by words.
  List<String> get eventNameParts => Isar.splitWords(eventName);

  /// The start date of the event.
  @Index(name: AnalystDatabase.dateIndex)
  DateTime date;

  /// A convenience property for the start date of the event.
  ///
  /// Equivalent to [date] for backward compatibility.
  @ignore
  DateTime get startDate => date;

  /// The end date of the event.
  @Index()
  DateTime? endDate;

  /// The sport of the event.
  String sportName;
  /// The source code of the event, if available.
  String? sourceCode;
  /// The source IDs of the event, if available.
  List<String>? sourceIds;

  /// Associate a [DbShootingMatch] with this [FutureMatch].
  ///
  /// If [save] is true, the changes will be persisted to the database.
  Future<void> associateDbMatch(DbShootingMatch match, {bool save = true}) async {
    dbMatch.value = match;
    sourceCode = match.sourceCode;
    sourceIds = [...match.sourceIds];
    if(save) {
      await AnalystDatabase().saveFutureMatch(this, updateLinks: [MatchPrepLinkTypes.dbMatch]);
    }
  }

  /// Associate a [DbShootingMatch] with this [FutureMatch] synchronously.
  void associateDbMatchSync(DbShootingMatch match, {bool save = true}) {
    dbMatch.value = match;
    sourceCode = match.sourceCode;
    sourceIds = [...match.sourceIds];
    if(save) {
      AnalystDatabase().saveFutureMatchSync(this, updateLinks: [MatchPrepLinkTypes.dbMatch]);
    }
  }

  /// Find the registrations for a given sport and rating group.
  List<MatchRegistration> getRegistrationsFor(Sport sport, {RatingGroup? group = null, List<String>? squads = null, bool fallbackDivision = true}) {
    List<MatchRegistration> matchedRegistrations = [];
    if(group == null) {
      matchedRegistrations = registrations.toList();
    }
    else {
      for(var registration in registrations) {
        var division = sport.divisions.lookupByName(registration.shooterDivisionName, fallback: fallbackDivision);
        if(division == null) {
          continue;
        }
        if(group.containsDivision(division)) {
          matchedRegistrations.add(registration);
        }
      }
    }

    if(squads != null) {
      matchedRegistrations = matchedRegistrations.where((registration) => squads.contains(registration.squad)).toList();
    }
    return matchedRegistrations;
  }

  /// Find the unmatched registrations for a given sport and rating group.
  List<MatchRegistration> getUnmatchedRegistrationsFor(Sport sport, [RatingGroup? group]) {
    List<MatchRegistration> unmatched = [];
    for(var registration in getRegistrationsFor(sport, group: group)) {
      if(registration.shooterMemberNumbers.isEmpty) {
        unmatched.add(registration);
      }
    }
    return unmatched;
  }

  /// Attempt to match registrations (optionally for a given rating group) to known
  /// competitors from a list of possible shooter ratings, by comparing name, division, and classification.
  Future<void> matchRegistrationsToRatings(Sport sport, List<ShooterRating> ratings, {RatingGroup? group}) async {
    var unmatched = getUnmatchedRegistrationsFor(sport, group);

    List<MatchRegistration> updateRequired = [];
    for(var registration in unmatched) {
      var rating = ratings.firstWhereOrNull((r) =>
        r.name.toLowerCase() == registration.shooterName?.toLowerCase()
        && r.division?.name == registration.shooterDivisionName
        && r.lastClassification?.name == registration.shooterClassificationName
      );
      if(rating != null) {
        registration.shooterMemberNumbers = rating.knownMemberNumbers.toList();
        updateRequired.add(registration);
      }
    }

    if(updateRequired.isNotEmpty) {
      await AnalystDatabase().saveMatchRegistrations(updateRequired);
    }
  }

  /// Update the saved registrations for this match from its saved mappings.
  ///
  /// Returns the number of registrations updated.
  Future<int> updateRegistrationsFromMappings() async {
    var db = AnalystDatabase();
    var mappings = await db.getMatchRegistrationMappings(matchId);
    List<MatchRegistration> registrationsToUpdate = [];
    for(var mapping in mappings) {
      var registration = registrations.firstWhereOrNull((r) =>
        r.shooterName == mapping.shooterName
        && r.shooterDivisionName == mapping.shooterDivisionName
        && r.shooterClassificationName == mapping.shooterClassificationName
        /// If any numbers from the mapping are not in the registration, we need
        /// to update the registration.
        && !mapping.detectedMemberNumbers.every((n) => r.shooterMemberNumbers.contains(n)));

      if(registration != null) {
        registration.shooterMemberNumbers = mapping.detectedMemberNumbers.toList();
        registrationsToUpdate.add(registration);
      }
    }

    if(registrationsToUpdate.isNotEmpty) {
      await db.saveMatchRegistrations(registrationsToUpdate);
    }
    return registrationsToUpdate.length;
  }

  /// Once this match has occurred and been saved to the local database, this will
  /// contain the corresponding [DbShootingMatch].
  final dbMatch = IsarLink<DbShootingMatch>();

  /// Registrations parsed for this match.
  final registrations = IsarLinks<MatchRegistration>();

  @ignore
  List<MatchRegistration> newRegistrations;

  /// Mappings of registrations to known shooters for this match.
  final mappings = IsarLinks<MatchRegistrationMapping>();

  /// Check if a mapping exists for a given registration.
  bool hasMappingFor(MatchRegistration registration) {
    return mappings.any((m) => m.matchesRegistration(registration));
  }

  /// Get a mapping for a given registration, if it exists.
  MatchRegistrationMapping? getMappingFor(MatchRegistration registration) {
    return mappings.firstWhereOrNull((m) => m.matchesRegistration(registration));
  }

  FutureMatch({
    required this.matchId,
    required this.eventName,
    required this.date,
    required this.sportName,
    required this.sourceCode,
    required this.sourceIds,
    this.newRegistrations = const [],
  });

  @override
  String toString() {
    return "$eventName ($matchId) (${programmerYmdFormat.format(date)})";
  }
}
