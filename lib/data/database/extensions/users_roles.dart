import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/role.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

extension UserRoleDatabase on AnalystDatabase {
  Future<User?> getUserByUsername(String username) async {
    return await isar.users.filter().usernameEqualTo(username).findFirst();
  }

  /// Get a user by their ID.
  Future<User?> getUserById(int id) async {
    return await isar.users.get(id);
  }

  Future<User> saveUser(User user) async {
    await isar.writeTxn(() async {
      await isar.users.put(user);
    });
    return user;
  }

  User saveUserSync(User user) {
    isar.writeTxnSync(() {
      isar.users.putSync(user);
    });
    return user;
  }

  /// Get a role by its name.
  Future<Role?> getRoleByName(String name) async {
    return await isar.roles.where().nameEqualTo(name).findFirst();
  }

  /// Get a role by its name synchronously.
  Role? getRoleByNameSync(String name) {
    return isar.roles.where().nameEqualTo(name).findFirstSync();
  }

  Future<List<Role>> saveAllRoles(List<Role> roles) async {
    await isar.writeTxn(() async {
      await isar.roles.putAll(roles);
    });
    return roles;
  }

  List<Role> saveAllRolesSync(List<Role> roles) {
    isar.writeTxnSync(() {
      isar.roles.putAllSync(roles);
    });
    return roles;
  }

  /// Save a role to the database.
  Future<Role> saveRole(Role role) async {
    await isar.writeTxn(() async {
      await isar.roles.put(role);
    });
    return role;
  }

  /// Save a role to the database synchronously.
  Role saveRoleSync(Role role) {
    isar.writeTxnSync(() {
      isar.roles.putSync(role);
    });
    return role;
  }
}
