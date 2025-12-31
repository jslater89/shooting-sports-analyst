/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("RegistrationDatabase");

extension RegistrationDatabase on AnalystDatabase {
  Future<List<MatchRegistrationMapping>> getMatchRegistrationMappings(String matchId) async {
    return await isar.matchRegistrationMappings.where().matchIdEqualTo(matchId).findAll();
  }

  Future<MatchRegistrationMapping?> getMatchRegistrationMappingByName({required String matchId, required String shooterName, required String shooterDivisionName}) async {
    return await isar.matchRegistrationMappings.where().matchIdShooterNameShooterDivisionNameEqualTo(matchId, shooterName, shooterDivisionName).findFirst();
  }

  Future<void> saveMatchRegistrationMappings(String matchId, List<MatchRegistrationMapping> mappings) async {
    await isar.writeTxn(() async {
      await isar.matchRegistrationMappings.putAll(mappings);
    });

    var futureMatch = await getFutureMatchByMatchId(matchId);
    if(futureMatch != null) {
      // Merge the new mappings with the existing mappings, preserving the new mappings
      // if there are conflicts.
      Set<MatchRegistrationMapping> newMappings = {...mappings, ...futureMatch.mappings};
      futureMatch.mappings.clear();
      futureMatch.mappings.addAll(newMappings);
      await saveFutureMatch(futureMatch);
    }
  }

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

  Future<void> saveMatchRegistrations(List<MatchRegistration> registrations) async {
    await isar.writeTxn(() async {
      await isar.matchRegistrations.putAll(registrations);
    });
  }

  void saveMatchRegistrationsSync(List<MatchRegistration> registrations) {
    isar.writeTxnSync(() {
      isar.matchRegistrations.putAllSync(registrations);
    });
  }
}
