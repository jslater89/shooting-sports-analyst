
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/entity_changes.dart';

extension EntityChangesExtension on AnalystDatabase {
  /// Clean up entity changes older than the given date.
  Future<void> cleanEntityChanges([DateTime? before]) async {
    if(before == null) {
      before = DateTime.now().subtract(const Duration(days: 30));
    }

    await isar.writeTxn(() async {
      await isar.entityChanges.where().timestampLessThan(before!).deleteAll();
    });
  }

  /// Clean up entity changes older than the given date synchronously.
  void cleanEntityChangesSync([DateTime? before]) {
    if(before == null) {
      before = DateTime.now().subtract(const Duration(days: 30));
    }

    isar.writeTxnSync(() {
      isar.entityChanges.where().timestampLessThan(before!).deleteAllSync();
    });
  }

  /// Notify the database that an entity has changed.
  Future<void> notifyEntityChange(EntityType entityType, int entityId) async {
    return isar.writeTxn(() async {
      await isar.entityChanges.put(EntityChange(entityId: entityId, entityType: entityType, timestamp: DateTime.now()));
    });
  }

  /// Get an entity change by its entity type and id.
  Future<EntityChange?> getEntityChange(EntityType entityType, int entityId) async {
    return await isar.entityChanges.where().entityIdEntityTypeEqualTo(entityId, entityType).findFirst();
  }

  /// Get an entity change by its entity type and id synchronously.
  EntityChange? getEntityChangeSync(EntityType entityType, int entityId) {
    return isar.entityChanges.where().entityIdEntityTypeEqualTo(entityId, entityType).findFirstSync();
  }

  /// Get all entity changes since the given date.
  Future<List<EntityChange>> getEntityChangesSince(DateTime since) async {
    return await isar.entityChanges.where().timestampGreaterThan(since).findAll();
  }

  /// Get all entity changes since the given date synchronously.
  List<EntityChange> getEntityChangesSinceSync(DateTime since) {
    return isar.entityChanges.where().timestampGreaterThan(since).findAllSync();
  }
}