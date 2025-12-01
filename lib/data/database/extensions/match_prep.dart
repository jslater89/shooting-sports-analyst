/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';

extension MatchPrepDatabase on AnalystDatabase {
  /// Get a future match by its internal ID.
  Future<FutureMatch?> getFutureMatchById(int id) async {
    return await isar.futureMatchs.get(id);
  }

  /// Get a future match by its match ID.
  Future<FutureMatch?> getFutureMatchByMatchId(String matchId) async {
    return await isar.futureMatchs.where().matchIdEqualTo(matchId).findFirst();
  }

  /// Get a future match by its match ID synchronously.
  FutureMatch? getFutureMatchByMatchIdSync(String matchId) {
    return isar.futureMatchs.where().matchIdEqualTo(matchId).findFirstSync();
  }

  /// Save a future match to the database.
  ///
  /// If [newRegistrations] is provided, the existing registrations on the
  /// FutureMatch will be deleted and replaced with the contents of [newRegistrations].
  Future<void> saveFutureMatch(FutureMatch match, {
    List<MatchPrepLinkTypes> updateLinks = MatchPrepLinkTypes.values,
    List<MatchRegistration>? newRegistrations,
  }) async {
    await isar.writeTxn(() async {
      await isar.futureMatchs.put(match);

      if(match.newRegistrations.isNotEmpty) {
        await isar.matchRegistrations.putAll(match.newRegistrations);
        match.registrations.addAll(match.newRegistrations);
        await match.registrations.save();
        match.newRegistrations.clear();
      }

      if(newRegistrations != null) {
        await match.registrations.filter().deleteAll();
        match.registrations.clear();
        match.registrations.addAll(newRegistrations);
        await isar.matchRegistrations.putAll(newRegistrations);
      }

      if(updateLinks.contains(MatchPrepLinkTypes.registrations)) {
        await match.registrations.save();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.mappings)) {
        await match.mappings.save();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.dbMatch)) {
        await match.dbMatch.save();
      }
    });
  }

  /// Save a future match to the database synchronously.
  ///
  /// If [newRegistrations] is provided, the existing registrations on the
  /// FutureMatch will be deleted and replaced with the contents of [newRegistrations].
  void saveFutureMatchSync(FutureMatch match, {
    List<MatchPrepLinkTypes> updateLinks = MatchPrepLinkTypes.values,
    List<MatchRegistration>? newRegistrations,
  }) {
    isar.writeTxnSync(() {
      isar.futureMatchs.putSync(match);

      if(match.newRegistrations.isNotEmpty) {
        isar.matchRegistrations.putAllSync(match.newRegistrations);
        match.registrations.addAll(match.newRegistrations);
        match.registrations.saveSync();
        match.newRegistrations.clear();
      }

      if(newRegistrations != null) {
        match.registrations.clear();
        match.registrations.addAll(newRegistrations);
        isar.matchRegistrations.putAllSync(newRegistrations);
      }
      if(updateLinks.contains(MatchPrepLinkTypes.registrations)) {
        match.registrations.saveSync();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.mappings)) {
        match.mappings.saveSync();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.dbMatch)) {
        match.dbMatch.saveSync();
      }
    });
  }

  Future<List<FutureMatch>> getFutureMatchesByName(String name) async {
    if(name.contains(" ")) {
      return await isar.futureMatchs.filter().eventNameContains(name).findAll();
    }
    else {
      return await isar.futureMatchs.where().eventNamePartsElementStartsWith(name).findAll();
    }
  }

  List<FutureMatch> getFutureMatchesByNameSync(String name) {
    if(name.contains(" ")) {
      return isar.futureMatchs.filter().eventNameContains(name).findAllSync();
    }
    else {
      return isar.futureMatchs.where().eventNamePartsElementStartsWith(name).findAllSync();
    }
  }
}

enum MatchPrepLinkTypes {
  registrations,
  mappings,
  dbMatch,
}
