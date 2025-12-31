/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/future_match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/util.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("FutureMatchDatabase");

extension FutureMatchDatabase on AnalystDatabase {
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
    var sport = SportRegistry().lookup(match.sportName, caseSensitive: false);
    if(sport == null) {
      _log.w("Unknown sport in future match: ${match.sportName}");
    }
    else {
      // normalize to the canonically-cased name
      match.sportName = sport.name;
    }
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
    var sport = SportRegistry().lookup(match.sportName, caseSensitive: false);
    if(sport == null) {
      _log.w("Unknown sport in future match: ${match.sportName}");
    }
    else {
      // normalize to the canonically-cased name
      match.sportName = sport.name;
    }
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
    return queryFutureMatches(name: name);
  }

  /// Query future matches with pagination, sorting, and filtering.
  ///
  /// Similar to [AnalystDatabase.queryMatches] but for [FutureMatch].
  Future<List<FutureMatch>> queryFutureMatches({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    FutureMatchSortField sort = const DateSort(),
    Sport? sport,
  }) async {
    List<FutureMatchQueryElement> elements = [
      if(name != null)
        NamePartsQuery(name),
      if(sport != null)
        SportQuery([sport]),
      if(after != null || before != null)
        DateQuery(after: after, before: before),
    ];
    var query = _buildFutureMatchQuery(
      elements,
      sort: sort,
      limit: pageSize,
      offset: page * pageSize,
    );
    var matches = await query.findAll();
    return matches;
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
    FutureMatchSortField sort = const DateSort(),
    List<Sport>? sports,
  }) async {
    List<FutureMatchQueryElement> elements = [
      if(name != null)
        NamePartsQuery(name),
      if(sports != null && sports.isNotEmpty)
        SportQuery(sports),
      if(after != null || before != null)
        DateQuery(after: after, before: before),
    ];
    var query = _buildFutureMatchIdQuery(elements, sort: sort);
    var ids = await query.findAll();
    return ids;
  }

  /// Delete a future match by its internal ID.
  Future<void> deleteFutureMatch(int id) async {
    await isar.writeTxn(() async {
      await isar.futureMatchs.delete(id);
    });
  }

  Query<FutureMatch> _buildFutureMatchQuery(List<FutureMatchQueryElement> elements, {
    int? limit,
    int? offset,
    FutureMatchSortField sort = const DateSort(),
  }) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildFutureMatchQueryElements(
      elements,
      sort: sort,
      limit: limit,
      offset: offset,
    );

    Query<FutureMatch> query = this.isar.futureMatchs.buildQuery(
      whereClauses: whereElement?.whereClauses ?? [],
      filter: filterElements.isEmpty ? null : FilterGroup.and([
        for(var f in filterElements)
          if(f.filterCondition != null)
            f.filterCondition!,
      ]),
      sortBy: sortProperties,
      whereSort: whereSort,
      limit: limit,
      offset: offset,
    );

    return query;
  }

  Query<int> _buildFutureMatchIdQuery(List<FutureMatchQueryElement> elements, {
    int? limit,
    int? offset,
    FutureMatchSortField sort = const DateSort(),
  }) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildFutureMatchQueryElements(
      elements,
      sort: sort,
      limit: limit,
      offset: offset,
    );

    Query<int> query = this.isar.futureMatchs.buildQuery(
      whereClauses: whereElement?.whereClauses ?? [],
      filter: filterElements.isEmpty ? null : FilterGroup.and([
        for(var f in filterElements)
          if(f.filterCondition != null)
            f.filterCondition!,
      ]),
      sortBy: sortProperties,
      property: "id",
      whereSort: whereSort,
      limit: limit,
      offset: offset,
    );

    return query;
  }

  (FutureMatchQueryElement?, Iterable<FutureMatchQueryElement>, List<SortProperty>, Sort) _buildFutureMatchQueryElements(List<FutureMatchQueryElement> elements, {
    int? limit,
    int? offset,
    FutureMatchSortField sort = const DateSort(),
  }) {
    NamePartsQuery? nameQuery;
    NameSortQuery? nameSortQuery;
    DateQuery? dateQuery;
    SportQuery? sportQuery;

    for(var e in elements) {
      switch(e) {
        case NamePartsQuery():
          nameQuery = e;
        case NameSortQuery():
          nameSortQuery = e;
        case DateQuery():
          dateQuery = e;
        case SportQuery():
          sportQuery = e;
      }
    }

    // Defaults. Prefer strongly to 'where' by our sort. Since we do limit/offset
    // for paging, unless an alternate 'where' is highly selective, leaning on the
    // index for sort is probably preferable.
    FutureMatchQueryElement? whereElement;
    Iterable<FutureMatchQueryElement> filterElements = elements;
    if(dateQuery == null && (sort is DateSort)) {
      dateQuery = DateQuery(before: null, after: null);
      whereElement = dateQuery;
    }
    else if(nameSortQuery == null && (sort is NameSort)) {
      nameSortQuery = NameSortQuery();
      whereElement = nameQuery;
    }
    (whereElement, filterElements) =  buildQueryElementLists(elements, whereElement);

    if(nameQuery?.canWhere ?? false) {
      nameQuery!;

      // If we have a one-word name query of sufficient length, prefer to 'where'
      // on it, since high selectivity will probably outweigh the fast sort on
      // by the other index.
      if(nameQuery.name.length >= 3) {
        (whereElement, filterElements) = buildQueryElementLists(elements, nameQuery);
      }
    }

    var (sortProperties, whereSort) = _buildFutureMatchSortFields(whereElement, sort);

    return (whereElement, filterElements, sortProperties, whereSort);
  }

  (List<SortProperty>, Sort) _buildFutureMatchSortFields(FutureMatchQueryElement? whereElement, FutureMatchSortField sort) {
    var direction = sort.desc ? Sort.desc : Sort.asc;
    switch(sort) {
      case NameSort():
        if(whereElement is NameSortQuery) {
          return ([], direction);
        }
        else {
          return ([SortProperty(property: NameSortQuery().property, sort: direction)], direction);
        }
      case DateSort():
        if(whereElement is DateQuery) {
          return ([], direction);
        }
        else {
          return ([SortProperty(property: DateQuery().property, sort: direction)], direction);
        }
    }
  }
}

enum MatchPrepLinkTypes {
  registrations,
  mappings,
  dbMatch,
}
