/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

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
  Future<VoidResult> saveFutureMatch(FutureMatch match, {
    List<MatchPrepLinkTypes> updateLinks = MatchPrepLinkTypes.values,
    List<MatchRegistration>? newRegistrations,
  }) async {
    try {
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
    } catch(e) {
      return Result.err(StringError("Failed to save future match: $e"));
    }
    return Result.ok(null);
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

  /// Query future matches with pagination, sorting, and filtering.
  ///
  /// Similar to [AnalystDatabase.queryMatches] but for [FutureMatch].
  /// Note: Since FutureMatch doesn't have date/sportName indexes, filtering and sorting is done in memory.
  Future<List<FutureMatch>> queryFutureMatches({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    MatchSortField sort = const DateSort(),
    Sport? sport,
  }) async {
    // Load all matches and filter/sort in memory (FutureMatch is typically a smaller dataset)
    List<FutureMatch> matches = await isar.futureMatchs.where().findAll();

    // Apply filters in memory
    if (name != null && name.isNotEmpty) {
      var nameLower = name.toLowerCase();
      matches = matches.where((m) => m.eventName.toLowerCase().contains(nameLower)).toList();
    }

    if (sport != null) {
      matches = matches.where((m) => m.sportName == sport.name).toList();
    }

    if (after != null) {
      matches = matches.where((m) => m.date.isAfter(after) || m.date.isAtSameMomentAs(after)).toList();
    }

    if (before != null) {
      matches = matches.where((m) => m.date.isBefore(before) || m.date.isAtSameMomentAs(before)).toList();
    }

    // Apply sorting in memory (since FutureMatch doesn't have date/sportName indexes)
    switch (sort) {
      case NameSort():
        matches.sort((a, b) {
          var comparison = a.eventName.compareTo(b.eventName);
          return sort.desc ? -comparison : comparison;
        });
        break;
      case DateSort():
        matches.sort((a, b) {
          var comparison = a.date.compareTo(b.date);
          return sort.desc ? -comparison : comparison;
        });
        break;
    }

    // Apply pagination
    var start = page * pageSize;
    var end = start + pageSize;
    if (start >= matches.length) {
      return [];
    }
    if (end > matches.length) {
      end = matches.length;
    }
    return matches.sublist(start, end);
  }

  /// Return Isar future match IDs matching the query.
  ///
  /// Similar to [AnalystDatabase.queryMatchIds] but for [FutureMatch].
  /// Note: Since FutureMatch doesn't have date/sportName indexes, filtering and sorting is done in memory.
  Future<List<int>> queryFutureMatchIds({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    MatchSortField sort = const DateSort(),
    List<Sport>? sports,
  }) async {
    // Load all matches and filter/sort in memory (FutureMatch is typically a smaller dataset)
    List<FutureMatch> matches = await isar.futureMatchs.where().findAll();

    // Apply filters in memory
    if (name != null && name.isNotEmpty) {
      var nameLower = name.toLowerCase();
      matches = matches.where((m) => m.eventName.toLowerCase().contains(nameLower)).toList();
    }

    if (sports != null && sports.isNotEmpty) {
      var sportNames = sports.map((s) => s.name).toSet();
      matches = matches.where((m) => sportNames.contains(m.sportName)).toList();
    }

    if (after != null) {
      matches = matches.where((m) => m.date.isAfter(after) || m.date.isAtSameMomentAs(after)).toList();
    }

    if (before != null) {
      matches = matches.where((m) => m.date.isBefore(before) || m.date.isAtSameMomentAs(before)).toList();
    }

    // Apply sorting in memory (since FutureMatch doesn't have date/sportName indexes)
    switch (sort) {
      case NameSort():
        matches.sort((a, b) {
          var comparison = a.eventName.compareTo(b.eventName);
          return sort.desc ? -comparison : comparison;
        });
        break;
      case DateSort():
        matches.sort((a, b) {
          var comparison = a.date.compareTo(b.date);
          return sort.desc ? -comparison : comparison;
        });
        break;
    }

    // Apply pagination and get IDs
    var start = page * pageSize;
    var end = start + pageSize;
    if (start >= matches.length) {
      return [];
    }
    if (end > matches.length) {
      end = matches.length;
    }
    return matches.sublist(start, end).map((m) => m.id).toList();
  }

  /// Delete a future match by its internal ID.
  Future<void> deleteFutureMatch(int id) async {
    await isar.writeTxn(() async {
      await isar.futureMatchs.delete(id);
    });
  }
}

enum MatchPrepLinkTypes {
  registrations,
  mappings,
  dbMatch,
}
