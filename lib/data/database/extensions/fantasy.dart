/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';

Map<Id, FantasyPlayer> _fantasyPlayerCache = {};
extension FantasyDatabase on AnalystDatabase {

  Future<League?> getLeague(Id leagueId) async {
    return isar.leagues.get(leagueId);
  }

  /// Get all leagues that are currently active, i.e. those that need to be
  /// processed.
  Future<List<League>> getActiveLeagues() async {
    return isar.leagues.filter().stateEqualTo(LeagueState.active).findAll();
  }

  void clearFantasyPlayerCache() {
    _fantasyPlayerCache.clear();
  }

  FantasyPlayer? getPlayerByIdSync(Id id) {
    return isar.fantasyPlayers.getSync(id);
  }

  Future<FantasyPlayer?> getPlayerById(Id id) async {
    return await isar.fantasyPlayers.get(id);
  }

  Future<FantasyPlayer?> getPlayerFor({
    required DbShooterRating rating,
    required DbRatingProject project,
    required RatingGroup group,
    bool useCache = false,
    bool saveToCache = true,
    bool createIfMissing = false,
    bool saveCreatedPlayer = true,
    bool translateIpscUuids = false,
  }) async {
    var uuid = rating.group.value?.uuid ?? "";
    if(translateIpscUuids && uuid.startsWith("ipsc")) {
      uuid = UspsaRatingGroupsProvider.translateIpscUuid(uuid);
    }
    var id = FantasyPlayer.idFromEntityIdentifiers(
      sportName: rating.sportName,
      groupUuid: uuid,
      memberNumber: rating.originalMemberNumber,
      projectId: project.id,
    );

    if(useCache) {
      var cachedPlayer = _fantasyPlayerCache[id];
      if(cachedPlayer != null) {
        return cachedPlayer;
      }
    }

    var player = await isar.fantasyPlayers.get(id);
    if(player == null && createIfMissing) {
      player = FantasyPlayer.fromRating(rating, groupUuidOverride: uuid);
      if(saveCreatedPlayer) {
        await isar.writeTxn(() async {
          await isar.fantasyPlayers.put(player!);
          await player.rating.save();
        });
      }
    }

    if(saveToCache && player != null) {
      _fantasyPlayerCache[id] = player;
    }
    return player;
  }

  FantasyPlayer? getPlayerForSync({
    required DbShooterRating rating,
    required DbRatingProject project,
    required RatingGroup group,
    bool useCache = false,
    bool saveToCache = true,
    bool createIfMissing = false,
    bool saveCreatedPlayer = true,
    bool translateIpscUuids = false,
  }) {
    var uuid = rating.group.value?.uuid ?? "";
    if(translateIpscUuids && uuid.startsWith("ipsc")) {
      uuid = UspsaRatingGroupsProvider.translateIpscUuid(uuid);
    }
    var id = FantasyPlayer.idFromEntityIdentifiers(
      sportName: rating.sportName,
      groupUuid: uuid,
      memberNumber: rating.originalMemberNumber,
      projectId: project.id,
    );

    if(useCache) {
      var cachedPlayer = _fantasyPlayerCache[id];
      if(cachedPlayer != null) {
        return cachedPlayer;
      }
    }

    var player = isar.fantasyPlayers.getSync(id);
    if(player == null && createIfMissing) {
      player = FantasyPlayer.fromRating(rating, groupUuidOverride: uuid);
      if(saveCreatedPlayer) {
        isar.writeTxnSync(() {
          isar.fantasyPlayers.putSync(player!);
        });
      }
    }
    if(saveToCache && player != null) {
      _fantasyPlayerCache[id] = player;
    }
    return player;
  }

  List<PlayerMatchPerformance> getMatchPerformancesForProjectGroupSync({
    required DbRatingProject project,
    required RatingGroup group,
    DateTime? before,
    DateTime? after,
  }) {
    return getMatchPerformancesForProjectGroupIdsSync(
      projectId: project.id,
      groupUuid: group.uuid,
      before: before,
      after: after,
    );
  }

  List<PlayerMatchPerformance> getMatchPerformancesForProjectGroupIdsSync({
    required int projectId,
    required String groupUuid,
    DateTime? before,
    DateTime? after,
  }) {
    var preDateBuilder = isar.playerMatchPerformances
      .where()
      .projectIdGroupUuidEqualTo(projectId, groupUuid);


    if(before != null && after != null) {
      return preDateBuilder.filter().matchDateBetween(after, before).findAllSync();
    }
    else if(before != null) {
      return preDateBuilder.filter().matchDateLessThan(before).findAllSync();
    }
    else if(after != null) {
      return preDateBuilder.filter().matchDateGreaterThan(after).findAllSync();
    }
    else {
      return preDateBuilder.findAllSync();
    }
  }

  Future<int> saveMatchPerformances(List<PlayerMatchPerformance> performances) async {
    return await isar.writeTxn(() async {
      await isar.playerMatchPerformances.putAll(performances);
      return performances.length;
    });
  }

  int saveMatchPerformancesSync(List<PlayerMatchPerformance> performances) {
    return isar.writeTxnSync(() {
      isar.playerMatchPerformances.putAllSync(performances);
      return performances.length;
    });
  }
}
