import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/role.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/session.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

extension UserRoleDatabase on AnalystDatabase {
  Future<User?> getUserByUsername(String username) async {
    return await isar.users.where().usernameEqualTo(username).findFirst();
  }

  User? getUserByUsernameSync(String username) {
    return isar.users.where().usernameEqualTo(username).findFirstSync();
  }

  /// Get a user by their ID.
  Future<User?> getUserById(int id) async {
    return await isar.users.get(id);
  }

  User? getUserByIdSync(int id) {
    return isar.users.getSync(id);
  }

  Future<User?> getUserByEmail(String email) async {
    return await isar.users.where().emailEqualTo(email).findFirst();
  }

  User? getUserByEmailSync(String email) {
    return isar.users.where().emailEqualTo(email).findFirstSync();
  }

  Future<List<User>> getUsersForTierCheck() async {
    return await isar.users.filter()
      .availableAuthMethodsElementEqualTo(AuthMethod.patreonOauth)
      .patreonInfo((q) => q.nextTierCheckLessThan(DateTime.now())).findAll();
  }

  List<User> getUsersForTierCheckSync() {
    return isar.users.filter()
      .availableAuthMethodsElementEqualTo(AuthMethod.patreonOauth)
      .patreonInfo((q) => q.nextTierCheckLessThan(DateTime.now())).findAllSync();
  }

  Future<User> saveUser(User user, {bool saveLinks = true}) async {
    await isar.writeTxn(() async {
      await isar.users.put(user);

      if(saveLinks) {
        await user.roles.save();
        await user.fantasyUser.save();
        await user.predictionGamePlayers.save();
      }
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

  Future<Role?> getRoleByRoleId(String roleId) async {
    return await isar.roles.where().roleIdEqualTo(roleId).findFirst();
  }

  Role? getRoleByRoleIdSync(String roleId) {
    return isar.roles.where().roleIdEqualTo(roleId).findFirstSync();
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

  Future<Session?> getSessionBySessionId(String sessionId) async {
    return await isar.sessions.where().sessionIdEqualTo(sessionId).findFirst();
  }

  Session? getSessionBySessionIdSync(String sessionId) {
    return isar.sessions.where().sessionIdEqualTo(sessionId).findFirstSync();
  }

  Future<Session?> getSessionByJti(String jti) async {
    return await isar.sessions.where().jtiEqualTo(jti).findFirst();
  }

  Session? getSessionByJtiSync(String jti) {
    return isar.sessions.where().jtiEqualTo(jti).findFirstSync();
  }

  Future<List<Session>> getActiveSessions({User? user, int? limit}) async {
    var queryStart = isar.sessions.filter();
    if(user != null) {
      queryStart = queryStart.user((q) => q.idEqualTo(user.id));
    }
    var sortedQuery = queryStart.expiresGreaterThan(DateTime.now()).sortByExpires();
    if(limit != null) {
      return sortedQuery.limit(limit).findAll();
    }
    else {
      return sortedQuery.findAll();
    }
  }

  List<Session> getActiveSessionsSync({User? user, int? limit}) {
    var queryStart = isar.sessions.filter();
    if(user != null) {
      queryStart = queryStart.user((q) => q.idEqualTo(user.id));
    }
    var sortedQuery = queryStart.expiresGreaterThan(DateTime.now()).sortByExpires();
    if(limit != null) {
      return sortedQuery.limit(limit).findAllSync();
    }
    else {
      return sortedQuery.findAllSync();
    }
  }

  /// Query sessions by auth method and/or expiration date.
  Future<List<Session>> querySessions({
    AuthMethod? authMethod,
    DateTime? expiresBefore,
    bool activeOnly = true,
  }) async {

    var queryStart = isar.sessions.filter();
    QueryBuilder<Session, Session, QAfterFilterCondition>? query;
    if(authMethod != null) {
      query = queryStart.authMethodEqualTo(authMethod);
    }
    if(expiresBefore != null) {
      if(query != null) {
        query = query.expiresLessThan(expiresBefore);
      }
      else {
        query = queryStart.expiresLessThan(expiresBefore);
      }
    }
    if(activeOnly) {
      if(query != null) {
        query = query.expiresGreaterThan(DateTime.now());
      }
      else {
        query = queryStart.expiresGreaterThan(DateTime.now());
      }
    }

    if(query == null) {
      return isar.sessions.where().sortByExpires().findAll();
    }
    else {
      return await query.sortByExpires().findAll();
    }
  }

  /// Query sessions by auth method and/or expiration date synchronously.
  List<Session> querySessionsSync({
    AuthMethod? authMethod,
    DateTime? expiresBefore,
    bool activeOnly = true,
  }) {
    var queryStart = isar.sessions.filter();
    QueryBuilder<Session, Session, QAfterFilterCondition>? query;
    if(authMethod != null) {
      query = queryStart.authMethodEqualTo(authMethod);
    }
    if(expiresBefore != null) {
      if(query != null) {
        query = query.expiresLessThan(expiresBefore);
      }
      else {
        query = queryStart.expiresLessThan(expiresBefore);
      }
    }
    if(activeOnly) {
      if(query != null) {
        query = query.expiresGreaterThan(DateTime.now());
      }
      else {
        query = queryStart.expiresGreaterThan(DateTime.now());
      }
    }

    if(query == null) {
      return isar.sessions.where().sortByExpires().findAllSync();
    }
    else {
      return query.sortByExpires().findAllSync();
    }
  }

  Future<Session> saveSession(Session session) async {
    await isar.writeTxn(() async {
      await isar.sessions.put(session);
      await session.user.save();
    });
    return session;
  }

  Session saveSessionSync(Session session) {
    isar.writeTxnSync(() {
      isar.sessions.putSync(session);
    });
    return session;
  }

  Future<void> deleteSession(Session session) async {
    await isar.writeTxn(() async {
      await isar.sessions.delete(session.id);
    });
  }

  void deleteSessionSync(Session session) {
    isar.writeTxnSync(() {
      isar.sessions.deleteSync(session.id);
    });
  }

  Future<int> deleteExpiredSessions() async {
    return await isar.writeTxn(() async {
      return await isar.sessions.where().expiresLessThan(DateTime.now()).deleteAll();
    });
  }

  int deleteExpiredSessionsSync() {
    return isar.writeTxnSync(() {
      return isar.sessions.where().expiresLessThan(DateTime.now()).deleteAllSync();
    });
  }
}
