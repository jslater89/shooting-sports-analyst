/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/extensions/registrations.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'match.g.dart';

/// A FutureMatch is a match that has not yet occurred, including information about registration
/// and predictions.
@collection
class FutureMatch {
  Id get id => matchId.stableHash;
  @Index()
  String matchId;
  /// The name of the event.
  String eventName;
  /// The date of the event.
  DateTime date;
  /// The sport of the event.
  String sportName;
  /// The source code of the event, if available.
  String? sourceCode;
  /// The source IDs of the event, if available.
  List<String>? sourceIds;

  DateTime updated;

  /// Associate a [DbShootingMatch] with this [FutureMatch].
  ///
  /// If [save] is true, the changes will be persisted to the database.
  Future<void> associateDbMatch(DbShootingMatch match, {bool save = true}) async {
    dbMatch.value = match;
    sourceCode = match.sourceCode;
    sourceIds = [...match.sourceIds];
    updated = DateTime.now();
    if(save) {
      await AnalystDatabase().saveFutureMatch(this, updateLinks: [MatchPrepLinkTypes.dbMatch]);
    }
  }

  /// Associate a [DbShootingMatch] with this [FutureMatch] synchronously.
  void associateDbMatchSync(DbShootingMatch match, {bool save = true}) {
    dbMatch.value = match;
    sourceCode = match.sourceCode;
    sourceIds = [...match.sourceIds];
    updated = DateTime.now();
    if(save) {
      AnalystDatabase().saveFutureMatchSync(this, updateLinks: [MatchPrepLinkTypes.dbMatch]);
    }
  }

  /// Set the registrations for this match to the provided value.
  Future<void> setRegistrations(List<DbMatchRegistration> registrations, {bool save = true}) async {
    await AnalystDatabase().saveMatchRegistrations(registrations);
    this.registrations.clear();
    this.registrations.addAll(registrations);
    updated = DateTime.now();
    if(save) {
      await AnalystDatabase().saveFutureMatch(this, updateLinks: [MatchPrepLinkTypes.registrations]);
    }
  }

  /// Set the registrations for this match to the provided value synchronously.
  void setRegistrationsSync(List<DbMatchRegistration> registrations, {bool save = true}) {
    AnalystDatabase().saveMatchRegistrationsSync(registrations);
    this.registrations.clear();
    this.registrations.addAll(registrations);
    updated = DateTime.now();
    if(save) {
      AnalystDatabase().saveFutureMatchSync(this, updateLinks: [MatchPrepLinkTypes.registrations]);
    }
  }

  /// Update the registration mappings for this match, clearing the existing mapping list, adding the new mappings, and deleting all mappings
  /// in [deletedMappings].
  Future<void> updateRegistrationMappings({required List<MatchRegistrationMapping> newMappings, required List<MatchRegistrationMapping> deletedMappings, bool save = true}) async {
    await AnalystDatabase().saveMatchRegistrationMappings(matchId, newMappings);
    await AnalystDatabase().deleteMatchRegistrationMappings(deletedMappings);
    this.mappings.clear();
    this.mappings.addAll(newMappings);
    updated = DateTime.now();
    if(save) {
      await AnalystDatabase().saveFutureMatch(this, updateLinks: [MatchPrepLinkTypes.mappings]);
    }
  }

  /// Once this match has occurred and been saved to the local database, this will
  /// contain the corresponding [DbShootingMatch].
  final dbMatch = IsarLink<DbShootingMatch>();

  /// Registrations parsed for this match.
  final registrations = IsarLinks<DbMatchRegistration>();

  /// Mappings of registrations to known shooters for this match.
  final mappings = IsarLinks<MatchRegistrationMapping>();

  FutureMatch({
    required this.matchId,
    required this.eventName,
    required this.date,
    required this.sportName,
    required this.sourceCode,
    required this.sourceIds,
  }) : updated = DateTime.now();
}
