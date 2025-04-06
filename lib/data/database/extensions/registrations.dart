
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/registration.dart';
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
}
