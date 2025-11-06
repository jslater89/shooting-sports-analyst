/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("RegistrationDatabase");

extension RegistrationDatabase on AnalystDatabase {

  /// Retrieve all stored registrations for a match.
  Future<List<DbMatchRegistration>> getMatchRegistrationsForMatch(String matchId) async {
    return await isar.dbMatchRegistrations.where().matchIdEqualTo(matchId).findAll();
  }

  /// Save a list of registrations for a match.
  ///
  /// Prefer to use [FutureMatch.setRegistrations] or [FutureMatch.setRegistrationsSync] instead,
  /// which will also update the links on the [FutureMatch] object.
  Future<void> saveMatchRegistrations(List<DbMatchRegistration> registrations) async {
    await isar.writeTxn(() async {
      await isar.dbMatchRegistrations.putAll(registrations);
    });
  }

  /// Save a list of registrations for a match synchronously.
  ///
  /// Prefer to use [FutureMatch.setRegistrationsSync] instead,
  /// which will also update the links on the [FutureMatch] object.
  void saveMatchRegistrationsSync(List<DbMatchRegistration> registrations) {
    isar.writeTxnSync(() {
      isar.dbMatchRegistrations.putAllSync(registrations);
    });
  }

  Future<List<MatchRegistrationMapping>> getMatchRegistrationMappings(String matchId) async {
    return await isar.matchRegistrationMappings.where().matchIdEqualTo(matchId).findAll();
  }

  Future<MatchRegistrationMapping?> getMatchRegistrationMappingByName({required String matchId, required String shooterName, required String shooterDivisionName}) async {
    return await isar.matchRegistrationMappings.where().matchIdShooterNameShooterDivisionNameEqualTo(matchId, shooterName, shooterDivisionName).findFirst();
  }

  /// Save a list of registration mappings for a match.
  ///
  /// Prefer to use [FutureMatch.updateRegistrationMappings] instead,
  /// which will also update the links on the [FutureMatch] object.
  Future<void> saveMatchRegistrationMappings(String matchId, List<MatchRegistrationMapping> mappings) async {
    await isar.writeTxn(() async {
      await isar.matchRegistrationMappings.putAll(mappings);
    });
  }

  /// Delete a list of registration mappings for a match synchronously.
  Future<void> deleteMatchRegistrationMappings(List<MatchRegistrationMapping> mappings) async {
    await isar.writeTxn(() async {
      int totalDeleted = 0;
      for(var mapping in mappings) {
        int deleteCount = await isar.matchRegistrationMappings.where().idEqualTo(mapping.id).deleteAll();
        totalDeleted += deleteCount;
      }
      _log.v("Deleted $totalDeleted match registration mappings");
    });
  }

  /// Delete a list of registration mappings for a match by competitor names.
  Future<void> deleteMatchRegistrationMappingsByNames({required String matchId, required List<String> shooterNames}) async {
    await isar.writeTxn(() async {
      int totalDeleted = 0;
      for(var shooterName in shooterNames) {
        int deleteCount = await isar.matchRegistrationMappings.where().matchIdShooterNameEqualTo(matchId, shooterName).deleteAll();
        totalDeleted += deleteCount;
      }
      _log.v("Deleted $totalDeleted match registration mappings");
    });
  }
}
