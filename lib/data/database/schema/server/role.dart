import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/permission.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'role.g.dart';

@collection
class Role {
  Id get id => roleId.stableHash;

  @Index()
  String name;

  @Index()
  String roleId;

  @Enumerated(EnumType.value, 'permissionName')
  List<Permission> permissions = [];

  List<UsageInfo> usageLimits = [];

  Role({
    required this.name,
    required this.roleId,
    required this.permissions,
    this.usageLimits = const [],
  });
}

/// Information about the allowed usage or limits for a role.
@embedded
class UsageInfo {
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

  UsageInfo();
  UsageInfo.int({
    required this.usageType,
    required this.intLimit,
  });
  UsageInfo.double({
    required this.usageType,
    required this.doubleLimit,
  });
}