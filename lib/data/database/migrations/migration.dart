import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/migrations/add_subjects_to_wagers.dart';
import 'package:shooting_sports_analyst/data/database/schema/migration.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("Migrations");

/// A base class for database migrations.
///
/// Isar does most migrations automatically, but some (particularly where fields
/// are added and should have data in them) need additional manual handling.
///
/// Subclasses should implement [doMigration] to perform the migration, and
/// [record] to return the migration record.
abstract class Migration {
  MigrationRecord get record;

  Future<void> doMigration(AnalystDatabase db);

  Future<void> checkAndApply(AnalystDatabase db) async {
    var existing = await db.isar.migrationRecords.where().nameEqualTo(record.name).findFirst();
    if(existing == null) {
      await doMigration(db);
      await db.isar.writeTxn(() async {
        await db.isar.migrationRecords.put(record);
      });
      _log.i("Applied migration ${record.name}");
    }
    else {
      _log.v("Migration ${record.name} was already applied at ${programmerYmdHmFormat.format(existing.applied)}");
    }
  }

  static List<Migration> availableMigrations = [
    AddSubjectsToWagers(),
    FixWagerTransactions(),
  ];
}