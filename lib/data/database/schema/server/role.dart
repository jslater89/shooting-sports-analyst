import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/permission.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'role.g.dart';

@collection
class Role {
  Id get id => name.stableHash;

  @Index()
  String name;

  @enumerated
  List<Permission> permissions = [];

  List<UsageLimit> usageLimits = [];

  Role({
    required this.name,
    required this.permissions,
    this.usageLimits = const [],
  });
}

@embedded
class UsageLimit {
  String usageType = "";

  @ignore
  num get limit {
    var out = intLimit ?? doubleLimit;
    if(out == null) {
      throw StateError("missing limit");
    }
    return out;
  }

  int? intLimit;
  double? doubleLimit;

  UsageLimit();
  UsageLimit.int({
    required this.usageType,
    required this.intLimit,
  });
  UsageLimit.double({
    required this.usageType,
    required this.doubleLimit,
  });
}