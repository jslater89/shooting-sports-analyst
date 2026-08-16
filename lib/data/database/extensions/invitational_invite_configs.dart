/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:isar_community/isar.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/schema/invitational_invite_config.dart";

extension InvitationalInviteConfigDatabase on AnalystDatabase {
  Future<List<DbInvitationalInviteConfig>> getInvitationalInviteConfigs() async {
    return await isar.dbInvitationalInviteConfigs.where().sortByName().findAll();
  }

  List<DbInvitationalInviteConfig> getInvitationalInviteConfigsSync() {
    return isar.dbInvitationalInviteConfigs.where().sortByName().findAllSync();
  }

  Future<DbInvitationalInviteConfig?> getInvitationalInviteConfig(int id) async {
    return await isar.dbInvitationalInviteConfigs.get(id);
  }

  DbInvitationalInviteConfig? getInvitationalInviteConfigSync(int id) {
    return isar.dbInvitationalInviteConfigs.getSync(id);
  }

  Future<int> saveInvitationalInviteConfig(DbInvitationalInviteConfig config) async {
    return await isar.writeTxn(() async {
      return await isar.dbInvitationalInviteConfigs.put(config);
    });
  }

  int saveInvitationalInviteConfigSync(DbInvitationalInviteConfig config) {
    return isar.writeTxnSync(() {
      return isar.dbInvitationalInviteConfigs.putSync(config);
    });
  }

  Future<bool> deleteInvitationalInviteConfig(int id) async {
    return await isar.writeTxn(() async {
      return await isar.dbInvitationalInviteConfigs.delete(id);
    });
  }

  bool deleteInvitationalInviteConfigSync(int id) {
    return isar.writeTxnSync(() {
      return isar.dbInvitationalInviteConfigs.deleteSync(id);
    });
  }
}
