/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/match/match_query_element.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/fantasy_user.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/league.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/matchups.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/player.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/roster.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/standing.dart';
import 'package:shooting_sports_analyst/data/database/schema/fantasy/team.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/preferences.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/data/database/util.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:string_similarity/string_similarity.dart';

var _log = SSALogger("AnalystDb");

class AnalystDatabase {
  static const knownMemberNumbersIndex = "knownMemberNumbers";
  static const allPossibleMemberNumbersIndex = "allPossibleMemberNumbers";
  static const eventNamePartsIndex = "eventNameParts";
  static const sourceIdsIndex = "sourceIds";
  static const dateIndex = "date";
  static const sportNameIndex = "sportName";
  static const memberNumbersAppearingIndex = "memberNumbersAppearing";
  static Future<void> get readyStatic => _readyCompleter.future;
  static Completer<void> _readyCompleter = Completer();

  static const maxSizeMiB = 1024 * 32;
  static int get maxSizeBytes => maxSizeMiB * 1024 * 1024;

  Future<void> get ready => readyStatic;

  static AnalystDatabase? _instance;
  factory AnalystDatabase() {
    if(_instance == null) {
      _instance = AnalystDatabase._();
      _instance!._init();
    }
    return _instance!;
  }

  AnalystDatabase.path(String path) {
    _instance = AnalystDatabase._();
    _instance!._init(path: path);
  }

  static AnalystDatabase? _testInstance;
  factory AnalystDatabase.test() {
    if(_testInstance == null) {
      _testInstance = AnalystDatabase._();
      _testInstance!._init(test: true);
    }
    return _testInstance!;
  }

  late Isar isar;

  Future<void> _init({bool test = false, String? path}) async {
    var db = Directory(path ?? "db/");
    if(!db.existsSync()) {
      db.createSync(recursive: true);
    }
    try {
      isar = await Isar.open(
        [
          // Rating-related collections
          DbShootingMatchSchema,
          StandaloneDbMatchEntrySchema,
          DbRatingProjectSchema,
          RatingGroupSchema,
          RatingSetSchema,
          DbRatingEventSchema,
          DbShooterRatingSchema,
          MatchHeatSchema,
          ApplicationPreferencesSchema,

          // Match prep-related collections
          FutureMatchSchema,
          MatchRegistrationSchema,
          MatchRegistrationMappingSchema,

          // Fantasy-related collections
          FantasyUserSchema,
          LeagueSchema,
          FantasyRosterSlotTypeSchema,
          RosterSlotSchema,
          LeagueStandingSchema,
          LeagueSeasonSchema,
          LeagueMonthSchema,
          TeamSchema,
          FantasyPlayerSchema,
          MatchupSchema,
          PlayerMatchPerformanceSchema,
          PlayerMonthlyPerformanceSchema,
          MonthlyRosterSchema,
          RosterAssignmentSchema,
        ],
        maxSizeMiB: 1024 * 32,
        directory: db.path,
        name: test ? "test-database" : "database",
      );
    }
    on IsarError catch(e, stackTrace) {
      _log.e("Failed to open database with IsarError", error: e, stackTrace: stackTrace);
      rethrow;
    }
    catch(e, stackTrace) {
      _log.e("Failed to open database", error: e, stackTrace: stackTrace);
      rethrow;
    }

    // TODO Fix for broken IDPA databases; remove after releasing alpha11
    var provider = idpaSport.builtinRatingGroupsProvider;
    if(provider != null && (await isar.ratingGroups.getByUuid("icore-pcc")) != null) {
      int deleted = 0;
      for(var group in provider.builtinRatingGroups) {
        var wrongId = group.uuid.replaceFirst("idpa-", "icore-");
        await isar.writeTxn(() async {
          await isar.ratingGroups.deleteByUuid(wrongId);
          await isar.ratingGroups.put(group);
        });
        deleted += 1;
      }
      _log.i("Fixed $deleted broken IDPA rating groups");
    }

    await isar.writeTxn(() async {
      for(var sport in SportRegistry().availableSports) {
        var provider = sport.builtinRatingGroupsProvider;
        if(provider != null) {
          await isar.ratingGroups.putAll(provider.builtinRatingGroups);
        }
      }

      // TODO: fantasy initialization here
    });

    _readyCompleter.complete();
  }

  AnalystDatabase._();

  /// Perform a synchronous write transaction.
  T writeTxnSync<T>(T Function() txn, {bool silent = false}) {
    // Making my life slightly easier if I ever want to move off of Isar.
    return isar.writeTxnSync(txn, silent: silent);
  }

  /// Contains a cache of shooter ratings. By default, [knownShooter] and [maybeKnownShooter]
  /// will not read from the cache. By default, ratings will be saved to the cache when
  /// inserted, updated, or read.
  Map<RatingGroup, Map<String, DbShooterRating>> loadedShooterRatingCache = {};
  DbShooterRating? lookupCachedRating(RatingGroup group, String memberNumber) {
    return loadedShooterRatingCache[group]?[memberNumber];
  }
  void cacheRating(RatingGroup group, DbShooterRating rating) {
    loadedShooterRatingCache[group] ??= {};
    for(var n in rating.allPossibleMemberNumbers) {
      loadedShooterRatingCache[group]![n] = rating;
    }
  }
  void clearLoadedShooterRatingCache() {
    loadedShooterRatingCache.clear();
    loadedShooterRatingCacheHits = 0;
    loadedShooterRatingCacheMisses = 0;
  }
  int loadedShooterRatingCacheHits = 0;
  int loadedShooterRatingCacheMisses = 0;

  /// The standard match query: index on name if present or date if not.
  Future<List<DbShootingMatch>> queryMatches({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    MatchSortField sort = const DateSort(),
    Sport? sport,
  }) {
    Query<DbShootingMatch> finalQuery = _buildMatchQuery(
      [
        if(name != null)
          NamePartsQuery(name),
        if(sport != null)
          SportQuery([sport]),
        if(after != null || before != null)
          DateQuery(after: after, before: before),
      ],
      limit: pageSize,
      offset: page * pageSize,
    );

    return finalQuery.findAll();
  }

  Future<List<DbShootingMatch>> getMatchesByExactNames(List<String> names) async {
    if(names.isEmpty) return [];
    return await isar.dbShootingMatchs
      .where()
      .filter()
      .anyOf(names, (query, name) => query.eventNameEqualTo(name))
      .findAll();
  }

  double _calculateSimilarity(String queryLower, String eventNameLower, {bool printDebugInfo = false}) {
    var similarity = queryLower.similarityTo(eventNameLower);
    var similarityMultiplier = 1.0;
    var similarityBoost = 0.0;
    final similarityFactorPerWord = 0.5;
    final similarityBoostPerExactWord = 1;

    // A backward similarity factor of 1 will result in equal weight to forward
    // similarity, by the following example:
    // - query: "handgun"
    // - event name: "hand gun national championships"
    // - backward similarity for "hand" will be 4/7 * 1
    // - forward similarity for "hand" will be 3/4 * 1
    // - total similarity is 1
    // The reduction is because this is a fuzzier match to catch places where
    // a match name has a space and the query doesn't. (At present the DB query
    // doesn't have a way to return shorter-than-query-part matches, so this is not
    // helping if we search for "nationals" and want to get "national" matches as well.)
    final backwardSimilarityImpactFactor = 0.3;
    var eventNameWordsLower = eventNameLower.split(" ");
    var queryWordsLower = queryLower.split(" ");

    int exactWordMatches = 0;
    int partialWordMatches = 0;

    int backwardPartialMatches = 0;

    // Forward similarity: words in the query are matched against words in
    // the event name; query "national" will match the word "nationals"
    for(var word in queryWordsLower) {
      for(var eventNameWord in eventNameWordsLower) {
        if(eventNameWord.startsWith(word)) {
          if(eventNameWord.length == word.length) {
            exactWordMatches += 1;
            similarityBoost += similarityBoostPerExactWord;
          }
          else {
            partialWordMatches += 1;
          }
          var similarityFactor = 1 + (word.length / eventNameWord.length) * similarityFactorPerWord;
          similarityMultiplier *= similarityFactor;
          // Each query word can only match an event word once.
          break;
        }
      }
    }

    // Backward similarity: words in the event name are matched against words in the query,
    // So that a query for "handgun" will match "hand gun" in the event name. Impact reduced.
    for(var eventNameWord in eventNameWordsLower) {
      for(var queryWord in queryWordsLower) {
        if(queryWord != eventNameWord && queryWord.contains(eventNameWord)) {
          backwardPartialMatches += 1;
          similarityMultiplier *= (1 + (eventNameWord.length / queryWord.length) * similarityFactorPerWord * backwardSimilarityImpactFactor);
        }
      }
    }

    if(printDebugInfo) {
      var debugString = "Similarity between $queryLower and $eventNameLower: ${(similarity + similarityBoost) * similarityMultiplier}";
      debugString += "\nExact word matches: $exactWordMatches";
      debugString += "\nPartial word matches: $partialWordMatches";
      debugString += "\nBackward partial matches: $backwardPartialMatches";
      debugString += "\nBase similarity: $similarity";
      debugString += "\nSimilarity boost: $similarityBoost";
      debugString += "\nSimilarity multiplier: $similarityMultiplier";

      _log.v(debugString);
    }
    return (similarity + similarityBoost) * similarityMultiplier;
  }

  /// A text search match query, using partial searches and string similarity
  /// to return the best-matching names.
  ///
  /// Query will be split into search terms of 3+ characters on spaces.
  Future<List<DbShootingMatch>> matchNameTextSearch(String query, {
    int limit = 10,
    DateTime? after,
    DateTime? before,
  }) async {
    var queryLower = query.toLowerCase();
    var words = Isar.splitWords(queryLower);
    final numRegex = RegExp(r'^\d{1,2}$');
    var terms = words.where((t) =>
      t.length >= 3 ||
      // Also match 1- or 2-digit numbers, for e.g. "area 5"
      numRegex.hasMatch(t)
    ).toList();
    if(terms.isEmpty) return [];

    // TODO: possibly more advanced stemming
    // OTOH, this catches most of the cases I can think of in the USPSA and ICORE set.
    if(terms.contains("nationals")) terms.add("national");
    if(terms.contains("championships")) terms.add("championship");
    if(terms.contains("sectionals")) terms.add("section");
    if(terms.contains("sectional")) terms.add("section");
    if(terms.contains("regionals")) terms.add("region");
    if(terms.contains("regional")) terms.add("region");

    // We have to load a lot of matches and we only actually need the names to search on,
    // so get the names only and load exactly the number of requested hits at the end.
    Query<String> dbQuery = _buildMatchNameQuery([
      TextSearchQuery(terms),
      if(after != null || before != null)
        DateQuery(after: after, before: before),
    ]);

    var matchNames = await dbQuery.findAll();

    Map<String, double> matchNameSimilarities = {};
    for(var matchName in matchNames) {
      matchNameSimilarities[matchName] = _calculateSimilarity(queryLower, matchName.toLowerCase());
    }

    // Sort by dice similarity to the original query
    matchNames.sort((a, b) {
      var aSimilarity = matchNameSimilarities[a] ?? 0;
      var bSimilarity = matchNameSimilarities[b] ?? 0;
      return bSimilarity.compareTo(aSimilarity);
    });

    var topMatchNames = matchNames.take(limit).toList();

    // _log.v("DUMPING SIMILARITY CALCULATIONS FOR TOP MATCH NAMES ===");
    // for(var matchName in topMatchNames.sublist(0, min(10, topMatchNames.length))) {
    //   _calculateSimilarity(queryLower, matchName.toLowerCase(), printDebugInfo: true);
    // }

    // Load the found matches by exact names.
    // In the unlikely event that two matches have the same name, that's fine;
    // a text search on that name should return both.
    // We have to resort here because we don't preserve order in the matches-by-names query.
    var matches = await getMatchesByExactNames(topMatchNames);
    matches.sort((a, b) {
      var aSimilarity = matchNameSimilarities[a.eventName] ?? 0;
      var bSimilarity = matchNameSimilarities[b.eventName] ?? 0;
      return bSimilarity.compareTo(aSimilarity);
    });
    return matches;
  }

  /// Return all matches in the database.
  Future<List<DbShootingMatch>> getAllMatches() async {
    return await isar.dbShootingMatchs.where().findAll();
  }

  /// Return Isar match IDs matching the query.
  Future<List<int>> queryMatchIds({
    String? name,
    DateTime? after,
    DateTime? before,
    int page = 0,
    int pageSize = 100,
    MatchSortField sort = const DateSort(),
    List<Sport>? sports,
  }) {
    Query<int> finalQuery = _buildMatchIdQuery(
      [
        if(name != null)
          NamePartsQuery(name),
        if(sports != null)
          SportQuery(sports),
        if(after != null || before != null)
          DateQuery(after: after, before: before),
      ],
      limit: pageSize,
      offset: page * pageSize,
    );

    return finalQuery.findAll();
  }

  /// Get the last time the match was updated, according to the source it was retrieved from.
  Future<DateTime?> getMatchLastUpdated(String sourceId) async {
    return await isar.dbShootingMatchs.where().sourceIdsElementEqualTo(sourceId).sourceLastUpdatedProperty().findFirst();
  }

  /// Get the last time the match was updated, according to the source it was retrieved from.
  DateTime? getMatchLastUpdatedSync(String sourceId) {
    return isar.dbShootingMatchs.where().sourceIdsElementEqualTo(sourceId).sourceLastUpdatedProperty().findFirstSync();
  }

  Future<List<DbShootingMatch>> queryMatchesByCompetitorMemberNumbers(List<String> memberNumbers, {int page = 0, int pageSize = 10}) async {
    if(memberNumbers.isEmpty) return [];

    List<WhereClause> whereClauses = [];
    for(var memberNumber in memberNumbers) {
      whereClauses.add(IndexWhereClause.equalTo(
        indexName: AnalystDatabase.memberNumbersAppearingIndex,
        value: [memberNumber],
      ));
    }

    Query<DbShootingMatch> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereClauses,
      sortBy: [
        SortProperty(property: DateQuery().property, sort: Sort.desc),
      ],
      limit: pageSize,
      offset: page * pageSize,
    );

    return await query.findAll();
  }

  Future<List<String>> queryMatchNamesByCompetitorMemberNumbers(List<String> memberNumbers, {int page = 0, int pageSize = 10}) async {
    if(memberNumbers.isEmpty) return [];

    List<WhereClause> whereClauses = [];
    for(var memberNumber in memberNumbers) {
      whereClauses.add(IndexWhereClause.equalTo(
        indexName: AnalystDatabase.memberNumbersAppearingIndex,
        value: [memberNumber],
      ));
    }

    Query<String> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereClauses,
      sortBy: [
        SortProperty(property: DateQuery().property, sort: Sort.desc),
      ],
      limit: pageSize,
      offset: page * pageSize,
      property: "eventName",
    );

    return await query.findAll();
  }

  /// Save a match.
  ///
  /// The provided ShootingMatch will have its database ID set if the save succeeds.
  Future<Result<DbShootingMatch, ResultErr>> saveMatch(
    ShootingMatch match, {
      bool updateOnly = false,
      bool insertOnly = false,
    }
  ) async {
    if(match.sourceIds.isEmpty || match.sourceCode.isEmpty) {
      throw ArgumentError("Match must have at least one source ID and a source code to be saved in the database");
    }
    var dbMatch = DbShootingMatch.from(match);
    try {
      var oldMatch = await getMatchByAnySourceId(dbMatch.sourceIds);
      if(oldMatch != null && insertOnly) {
        return Result.err(StringError("Match already exists and insertOnly is true"));
      }
      if(oldMatch == null && updateOnly) {
        return Result.err(StringError("Match does not exist and updateOnly is true"));
      }
      dbMatch = await isar.writeTxn<DbShootingMatch>(() async {
        if (oldMatch != null) {
          dbMatch.id = oldMatch.id;
          await isar.dbShootingMatchs.put(dbMatch);
        }
        else {
          dbMatch.id = await isar.dbShootingMatchs.put(dbMatch);
        }
        return dbMatch;
      });

      if(dbMatch.shootersStoredSeparately) {
        // Get the current shooters from the links object, which are the ones we added during
        // conversion from ShootingMatch to DbShootingMatch. We have to do this before the
        // write transaction because toList() triggers a load of the links, which illegally
        // nests a transaction.
        var currentShooters = dbMatch.shooterLinks.toList();
        await isar.writeTxn(() async {
          if(oldMatch != null) {
            var deletedEntries = await deleteStandaloneMatchEntriesForMatchSourceIds(oldMatch.sourceIds);
            _log.d("Deleted $deletedEntries standalone match entries while updating match ${oldMatch.eventName}");
          }
          await isar.standaloneDbMatchEntrys.putAll(currentShooters);
          await dbMatch.shooterLinks.save();
        });
      }
    }
    catch(e, stackTrace) {
      _log.e("Failed to save match", error: e, stackTrace: stackTrace);
      _log.i("Failed source IDs: ${dbMatch.sourceIds}");
      return Result.err(StringError("$e"));
    }

    // For least confusion
    match.databaseId = dbMatch.id;
    return Result.ok(dbMatch);
  }

  /// Save a match synchronously.
  ///
  /// The provided ShootingMatch will have its database ID set if the save succeeds.
  Result<DbShootingMatch, ResultErr> saveMatchSync(ShootingMatch match) {
    if(match.sourceIds.isEmpty || match.sourceCode.isEmpty) {
      throw ArgumentError("Match must have at least one source ID and a source code to be saved in the database");
    }
    var dbMatch = DbShootingMatch.from(match);
    try {
      var oldMatch = getMatchByAnySourceIdSync(dbMatch.sourceIds);
      dbMatch = isar.writeTxnSync(() {
        if (oldMatch != null) {
          dbMatch.id = oldMatch.id;
          isar.dbShootingMatchs.putSync(dbMatch);
        }
        else {
          dbMatch.id = isar.dbShootingMatchs.putSync(dbMatch);
        }
        return dbMatch;
      });

      // We don't need to save the shooters separately in sync code, because putSync
      // also handles links, unlike the async version.
    }
    catch(e, stackTrace) {
      _log.e("Failed to save match", error: e, stackTrace: stackTrace);
      _log.i("Failed source IDs: ${dbMatch.sourceIds}");
      return Result.err(StringError("$e"));
    }

    // For least confusion
    match.databaseId = dbMatch.id;
    return Result.ok(dbMatch);
  }

  Future<DbShootingMatch?> getMatchByAnySourceId(List<String> ids) async {
    for(var id in ids) {
      var match = await isar.dbShootingMatchs.getByIndex(AnalystDatabase.sourceIdsIndex, [id]);
      if(match != null) return match;
    }

    return null;
  }

  Future<List<DbShootingMatch>> getMatchesByAnySourceIds(Iterable<String> ids) async {
    return await isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.sourceIdsElementEqualTo(id)).findAll();
  }

  DbShootingMatch? getMatchByAnySourceIdSync(List<String> ids) {
    return isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.sourceIdsElementEqualTo(id)).findFirstSync();
  }

  Future<DbShootingMatch?> getMatchBySourceId(String id) {
    return getMatchByAnySourceId([id]);
  }

  /// Check if a match exists by source ID.
  ///
  /// Faster than [getMatchBySourceId] because it doesn't need to load the match.
  Future<bool> hasMatchBySourceId(String id) async {
    return hasMatchByAnySourceId([id]);
  }

  /// Check if a match exists by any of the given source IDs.
  ///
  /// Faster than [getMatchByAnySourceId] because it doesn't need to load the match.
  Future<bool> hasMatchByAnySourceId(List<String> ids) async {
    return await isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.sourceIdsElementEqualTo(id)).count() > 0;
  }

  /// Check if a match exists by source ID.
  ///
  /// Faster than [getMatchBySourceIdSync] because it doesn't need to load the match.
  bool hasMatchBySourceIdSync(String id) {
    return hasMatchByAnySourceIdSync([id]);
  }

  /// Check if a match exists by any of the given source IDs.
  ///
  /// Faster than [getMatchByAnySourceIdSync] because it doesn't need to load the match.
  bool hasMatchByAnySourceIdSync(List<String> ids) {
    return isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.sourceIdsElementEqualTo(id)).countSync() > 0;
  }

  /// Get a match by database ID.
  Future<DbShootingMatch?> getMatch(int id) async {
    return await isar.dbShootingMatchs.get(id);
  }

  /// Get matches by database IDs.
  Future<List<DbShootingMatch>> getMatchesByIds(Iterable<Id> ids) async {
    return await isar.dbShootingMatchs.where().anyOf(ids, (query, id) => query.idEqualTo(id)).findAll();
  }

  Future<List<DbShootingMatch>> getMatchesByMemberNumbers(Iterable<String> memberNumbers) async {
    var matches = await isar.dbShootingMatchs
      .where()
      .anyOf(memberNumbers, (q, memberNumber) => q.memberNumbersAppearingElementEqualTo(memberNumber))
      .findAll();
    return matches;
  }

  Future<int> deleteStandaloneMatchEntriesForMatchSourceIds(List<String> matchSourceIds) async {
    return await isar.standaloneDbMatchEntrys.where().anyOf(matchSourceIds, (q, sourceId) => q.matchSourceIdsElementEqualTo(sourceId)).deleteAll();
  }

  Future<Result<bool, ResultErr>> deleteMatch(int id) async {
    return isar.writeTxn<Result<bool, ResultErr>>(() async {
      try {
        var match = await isar.dbShootingMatchs.get(id);
        if(match?.shootersStoredSeparately ?? false) {
          var deletedEntries = await deleteStandaloneMatchEntriesForMatchSourceIds(match!.sourceIds);
          _log.d("Deleted $deletedEntries standalone match entries while deleting match ${match.eventName}");
        }
        var result = await isar.dbShootingMatchs.delete(id);
        return Result.ok(result);
      }
      catch(e, stackTrace) {
        _log.e("Failed to delete match", error: e, stackTrace: stackTrace);
        return Result.err(StringError(e.toString()));
      }
    });
  }

  Future<Result<bool, ResultErr>> deleteMatchBySourceId(String id) async {
    var match = await getMatchBySourceId(id);
    if(match == null) {
      return Result.ok(false);
    }
    return deleteMatch(match.id);
  }

  // Future<void> migrateFromMatchCache(ProgressCallback callback) async {
  //   _log.d("Migrating from match cache");
  //   var cache = MatchCache();

  //   int i = 0;
  //   int matchCount = cache.allIndexEntries().length;
  //   for(var ie in cache.allIndexEntries()) {
  //     var oldMatch = await cache.getByIndex(ie);
  //     var newMatch = MatchTranslator.shootingMatchFrom(oldMatch);
  //     await saveMatch(newMatch);
  //     i += 1;
  //     if(i % 10 == 0) {
  //       _log.v("Migration: saved $i of $matchCount to database");
  //       await callback.call(i, matchCount);
  //     }
  //   }
  //   _log.i("Match cache migration complete with $matchCount cache entries processed");
  // }

  /// Build a match query. Returns either a [Query<DbShootingMatch>] or a [Query<int>], depending on the [idProperty] parameter.
  Query<DbShootingMatch> _buildMatchQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildMatchQueryElements(elements, sort: sort);

    Query<DbShootingMatch> query = isar.dbShootingMatchs.buildQuery(
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

  Query<String> _buildMatchNameQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildMatchQueryElements(elements, sort: sort);

    Query<String> query = isar.dbShootingMatchs.buildQuery(
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
      property: "eventName",
    );

    return query;
  }

  Query<DateTime> _buildMatchLastUpdatedQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildMatchQueryElements(elements, sort: sort);

    Query<DateTime> query = isar.dbShootingMatchs.buildQuery(
      whereClauses: whereElement?.whereClauses ?? [],
      filter: filterElements.isEmpty ? null : FilterGroup.and([
        for(var f in filterElements)
          if(f.filterCondition != null)
            f.filterCondition!,
      ]),
      sortBy: sortProperties,
      property: "sourceLastUpdated",
      whereSort: whereSort,
      limit: limit,
      offset: offset,
    );

    return query;
  }

  Query<int> _buildMatchIdQuery(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    var (whereElement, filterElements, sortProperties, whereSort) = _buildMatchQueryElements(elements, sort: sort);

    Query<int> query = isar.dbShootingMatchs.buildQuery(
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

  (MatchQueryElement?, Iterable<MatchQueryElement>, List<SortProperty>, Sort) _buildMatchQueryElements(List<MatchQueryElement> elements, {int? limit, int? offset, MatchSortField sort = const DateSort()}) {
    NamePartsQuery? nameQuery;
    TextSearchQuery? textSearchQuery;
    DateQuery? dateQuery;
    // ignore: unused_local_variable
    LevelNameQuery? levelNameQuery;
    SportQuery? sportQuery;

    for(var e in elements) {
      switch(e) {
        case TextSearchQuery():
          textSearchQuery = e;
        case NamePartsQuery():
          nameQuery = e;
        case DateQuery():
          dateQuery = e;
        case LevelNameQuery():
          levelNameQuery = e;
        case SportQuery():
          sportQuery = e;
      }
    }

    // Defaults. Prefer strongly to 'where' by our sort. Since we do limit/offset
    // for paging, unless an alternate 'where' is highly selective, leaning on the
    // index for sort is probably preferable.
    MatchQueryElement? whereElement;
    Iterable<MatchQueryElement> filterElements = elements;
    if(dateQuery == null && (sort is DateSort)) {
      dateQuery = DateQuery(before: null, after: null);
      whereElement = dateQuery;
    }
    else if(nameQuery == null && (sort is NameSort)) {
      nameQuery = NamePartsQuery("");
      whereElement = nameQuery;
    }
    (whereElement, filterElements) = buildQueryElementLists(elements, whereElement);

    if(textSearchQuery != null) {
      // If we have a text search query, always where on it.
      (whereElement, filterElements) = buildQueryElementLists(elements, textSearchQuery);
    }
    else if(nameQuery?.canWhere ?? false) {
      nameQuery!;

      // If we have a one-word name query of sufficient length, prefer to 'where'
      // on it, since high selectivity will probably outweigh the fast sort on
      // by the other index.
      if(nameQuery.name.length >= 3 || (sort is NameSort)) {
        (whereElement, filterElements) = buildQueryElementLists(elements, nameQuery);
      }
    }
    else if(sportQuery != null && whereElement == null) {
      // If we have a sport query and no other where element, we can where on it.
      // This is very unlikely to happen currently, since we're usually going to end up
      // with a name or date where for sorting, but just in case we add future sorts
      // that aren't where-backed...
      (whereElement, filterElements) = buildQueryElementLists(elements, sportQuery);
    }

    var (sortProperties, whereSort) = _buildMatchSortFields(whereElement, sort);
    return (whereElement, filterElements, sortProperties, whereSort);
  }

  (List<SortProperty>, Sort) _buildMatchSortFields(MatchQueryElement? whereElement, MatchSortField sort) {
    var direction = sort.desc ? Sort.desc : Sort.asc;
    switch(sort) {
      case NameSort():
        if(whereElement is NamePartsQuery) {
          return ([], direction);
        }
        else {
          return ([SortProperty(property: NamePartsQuery("").property, sort: direction)], direction);
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

/// The order of a query.
///
/// Not all elements apply to all queries.
enum Order {
  /// Ascending order, by the most relevant quality of the data.
  ascending,
  /// Descending order, by the most relevant quality of the data.
  descending,

  /// Descending order by rating change.
  ///
  /// Applies only to rating event queries.
  descendingChange,
}
