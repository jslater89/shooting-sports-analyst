import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'migration.g.dart';

@collection
class MigrationRecord {
  Id get id => name.stableHash64;

  @Index()
  String name;

  DateTime applied;

  MigrationRecord({
    required this.name,
    required this.applied,
  });
}