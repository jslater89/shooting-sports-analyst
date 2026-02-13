import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'entity_changes.g.dart';

@collection
class EntityChange {
  Id get id => combineHashList64([entityId.stableHash64, entityType.idHashCode]);

  @Index()
  @Index(composite: [CompositeIndex('entityType')])
  int entityId;

  @Enumerated(EnumType.name)
  EntityType entityType;

  @Index()
  DateTime timestamp;

  EntityChange({
    required this.entityId,
    required this.entityType,
    required this.timestamp,
  });
}

/// Entity types whose changes we can track.
enum EntityType {
  match,
  futureMatch,
  matchPrep,
  ratingProject;

  int get idHashCode => name.stableHash64;
}