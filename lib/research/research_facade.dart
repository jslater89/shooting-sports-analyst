/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:isar_community/isar.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/match_prep.dart";
import "package:shooting_sports_analyst/data/database/extensions/prediction_game.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart";
import "package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart";
import "package:shooting_sports_analyst/data/ranking/model/rating_system.dart";
import "package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart";
import "package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rating.dart";
import "package:shooting_sports_analyst/data/sport/builtins/registry.dart";
import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/data/sport/scoring/scoring.dart";
import "package:shooting_sports_analyst/data/sport/shooter/filter_set.dart";
import "package:shooting_sports_analyst/data/sport/shooter/shooter.dart";
import "package:shooting_sports_analyst/data/sport/sport.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/research/dtos.dart";
import "package:shooting_sports_analyst/research/research_queries.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("ResearchFacade");

/// Read-only research queries over [AnalystDatabase].
///
/// Shared by the stdio MCP server (local fallback), the optional in-app
/// localhost MCP host, and the local research HTTP API.
class ResearchFacade implements ResearchQueries {
  ResearchFacade(this.db);

  final AnalystDatabase db;

  Future<ResearchResult<List<RatingProjectDto>>> listRatingProjects({String? name, int limit = 50}) async {
    final projects = name == null || name.trim().isEmpty
        ? await db.getAllRatingProjects()
        : await db.findRatingProjects(name: name, limit: limit);
    final out = <RatingProjectDto>[];
    for (final p in projects.take(limit)) {
      if (!p.dbGroups.isLoaded) {
        await p.dbGroups.load();
      }
      out.add(_projectDto(p));
    }
    return Result.ok(out);
  }

  Future<ResearchResult<LeaderboardResponse>> getLeaderboard({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? sort,
    int limit = 25,
    int minMatches = 0,
    DateTime? seenSince,
    DateTime? changeSince,
  }) async {
    if (limit < 1) {
      return Result.err(ResearchError("limit must be >= 1"));
    }
    if (minMatches < 0) {
      return Result.err(ResearchError("minMatches must be >= 0"));
    }

    final projectRes = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (projectRes.isErr()) {
      return Result.errFrom(projectRes);
    }
    final project = projectRes.unwrap();
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }
    final groupRes = _requireSingleGroup(project, groupUuid: groupUuid, groupName: groupName);
    if (groupRes.isErr()) {
      return Result.errFrom(groupRes);
    }
    final group = groupRes.unwrap();
    final algo = project.settings.algorithm;
    final sortModeRes = _parseSortMode(sort, algo);
    if (sortModeRes.isErr()) {
      return Result.errFrom(sortModeRes);
    }
    final sortMode = sortModeRes.unwrap();
    final latestMatchDateRes = _latestMatchDate(project);
    if (latestMatchDateRes.isErr()) {
      return Result.errFrom(latestMatchDateRes);
    }
    final latestMatchDate = latestMatchDateRes.unwrap();
    final effectiveSeenSince = seenSince ?? DateTime(latestMatchDate.year - 1, 1, 1);

    final ratingsRes = await project.getRatings(group);
    if (ratingsRes.isErr()) {
      return Result.err(ResearchError(
        "Failed to load ratings for group ${group.name}: ${ratingsRes.unwrapErr()}",
        statusCode: 500,
      ));
    }

    final wrapped = <ShooterRating>[];
    for (final dbRating in ratingsRes.unwrap()) {
      if (dbRating.lastSeen.isBefore(effectiveSeenSince)) {
        continue;
      }
      final r = project.wrapDbRatingSync(dbRating);
      final matches = r.matchCount ?? r.length;
      if (matches < minMatches) {
        continue;
      }
      wrapped.add(r);
    }

    final comparator = algo.comparatorFor(sortMode, changeSince: changeSince)
        ?? sortMode.comparator(changeSince: changeSince);
    wrapped.sort(comparator);

    final entries = <LeaderboardEntryDto>[];
    final take = wrapped.take(limit).toList();
    for (var i = 0; i < take.length; i++) {
      entries.add(_leaderboardEntry(
        place: i + 1,
        project: project,
        rating: take[i],
        sortMode: sortMode,
        changeSince: changeSince,
      ));
    }

    return Result.ok(LeaderboardResponse(
      projectName: project.name,
      groupUuid: group.uuid,
      groupName: group.name,
      sort: sortMode.name,
      sortLabel: algo.nameForSort(sortMode),
      minMatches: minMatches,
      seenSince: effectiveSeenSince,
      latestMatchDate: latestMatchDate,
      totalAfterFilters: wrapped.length,
      entries: entries,
    ));
  }

  Future<ResearchResult<List<MatchSummaryDto>>> searchMatches({
    required String query,
    int limit = 10,
    DateTime? after,
    DateTime? before,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return Result.err(ResearchError("query is required"));
    }
    final matches = await db.matchNameTextSearch(
      q,
      limit: limit,
      after: after,
      before: before,
    );
    return Result.ok(matches.map(_matchSummary).toList());
  }

  Future<ResearchResult<MatchWinnersResponse>> getMatchWinners({
    int? matchId,
    String? matchQuery,
    String? projectName,
    bool byRatingGroup = false,
    int topN = 1,
  }) async {
    if (topN < 1) {
      return Result.err(ResearchError("topN must be >= 1"));
    }
    final dbMatchRes = await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    if (dbMatchRes.isErr()) {
      return Result.errFrom(dbMatchRes);
    }
    final dbMatch = dbMatchRes.unwrap();
    final shootingMatchRes = await _hydrate(dbMatch);
    if (shootingMatchRes.isErr()) {
      return Result.errFrom(shootingMatchRes);
    }
    final shootingMatch = shootingMatchRes.unwrap();

    final winners = <MatchWinnerDto>[];
    if (byRatingGroup) {
      final projectRes = await _requireProject(projectName ?? kDefaultResearchProjectName);
      if (projectRes.isErr()) {
        return Result.errFrom(projectRes);
      }
      final project = projectRes.unwrap();
      if (!project.dbGroups.isLoaded) {
        await project.dbGroups.load();
      }
      final groups = [...project.groups]..sort((a, b) {
          final o = a.sortOrder.compareTo(b.sortOrder);
          if (o != 0) return o;
          return a.name.compareTo(b.name);
        });
      for (final group in groups) {
        winners.addAll(_topFromScores(
          shootingMatch.getScoresFromFilters(group.filters),
          label: group.name,
          kind: "ratingGroup",
          topN: topN,
        ));
      }
    }
    else {
      final sport = shootingMatch.sport;
      final divisions = sport.divisions.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final division in divisions) {
        winners.addAll(_topFromScores(
          shootingMatch.getScoresFromFilters(FilterSet.forDivision(sport, division)),
          label: division.displayName,
          kind: "division",
          topN: topN,
        ));
      }
    }

    return Result.ok(MatchWinnersResponse(
      match: _matchSummary(dbMatch),
      winners: winners,
    ));
  }

  /// Fuller standings for one scoring pool (division, rating group, or overall).
  ///
  /// Optional [femaleOnly], [ageCategory], and [category] narrow the competitor
  /// pool before scoring (same semantics as UI [FilterSet]).
  Future<ResearchResult<MatchResultsResponse>> getMatchResults({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    int topN = kDefaultMatchPoolTopN,
    bool overall = false,
  }) async {
    final resolvedRes = await _resolveMatchPool(
      matchId: matchId,
      matchQuery: matchQuery,
      projectName: projectName,
      division: division,
      groupUuid: groupUuid,
      groupName: groupName,
      femaleOnly: femaleOnly,
      ageCategory: ageCategory,
      category: category,
      overall: overall,
    );
    if (resolvedRes.isErr()) {
      return Result.errFrom(resolvedRes);
    }
    final resolved = resolvedRes.unwrap();
    final scored = resolved.scores.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));
    final limit = topN > 0 ? topN : scored.length;
    final results = <MatchCompetitorResultDto>[];
    for (final e in scored.take(limit)) {
      results.add(_competitorResult(e.key, e.value));
    }

    return Result.ok(MatchResultsResponse(
      match: _matchSummary(resolved.dbMatch),
      pool: resolved.pool,
      kind: resolved.kind,
      femaleOnly: femaleOnly,
      ageCategory: resolved.ageCategoryFilter,
      category: resolved.categoryFilter,
      competitorCount: scored.length,
      results: results,
    ));
  }

  /// Detailed match scores for one scoring pool, with optional stages and event counts.
  Future<ResearchResult<MatchScoresResponse>> getMatchScores({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    int topN = kDefaultMatchPoolTopN,
    bool overall = false,
    bool includeStages = false,
    bool includeScoringEventCounts = false,
  }) async {
    final resolvedRes = await _resolveMatchPool(
      matchId: matchId,
      matchQuery: matchQuery,
      projectName: projectName,
      division: division,
      groupUuid: groupUuid,
      groupName: groupName,
      femaleOnly: femaleOnly,
      ageCategory: ageCategory,
      category: category,
      overall: overall,
    );
    if (resolvedRes.isErr()) {
      return Result.errFrom(resolvedRes);
    }
    final resolved = resolvedRes.unwrap();
    final scoringKind = _scoringKind(resolved.shootingMatch.sport);
    final scored = resolved.scores.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));
    final limit = topN > 0 ? topN : scored.length;
    final rows = <MatchScoreRowDto>[];
    for (final e in scored.take(limit)) {
      rows.add(_matchScoreRow(
        e.key,
        e.value,
        scoringKind: scoringKind,
        includeStages: includeStages,
        includeScoringEventCounts: includeScoringEventCounts,
      ));
    }

    return Result.ok(MatchScoresResponse(
      match: _matchSummary(resolved.dbMatch),
      pool: resolved.pool,
      kind: resolved.kind,
      scoringKind: scoringKind,
      femaleOnly: femaleOnly,
      ageCategory: resolved.ageCategoryFilter,
      category: resolved.categoryFilter,
      competitorCount: scored.length,
      includeStages: includeStages,
      includeScoringEventCounts: includeScoringEventCounts,
      scores: rows,
    ));
  }

  /// One competitor's stage scores at a match.
  ///
  /// If no pool is specified, defaults to the competitor's entered division.
  Future<ResearchResult<CompetitorStageScoresResponse>> getCompetitorStageScores({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? memberNumber,
    int? ratingId,
    String? division,
    String? groupUuid,
    String? groupName,
    bool overall = false,
    bool includeScoringEventCounts = false,
  }) async {
    final dbMatchRes = await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    if (dbMatchRes.isErr()) {
      return Result.errFrom(dbMatchRes);
    }
    final dbMatch = dbMatchRes.unwrap();
    final shootingMatchRes = await _hydrate(dbMatch);
    if (shootingMatchRes.isErr()) {
      return Result.errFrom(shootingMatchRes);
    }
    final shootingMatch = shootingMatchRes.unwrap();
    final sport = shootingMatch.sport;

    final entryRes = await _resolveMatchEntry(
      shootingMatch,
      memberNumber: memberNumber,
      ratingId: ratingId,
      projectName: projectName,
    );
    if (entryRes.isErr()) {
      return Result.errFrom(entryRes);
    }
    final entry = entryRes.unwrap();

    final hasExplicitPool = overall ||
        (division != null && division.trim().isNotEmpty) ||
        (groupUuid != null && groupUuid.isNotEmpty) ||
        (groupName != null && groupName.isNotEmpty);

    late final ResearchResult<_ResolvedMatchPool> resolvedRes;
    if (hasExplicitPool) {
      resolvedRes = await _resolveMatchPool(
        matchId: dbMatch.id,
        projectName: projectName,
        division: division,
        groupUuid: groupUuid,
        groupName: groupName,
        overall: overall,
        preloadedDbMatch: dbMatch,
        preloadedShootingMatch: shootingMatch,
      );
    }
    else {
      final entered = entry.division;
      if (entered == null) {
        return Result.err(ResearchError(
          "Competitor has no entered division; specify division, group/groupUuid, or overall=true",
        ));
      }
      resolvedRes = await _resolveMatchPool(
        matchId: dbMatch.id,
        projectName: projectName,
        division: entered.name,
        preloadedDbMatch: dbMatch,
        preloadedShootingMatch: shootingMatch,
      );
    }
    if (resolvedRes.isErr()) {
      return Result.errFrom(resolvedRes);
    }
    final resolved = resolvedRes.unwrap();

    final score = resolved.scores[entry];
    if (score == null) {
      return Result.err(ResearchError(
        "Competitor ${entry.memberNumber} is not in scoring pool '${resolved.pool}'",
        statusCode: 404,
      ));
    }

    final scoringKind = _scoringKind(sport);
    final competitorRow = _matchScoreRow(
      entry,
      score,
      scoringKind: scoringKind,
      includeStages: false,
      includeScoringEventCounts: includeScoringEventCounts,
    );
    final stages = _stageScoreDtos(
      score,
      scoringKind: scoringKind,
      includeScoringEventCounts: includeScoringEventCounts,
    );

    return Result.ok(CompetitorStageScoresResponse(
      match: _matchSummary(dbMatch),
      pool: resolved.pool,
      kind: resolved.kind,
      scoringKind: scoringKind,
      competitor: competitorRow,
      stages: stages,
      includeScoringEventCounts: includeScoringEventCounts,
    ));
  }

  Future<ResearchResult<List<ShooterHitDto>>> searchShooters({
    required String query,
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int limit = 20,
    bool includeInternal = false,
  }) async {
    final projectRes = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (projectRes.isErr()) {
      return Result.errFrom(projectRes);
    }
    final project = projectRes.unwrap();
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }
    final groupsRes = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
    if (groupsRes.isErr()) {
      return Result.errFrom(groupsRes);
    }
    final groups = groupsRes.unwrap();
    final hits = <ShooterHitDto>[];

    final mn = memberNumber?.trim();
    if (mn != null && mn.isNotEmpty) {
      for (final group in groups) {
        final rating = await db.maybeKnownShooter(
          project: project,
          group: group,
          memberNumber: mn,
          usePossibleMemberNumbers: true,
        );
        if (rating != null) {
          hits.add(_shooterHit(project, rating, group, includeInternal: includeInternal));
        }
      }
      return Result.ok(hits.take(limit).toList());
    }

    final q = query.trim();
    if (q.length < 2) {
      return Result.err(ResearchError("query must be at least 2 characters (or pass memberNumber)"));
    }
    for (final group in groups) {
      final found = await db.findShooterRatings(
        project: project,
        group: group,
        name: q,
        limit: limit,
      );
      for (final rating in found) {
        hits.add(_shooterHit(project, rating, group, includeInternal: includeInternal));
      }
    }
    return Result.ok(hits.take(limit).toList());
  }

  Future<ResearchResult<ShooterSummaryDto>> getShooterSummary({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    bool includeInternal = false,
  }) async {
    final resolvedRes = await _resolveShooterRating(
      projectName: projectName,
      groupUuid: groupUuid,
      groupName: groupName,
      memberNumber: memberNumber,
      ratingId: ratingId,
    );
    if (resolvedRes.isErr()) {
      return Result.errFrom(resolvedRes);
    }
    final resolved = resolvedRes.unwrap();
    final rating = resolved.rating;
    final group = resolved.group;
    final project = resolved.project;
    final wrapped = project.wrapDbRatingSync(rating);
    final algo = project.settings.algorithm;

    return Result.ok(ShooterSummaryDto(
      ratingId: rating.id,
      firstName: rating.firstName,
      lastName: rating.lastName,
      name: "${rating.firstName} ${rating.lastName}".trim(),
      memberNumber: rating.memberNumber,
      knownMemberNumbers: [...rating.knownMemberNumbers],
      deduplicatorName: rating.deduplicatorName,
      projectName: project.name,
      groupUuid: group.uuid,
      groupName: group.name,
      rating: wrapped.scaledRating,
      agedRating: algo.scaleRating(wrapped.agedRating),
      careerMinimumRating: algo.scaleRating(wrapped.careerMinimumRating),
      careerMaximumRating: algo.scaleRating(wrapped.careerMaximumRating),
      eventCount: rating.length,
      firstSeen: rating.firstSeen,
      lastSeen: rating.lastSeen,
      classification: rating.lastClassificationName,
      division: rating.divisionName,
      female: rating.female,
      ageCategory: rating.ageCategoryName,
      categories: [...rating.categoryNames],
      region: rating.region,
      regionSubdivision: rating.regionSubdivision,
      rawLocation: rating.rawLocation,
      connectivity: rating.connectivity,
      internalRating: includeInternal ? wrapped.rating : null,
      internalAgedRating: includeInternal ? wrapped.agedRating : null,
      internalCareerMinimumRating: includeInternal ? wrapped.careerMinimumRating : null,
      internalCareerMaximumRating: includeInternal ? wrapped.careerMaximumRating : null,
    ));
  }

  Future<ResearchResult<List<RatingEventDto>>> getRatingHistory({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool matchLevelOnly = true,
    bool includeInternal = false,
  }) async {
    final resolvedRes = await _resolveShooterRating(
      projectName: projectName,
      groupUuid: groupUuid,
      groupName: groupName,
      memberNumber: memberNumber,
      ratingId: ratingId,
    );
    if (resolvedRes.isErr()) {
      return Result.errFrom(resolvedRes);
    }
    final resolved = resolvedRes.unwrap();
    final algo = resolved.project.settings.algorithm;
    final events = await db.getRatingEventsFor(resolved.rating, limit: limit * 4);
    final out = <RatingEventDto>[];
    for (final e in events) {
      if (matchLevelOnly && e.stageNumber >= 0) {
        continue;
      }
      var matchName = e.matchId;
      final m = await e.getMatch(save: false);
      if (m != null) {
        matchName = m.eventName;
      }
      final entryInfo = await _entryDivisionAndClassification(m, e.entryId);
      final displayOld = algo.scaleRating(e.oldRating);
      final displayNew = algo.scaleRating(e.newRating);
      out.add(RatingEventDto(
        date: e.date,
        matchId: e.matchId,
        matchName: matchName,
        stageNumber: e.stageNumber,
        oldRating: displayOld,
        newRating: displayNew,
        ratingChange: displayNew - displayOld,
        matchPlace: e.matchScore.place,
        matchRatio: e.matchScore.ratio,
        matchPercentage: e.matchScore.percentage,
        division: entryInfo.division,
        classification: entryInfo.classification,
        internalOldRating: includeInternal ? e.oldRating : null,
        internalNewRating: includeInternal ? e.newRating : null,
        internalRatingChange: includeInternal ? e.ratingChange : null,
      ));
      if (out.length >= limit) {
        break;
      }
    }
    return Result.ok(out);
  }

  Future<ResearchResult<List<ShooterMatchResultDto>>> getShooterMatchResults({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool includeInternal = false,
    bool bestFirst = false,
  }) async {
    final resolvedRes = await _resolveShooterRating(
      projectName: projectName,
      groupUuid: groupUuid,
      groupName: groupName,
      memberNumber: memberNumber,
      ratingId: ratingId,
    );
    if (resolvedRes.isErr()) {
      return Result.errFrom(resolvedRes);
    }
    final resolved = resolvedRes.unwrap();
    final algo = resolved.project.settings.algorithm;
    // Recency mode can stop after [limit] matches. Highlights need the full
    // match-level history so "best" is career-best, not recent-best.
    final eventLimit = bestFirst ? 0 : limit * 8;
    final events = await db.getRatingEventsFor(resolved.rating, limit: eventLimit);
    final byMatch = <String, ShooterMatchResultDto>{};
    for (final e in events) {
      if (e.stageNumber >= 0) {
        continue;
      }
      if (byMatch.containsKey(e.matchId)) {
        continue;
      }
      var matchName = e.matchId;
      final m = await e.getMatch(save: false);
      if (m != null) {
        matchName = m.eventName;
      }
      final entryInfo = await _entryDivisionAndClassification(m, e.entryId);
      final displayOld = algo.scaleRating(e.oldRating);
      final displayNew = algo.scaleRating(e.newRating);
      byMatch[e.matchId] = ShooterMatchResultDto(
        matchId: e.matchId,
        matchName: matchName,
        date: e.date,
        place: e.matchScore.place,
        ratio: e.matchScore.ratio,
        percentage: e.matchScore.percentage,
        division: entryInfo.division,
        classification: entryInfo.classification,
        ratingChange: displayNew - displayOld,
        oldRating: displayOld,
        newRating: displayNew,
        internalRatingChange: includeInternal ? e.ratingChange : null,
        internalOldRating: includeInternal ? e.oldRating : null,
        internalNewRating: includeInternal ? e.newRating : null,
      );
      if (!bestFirst && byMatch.length >= limit) {
        break;
      }
    }
    var out = byMatch.values.toList();
    if (bestFirst) {
      out.sort((a, b) {
        final byPct = b.percentage.compareTo(a.percentage);
        if (byPct != 0) {
          return byPct;
        }
        final byPlace = a.place.compareTo(b.place);
        if (byPlace != 0) {
          return byPlace;
        }
        return b.date.compareTo(a.date);
      });
      if (out.length > limit) {
        out = out.take(limit).toList();
      }
    }
    return Result.ok(out);
  }

  Future<ResearchResult<List<MatchPrepHitDto>>> searchMatchPreps({
    String? projectName,
    String? query,
    DateTime? after,
    DateTime? before,
    int limit = 10,
    bool hasPredictionsOnly = true,
  }) async {
    if (limit < 1) {
      return Result.err(ResearchError("limit must be >= 1"));
    }
    final projectRes = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (projectRes.isErr()) {
      return Result.errFrom(projectRes);
    }
    final project = projectRes.unwrap();
    final nameFilter = query?.trim();
    final preps = await db.queryMatchPreps(
      project: project,
      nameFilter: (nameFilter == null || nameFilter.isEmpty) ? null : nameFilter,
      after: after,
      before: before,
      limit: limit,
      hasPredictionsOnly: hasPredictionsOnly,
    );
    final out = <MatchPrepHitDto>[];
    for (final prep in preps) {
      out.add(await _matchPrepHit(prep, projectName: project.name));
    }
    return Result.ok(out);
  }

  Future<ResearchResult<List<PredictionSetDto>>> listPredictionSets({
    required String prepId,
  }) async {
    final idRes = _parseResearchId(prepId, "prepId");
    if (idRes.isErr()) {
      return Result.errFrom(idRes);
    }
    final prep = await db.getMatchPrepById(idRes.unwrap());
    if (prep == null) {
      return Result.err(ResearchError("Match prep not found: id=$prepId", statusCode: 404));
    }
    final sets = await db.getPredictionSetsForMatchPrep(prep);
    final out = <PredictionSetDto>[];
    for (final set in sets) {
      out.add(await _predictionSetDto(set));
    }
    return Result.ok(out);
  }

  Future<ResearchResult<PredictionsResponse>> getPredictions({
    String? predictionSetId,
    String? prepId,
    String? groupUuid,
    String? groupName,
    int topN = kDefaultPredictionTopN,
  }) async {
    final setRes = await _resolvePredictionSet(
      predictionSetId: predictionSetId,
      prepId: prepId,
    );
    if (setRes.isErr()) {
      return Result.errFrom(setRes);
    }
    final set = setRes.unwrap();
    final projectRes = await _projectForPredictionSet(set);
    if (projectRes.isErr()) {
      return Result.errFrom(projectRes);
    }
    final project = projectRes.unwrap();
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }
    final groupRes = _requireSingleGroup(project, groupUuid: groupUuid, groupName: groupName);
    if (groupRes.isErr()) {
      return Result.errFrom(groupRes);
    }
    final group = groupRes.unwrap();

    final rows = await _loadPredictionRows(set, scoringGroup: group);
    rows.sort((a, b) => a.medianPlace.compareTo(b.medianPlace));
    final limit = topN > 0 ? topN : rows.length;
    return Result.ok(PredictionsResponse(
      predictionSet: await _predictionSetDto(set),
      scoringGroup: group.name,
      scoringGroupUuid: group.uuid,
      competitorCount: rows.length,
      predictions: rows.take(limit).toList(),
    ));
  }

  Future<ResearchResult<List<PredictionRowDto>>> searchPredictions({
    String? predictionSetId,
    String? prepId,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    String? query,
    List<String>? memberNumbers,
    List<int>? ratingIds,
    int limit = kDefaultPredictionSearchLimit,
  }) async {
    final memberSet = <String>{
      if (memberNumber != null && memberNumber.trim().isNotEmpty) memberNumber.trim(),
      ...?memberNumbers?.map((m) => m.trim()).where((m) => m.isNotEmpty),
    };
    final ratingIdSet = <int>{
      if (ratingId != null) ratingId,
      ...?ratingIds,
    };
    final nameQuery = query?.trim() ?? "";
    final hasBatch = memberSet.isNotEmpty || ratingIdSet.isNotEmpty;
    final hasName = nameQuery.length >= 2;
    if (!hasBatch && !hasName) {
      return Result.err(ResearchError(
        "Provide memberNumber(s), ratingId(s), and/or a name query of at least 2 characters",
      ));
    }
    if (nameQuery.isNotEmpty && nameQuery.length < 2) {
      return Result.err(ResearchError("query must be at least 2 characters"));
    }

    final setRes = await _resolvePredictionSet(
      predictionSetId: predictionSetId,
      prepId: prepId,
    );
    if (setRes.isErr()) {
      return Result.errFrom(setRes);
    }
    final set = setRes.unwrap();

    RatingGroup? groupFilter;
    if ((groupUuid != null && groupUuid.isNotEmpty) || (groupName != null && groupName.isNotEmpty)) {
      final projectRes = await _projectForPredictionSet(set);
      if (projectRes.isErr()) {
        return Result.errFrom(projectRes);
      }
      final project = projectRes.unwrap();
      if (!project.dbGroups.isLoaded) {
        await project.dbGroups.load();
      }
      final groupRes = _requireSingleGroup(project, groupUuid: groupUuid, groupName: groupName);
      if (groupRes.isErr()) {
        return Result.errFrom(groupRes);
      }
      groupFilter = groupRes.unwrap();
    }

    final loaded = await _loadPredictionsWithRatings(set, scoringGroup: groupFilter);
    final nameLower = nameQuery.toLowerCase();
    final matched = <PredictionRowDto>[];
    for (final entry in loaded) {
      final pred = entry.prediction;
      final rating = entry.rating;
      final row = entry.row;
      var hit = false;
      if (memberSet.isNotEmpty) {
        if (memberSet.contains(pred.memberNumber)) {
          hit = true;
        }
        else if (rating != null && rating.knownMemberNumbers.any(memberSet.contains)) {
          hit = true;
        }
      }
      if (!hit && ratingIdSet.isNotEmpty && rating != null && ratingIdSet.contains(rating.id)) {
        hit = true;
      }
      if (!hit && hasName) {
        final full = row.name.toLowerCase();
        if (full.contains(nameLower) ||
            row.firstName.toLowerCase().contains(nameLower) ||
            row.lastName.toLowerCase().contains(nameLower)) {
          hit = true;
        }
      }
      if (hit) {
        matched.add(row);
      }
    }

    matched.sort((a, b) => a.medianPlace.compareTo(b.medianPlace));
    final effectiveLimit = hasBatch
        ? kMaxPredictionSearchLimit
        : (limit < 1 ? kDefaultPredictionSearchLimit : limit.clamp(1, kMaxPredictionSearchLimit));
    return Result.ok(matched.take(effectiveLimit).toList());
  }

  MatchSummaryDto _matchSummary(DbShootingMatch m) => MatchSummaryDto(
        id: m.id,
        name: m.eventName,
        date: m.date,
        sportName: m.sportName,
        sourceIds: [...m.sourceIds],
      );

  Future<ResearchResult<DbShootingMatch>> _resolveMatch({int? matchId, String? matchQuery}) async {
    if (matchId != null) {
      final m = await db.getMatch(matchId);
      if (m == null) {
        return Result.err(ResearchError("Match not found: id=$matchId", statusCode: 404));
      }
      return Result.ok(m);
    }
    final q = matchQuery?.trim();
    if (q == null || q.isEmpty) {
      return Result.err(ResearchError("matchId or matchQuery is required"));
    }
    final hits = await db.matchNameTextSearch(q, limit: 5);
    if (hits.isEmpty) {
      return Result.err(ResearchError("No matches found for query: $q", statusCode: 404));
    }
    if (hits.length > 1) {
      final names = hits.map((h) => "${h.id}: ${h.eventName}").join("; ");
      _log.i("Ambiguous match query '$q'; using first of ${hits.length}: ${hits.first.eventName}");
      // Prefer exact-ish first hit; still return it but log ambiguity for agents.
      if (hits.first.eventName.toLowerCase() != q.toLowerCase()) {
        // Keep going with best similarity hit; include note via first result.
      }
      // If multiple strong hits, still pick the top text-search result (agents can re-query by id).
      _log.d("Candidates: $names");
    }
    return Result.ok(hits.first);
  }

  Future<ResearchResult<ShootingMatch>> _hydrate(DbShootingMatch dbMatch) async {
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }
    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      return Result.err(ResearchError(
        "Failed to hydrate match ${dbMatch.eventName}: ${hydrated.unwrapErr()}",
        statusCode: 500,
      ));
    }
    return Result.ok(hydrated.unwrap());
  }

  /// Resolve division/classification entered for a rating event via match entryId.
  Future<({String? division, String? classification})> _entryDivisionAndClassification(
    DbShootingMatch? match,
    int entryId,
  ) async {
    if (match == null) {
      return (division: null, classification: null);
    }

    DbMatchEntryBase? entry;
    if (match.shootersStoredSeparately) {
      if (!match.shooterLinks.isLoaded) {
        await match.shooterLinks.load();
      }
      entry = match.shooterLinks.firstWhereOrNull((e) => e.entryId == entryId);
    }
    else {
      entry = match.shooters.firstWhereOrNull((e) => e.entryId == entryId);
    }
    if (entry == null) {
      return (division: null, classification: null);
    }

    final sport = SportRegistry().lookup(match.sportName);
    final divisionName = entry.divisionName;
    final classificationName = entry.classificationName;
    final division = divisionName == null
        ? null
        : (sport?.divisions.lookupByName(divisionName)?.displayName ?? divisionName);
    final classification = classificationName == null
        ? null
        : (sport?.classifications.lookupByName(classificationName)?.displayName
            ?? classificationName);
    return (division: division, classification: classification);
  }

  List<MatchWinnerDto> _topFromScores(
    Map<MatchEntry, RelativeMatchScore> scores, {
    required String label,
    required String kind,
    required int topN,
  }) {
    if (scores.isEmpty) {
      return [];
    }
    final scored = scores.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));
    final out = <MatchWinnerDto>[];
    for (final e in scored.take(topN)) {
      final shooter = e.key;
      final score = e.value;
      out.add(MatchWinnerDto(
        divisionOrGroup: label,
        kind: kind,
        place: score.place,
        name: "${shooter.firstName} ${shooter.lastName}".trim(),
        memberNumber: shooter.memberNumber,
        classification: shooter.classification?.displayName ?? shooter.classification?.name,
        division: shooter.division?.displayName ?? shooter.division?.name,
        female: shooter.female,
        ageCategory: shooter.ageCategory?.displayName ?? shooter.ageCategory?.name,
        categories: shooter.categories.map((c) => c.displayName).toList(),
        ratio: score.ratio,
        percentage: score.percentage,
        points: score.points,
        competitorCount: scored.length,
        dq: shooter.dq,
      ));
    }
    return out;
  }

  MatchCompetitorResultDto _competitorResult(MatchEntry shooter, RelativeMatchScore score) {
    return MatchCompetitorResultDto(
      place: score.place,
      name: "${shooter.firstName} ${shooter.lastName}".trim(),
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      memberNumber: shooter.memberNumber,
      classification: shooter.classification?.displayName ?? shooter.classification?.name,
      division: shooter.division?.displayName ?? shooter.division?.name,
      powerFactor: shooter.powerFactor.displayName,
      female: shooter.female,
      ageCategory: shooter.ageCategory?.displayName ?? shooter.ageCategory?.name,
      categories: shooter.categories.map((c) => c.displayName).toList(),
      ratio: score.ratio,
      percentage: score.percentage,
      points: score.points,
      dq: shooter.dq,
      reentry: shooter.reentry,
      squad: shooter.squad,
    );
  }

  Future<ResearchResult<_ResolvedMatchPool>> _resolveMatchPool({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    bool overall = false,
    DbShootingMatch? preloadedDbMatch,
    ShootingMatch? preloadedShootingMatch,
  }) async {
    late final ResearchResult<DbShootingMatch> dbMatchRes;
    if (preloadedDbMatch != null) {
      dbMatchRes = Result.ok(preloadedDbMatch);
    }
    else {
      dbMatchRes = await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    }
    if (dbMatchRes.isErr()) {
      return Result.errFrom(dbMatchRes);
    }
    final dbMatch = dbMatchRes.unwrap();

    late final ResearchResult<ShootingMatch> shootingMatchRes;
    if (preloadedShootingMatch != null) {
      shootingMatchRes = Result.ok(preloadedShootingMatch);
    }
    else {
      shootingMatchRes = await _hydrate(dbMatch);
    }
    if (shootingMatchRes.isErr()) {
      return Result.errFrom(shootingMatchRes);
    }
    final shootingMatch = shootingMatchRes.unwrap();
    final sport = shootingMatch.sport;

    late final FilterSet filters;
    late final String pool;
    late final String kind;

    if (overall) {
      filters = FilterSet(sport);
      pool = "overall";
      kind = "overall";
    }
    else if (groupUuid != null || groupName != null) {
      final projectRes = await _requireProject(projectName ?? kDefaultResearchProjectName);
      if (projectRes.isErr()) {
        return Result.errFrom(projectRes);
      }
      final project = projectRes.unwrap();
      if (!project.dbGroups.isLoaded) {
        await project.dbGroups.load();
      }
      final groupsRes = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
      if (groupsRes.isErr()) {
        return Result.errFrom(groupsRes);
      }
      final groups = groupsRes.unwrap();
      if (groups.length != 1) {
        return Result.err(ResearchError(
          "Specify a single rating group (got ${groups.length}). Pass groupUuid or a unique group name.",
        ));
      }
      filters = groups.first.filters;
      pool = groups.first.name;
      kind = "ratingGroup";
    }
    else if (division != null && division.trim().isNotEmpty) {
      final divRes = _lookupDivision(sport, division.trim());
      if (divRes.isErr()) {
        return Result.errFrom(divRes);
      }
      final div = divRes.unwrap();
      filters = FilterSet.forDivision(sport, div);
      pool = div.displayName;
      kind = "division";
    }
    else {
      return Result.err(ResearchError(
        "Specify division, group/groupUuid, or overall=true",
      ));
    }

    filters.femaleOnly = femaleOnly;
    final ageFilter = ageCategory?.trim();
    final categoryFilter = category?.trim();
    if (ageFilter != null && ageFilter.isNotEmpty) {
      final age = sport.ageCategories.lookupByName(ageFilter);
      if (age == null) {
        return Result.err(ResearchError("Unknown age category: $ageFilter", statusCode: 404));
      }
      for (final key in filters.ageCategories.keys.toList()) {
        filters.ageCategories[key] = key == age;
      }
    }
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      final cat = sport.categories.lookupByName(categoryFilter);
      if (cat == null) {
        return Result.err(ResearchError("Unknown competitor category: $categoryFilter", statusCode: 404));
      }
      for (final key in filters.categories.keys.toList()) {
        filters.categories[key] = key == cat;
      }
    }

    final scores = shootingMatch.getScoresFromFilters(filters);
    return Result.ok(_ResolvedMatchPool(
      dbMatch: dbMatch,
      shootingMatch: shootingMatch,
      filters: filters,
      scores: scores,
      pool: pool,
      kind: kind,
      ageCategoryFilter: (ageFilter == null || ageFilter.isEmpty) ? null : ageFilter,
      categoryFilter: (categoryFilter == null || categoryFilter.isEmpty) ? null : categoryFilter,
    ));
  }

  Future<ResearchResult<MatchEntry>> _resolveMatchEntry(
    ShootingMatch match, {
    String? memberNumber,
    int? ratingId,
    String? projectName,
  }) async {
    String? mn = memberNumber?.trim();
    if ((mn == null || mn.isEmpty) && ratingId != null) {
      final resolvedRes = await _resolveShooterRating(
        projectName: projectName,
        ratingId: ratingId,
      );
      if (resolvedRes.isErr()) {
        return Result.errFrom(resolvedRes);
      }
      mn = resolvedRes.unwrap().rating.memberNumber;
    }
    if (mn == null || mn.isEmpty) {
      return Result.err(ResearchError("memberNumber or ratingId is required"));
    }

    final processor = ShooterDeduplicator.numberProcessor(match.sport);
    final processed = processor(mn);
    final matches = match.shooters.where((s) {
      if (s.memberNumber == mn || s.memberNumber == processed) {
        return true;
      }
      final sProcessed = processor(s.memberNumber);
      return sProcessed == processed || s.knownMemberNumbers.contains(mn) || s.knownMemberNumbers.contains(processed);
    }).toList();

    if (matches.isEmpty) {
      return Result.err(ResearchError(
        "Competitor not found in match: memberNumber=$mn",
        statusCode: 404,
      ));
    }
    // Prefer non-reentry when multiple entries exist.
    final primary = matches.firstWhereOrNull((s) => !s.reentry) ?? matches.first;
    return Result.ok(primary);
  }

  String _scoringKind(Sport sport) {
    if (sport.type.isHitFactor) {
      return "hitFactor";
    }
    if (sport.type.isTimePlus) {
      return "timePlus";
    }
    if (sport.type.isPoints) {
      return "points";
    }
    return "hitFactor";
  }

  MatchScoreRowDto _matchScoreRow(
    MatchEntry shooter,
    RelativeMatchScore score, {
    required String scoringKind,
    required bool includeStages,
    required bool includeScoringEventCounts,
  }) {
    final total = score.total;
    return MatchScoreRowDto(
      place: score.place,
      name: "${shooter.firstName} ${shooter.lastName}".trim(),
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      memberNumber: shooter.memberNumber,
      classification: shooter.classification?.displayName ?? shooter.classification?.name,
      division: shooter.division?.displayName ?? shooter.division?.name,
      powerFactor: shooter.powerFactor.displayName,
      female: shooter.female,
      ageCategory: shooter.ageCategory?.displayName ?? shooter.ageCategory?.name,
      categories: shooter.categories.map((c) => c.displayName).toList(),
      ratio: score.ratio,
      percentage: score.percentage,
      points: score.points,
      finalTime: total.finalTime,
      hitFactor: scoringKind == "hitFactor" ? total.hitFactor : null,
      rawPoints: scoringKind == "hitFactor" || scoringKind == "points"
          ? total.getTotalPoints().toDouble()
          : null,
      dq: shooter.dq,
      reentry: shooter.reentry,
      squad: shooter.squad,
      entryId: shooter.entryId,
      eventCounts: includeScoringEventCounts ? _eventCountsDto(total) : null,
      stages: includeStages
          ? _stageScoreDtos(
              score,
              scoringKind: scoringKind,
              includeScoringEventCounts: includeScoringEventCounts,
            )
          : const [],
    );
  }

  List<StageScoreDto> _stageScoreDtos(
    RelativeMatchScore matchScore, {
    required String scoringKind,
    required bool includeScoringEventCounts,
  }) {
    final stages = matchScore.stageScores.entries.toList()
      ..sort((a, b) => a.key.stageId.compareTo(b.key.stageId));
    return stages.map((e) {
      final stage = e.key;
      final stageScore = e.value;
      final raw = stageScore.score;
      return StageScoreDto(
        stageNumber: stage.stageId,
        stageName: stage.name,
        place: stageScore.place,
        ratio: stageScore.ratio,
        percentage: stageScore.percentage,
        points: stageScore.points,
        finalTime: raw.finalTime,
        hitFactor: scoringKind == "hitFactor" ? raw.hitFactor : null,
        rawPoints: scoringKind == "hitFactor" || scoringKind == "points"
            ? raw.getTotalPoints().toDouble()
            : null,
        dnf: stageScore.isDnf,
        eventCounts: includeScoringEventCounts ? _eventCountsDto(raw) : null,
      );
    }).toList();
  }

  ScoringEventCountsDto _eventCountsDto(RawScore raw) {
    final target = <String, int>{};
    for (final e in raw.targetEvents.entries) {
      if (e.value != 0) {
        target[e.key.name] = e.value;
      }
    }
    final penalties = <String, int>{};
    for (final e in raw.penaltyEvents.entries) {
      if (e.value != 0) {
        penalties[e.key.name] = e.value;
      }
    }
    final penaltyCount = penalties.values.fold<int>(0, (a, b) => a + b);
    return ScoringEventCountsDto(
      targetEvents: target,
      penaltyEvents: penalties,
      penaltyCount: penaltyCount,
      hasPenalties: penaltyCount > 0,
    );
  }

  ResearchResult<Division> _lookupDivision(Sport sport, String name) {
    final exact = sport.divisions.lookupByName(name);
    if (exact != null) {
      return Result.ok(exact);
    }
    final lower = name.toLowerCase();
    final fuzzy = sport.divisions.values.where((d) {
      return d.name.toLowerCase().contains(lower) ||
          d.displayName.toLowerCase().contains(lower);
    }).toList();
    if (fuzzy.length == 1) {
      return Result.ok(fuzzy.first);
    }
    if (fuzzy.isEmpty) {
      return Result.err(ResearchError("Unknown division: $name", statusCode: 404));
    }
    return Result.err(ResearchError(
      "Ambiguous division '$name': ${fuzzy.map((d) => d.displayName).join(", ")}",
    ));
  }

  Future<ResearchResult<DbRatingProject>> _requireProject(String name) async {
    final project = await db.getRatingProjectByName(name);
    if (project == null) {
      return Result.err(ResearchError("Rating project not found: $name", statusCode: 404));
    }
    return Result.ok(project);
  }

  ResearchResult<List<RatingGroup>> _resolveGroups(
    DbRatingProject project, {
    String? groupUuid,
    String? groupName,
  }) {
    final all = [...project.groups];
    if (groupUuid != null && groupUuid.isNotEmpty) {
      final g = all.firstWhereOrNull((g) => g.uuid == groupUuid);
      if (g == null) {
        return Result.err(ResearchError("Rating group not found: uuid=$groupUuid", statusCode: 404));
      }
      return Result.ok([g]);
    }
    if (groupName != null && groupName.isNotEmpty) {
      final lower = groupName.toLowerCase();
      final exact = all.where((g) => g.name.toLowerCase() == lower).toList();
      if (exact.isNotEmpty) {
        return Result.ok(exact);
      }
      final partial = all.where((g) => g.name.toLowerCase().contains(lower)).toList();
      if (partial.length == 1) {
        return Result.ok(partial);
      }
      if (partial.isEmpty) {
        return Result.err(ResearchError("Rating group not found: name=$groupName", statusCode: 404));
      }
      return Result.err(ResearchError(
        "Ambiguous rating group name '$groupName'; matches: "
        "${partial.map((g) => g.name).join(", ")}. "
        "Use an exact group name or groupUuid.",
      ));
    }
    return Result.ok(all);
  }

  Future<ResearchResult<({DbRatingProject project, RatingGroup group, DbShooterRating rating})>> _resolveShooterRating({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
  }) async {
    if (ratingId != null) {
      final rating = await db.getRatingById(ratingId);
      if (rating == null) {
        return Result.err(ResearchError("Shooter rating not found: id=$ratingId", statusCode: 404));
      }
      if (!rating.group.isLoaded) {
        await rating.group.load();
      }
      if (!rating.project.isLoaded) {
        await rating.project.load();
      }
      final group = rating.group.value;
      final proj = rating.project.value;
      if (group == null || proj == null) {
        return Result.err(ResearchError("Shooter rating $ratingId missing project/group links", statusCode: 500));
      }
      return Result.ok((project: proj, group: group, rating: rating));
    }

    final projectRes = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (projectRes.isErr()) {
      return Result.errFrom(projectRes);
    }
    final project = projectRes.unwrap();
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }

    final mn = memberNumber?.trim();
    if (mn == null || mn.isEmpty) {
      return Result.err(ResearchError("memberNumber or ratingId is required"));
    }

    final groupsRes = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
    if (groupsRes.isErr()) {
      return Result.errFrom(groupsRes);
    }
    final groups = groupsRes.unwrap();
    DbShooterRating? found;
    RatingGroup? foundGroup;
    for (final group in groups) {
      final rating = await db.maybeKnownShooter(
        project: project,
        group: group,
        memberNumber: mn,
        usePossibleMemberNumbers: true,
      );
      if (rating != null) {
        found = rating;
        foundGroup = group;
        break;
      }
    }
    if (found == null || foundGroup == null) {
      return Result.err(ResearchError(
        "Shooter not found: memberNumber=$mn project=${project.name}",
        statusCode: 404,
      ));
    }
    return Result.ok((project: project, group: foundGroup, rating: found));
  }

  ShooterHitDto _shooterHit(
    DbRatingProject project,
    DbShooterRating rating,
    RatingGroup group, {
    bool includeInternal = false,
  }) {
    final wrapped = project.wrapDbRatingSync(rating);
    final algo = project.settings.algorithm;
    return ShooterHitDto(
      ratingId: rating.id,
      firstName: rating.firstName,
      lastName: rating.lastName,
      name: "${rating.firstName} ${rating.lastName}".trim(),
      memberNumber: rating.memberNumber,
      deduplicatorName: rating.deduplicatorName,
      groupUuid: group.uuid,
      groupName: group.name,
      rating: wrapped.scaledRating,
      agedRating: algo.scaleRating(wrapped.agedRating),
      classification: rating.lastClassificationName,
      division: rating.divisionName,
      female: rating.female,
      ageCategory: rating.ageCategoryName,
      categories: [...rating.categoryNames],
      region: rating.region,
      regionSubdivision: rating.regionSubdivision,
      rawLocation: rating.rawLocation,
      internalRating: includeInternal ? wrapped.rating : null,
      internalAgedRating: includeInternal ? wrapped.agedRating : null,
    );
  }

  RatingProjectDto _projectDto(DbRatingProject p) {
    final algo = p.settings.algorithm;
    final algoId = _algorithmId(p);
    final latestRes = _latestMatchDate(p);
    return RatingProjectDto(
      id: p.id,
      name: p.name,
      sportName: p.sportName,
      matchCount: p.matchPointers.length,
      groups: p.groups
          .map((g) => RatingGroupDto(uuid: g.uuid, name: g.name))
          .toList(),
      algorithm: algoId,
      algorithmLabel: _algorithmLabel(algoId),
      supportedSorts: algo.supportedSorts
          .map((m) => RatingSortModeDto(id: m.name, label: algo.nameForSort(m)))
          .toList(),
      latestMatchDate: latestRes.isOk() ? latestRes.unwrap() : null,
      byStage: algo.byStage,
    );
  }

  ResearchResult<RatingGroup> _requireSingleGroup(
    DbRatingProject project, {
    String? groupUuid,
    String? groupName,
  }) {
    final groupsRes = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
    if (groupsRes.isErr()) {
      return Result.errFrom(groupsRes);
    }
    final groups = groupsRes.unwrap();
    if (groups.length == 1) {
      return Result.ok(groups.first);
    }
    if (groups.isEmpty) {
      return Result.err(ResearchError("No rating groups in project ${project.name}", statusCode: 404));
    }
    return Result.err(ResearchError(
      "Specify group or groupUuid; project has multiple groups: "
      "${groups.map((g) => g.name).join(", ")}",
    ));
  }

  ResearchResult<DateTime> _latestMatchDate(DbRatingProject project) {
    final dated = project.matchPointers.where((m) => m.date != null).toList();
    if (dated.isEmpty) {
      return Result.err(ResearchError(
        "Project ${project.name} has no dated matches",
        statusCode: 500,
      ));
    }
    dated.sort((a, b) => b.date!.compareTo(a.date!));
    return Result.ok(dated.first.date!);
  }

  ResearchResult<RatingSortMode> _parseSortMode(String? raw, RatingSystem algo) {
    if (raw == null || raw.trim().isEmpty) {
      return Result.ok(algo.supportedSorts.first);
    }
    final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r"[\s_\-+±]"), "");
    RatingSortMode? match;
    for (final mode in RatingSortMode.values) {
      final name = mode.name.toLowerCase();
      final label = mode.uiLabel.toLowerCase().replaceAll(RegExp(r"[\s_\-+±]"), "");
      if (name == normalized || label == normalized) {
        match = mode;
        break;
      }
    }
    if (match == null && (normalized == "movers" || normalized == "lastpm")) {
      match = RatingSortMode.lastChange;
    }
    if (match == null) {
      return Result.err(ResearchError(
        "Unknown sort '$raw'. Supported: "
        "${algo.supportedSorts.map((m) => m.name).join(", ")}",
      ));
    }
    if (!algo.supportedSorts.contains(match)) {
      return Result.err(ResearchError(
        "Sort '${match.name}' is not supported by this project's algorithm. "
        "Supported: ${algo.supportedSorts.map((m) => m.name).join(", ")}",
      ));
    }
    return Result.ok(match);
  }

  String _algorithmId(DbRatingProject project) {
    final json = project.jsonDecodedSettings;
    return (json[DbRatingProject.algorithmKey] as String?)
        ?? DbRatingProject.multiplayerEloValue;
  }

  String _algorithmLabel(String id) {
    switch (id) {
      case DbRatingProject.multiplayerEloValue:
        return "Multiplayer Elo";
      case DbRatingProject.latentLogValue:
        return "Latent Log Ratio";
      case DbRatingProject.openskillValue:
        return "OpenSkill";
      case DbRatingProject.pointsValue:
        return "Points";
      case DbRatingProject.marbleValue:
        return "Marbles";
      case DbRatingProject.glicko2Value:
        return "Glicko-2";
      default:
        return id;
    }
  }

  double _scaleChange(RatingSystem algo, double change) {
    return algo.scaleRating(change) - algo.scaleRating(0);
  }

  double _sortValue(
    ShooterRating rating,
    RatingSystem algo,
    RatingSortMode sortMode, {
    DateTime? changeSince,
  }) {
    switch (sortMode) {
      case RatingSortMode.rating:
        return rating.scaledRating;
      case RatingSortMode.agedRating:
        if (rating is LatentLogRating) {
          return algo.scaleRating(rating.calculateAgedRating());
        }
        return algo.scaleRating(rating.agedRating);
      case RatingSortMode.lastChange:
        return _scaleChange(algo, rating.lastMatchChange);
      case RatingSortMode.trend:
        if (changeSince != null) {
          return _scaleChange(algo, rating.rating - rating.ratingForDate(changeSince));
        }
        return _scaleChange(algo, rating.trend.toDouble());
      case RatingSortMode.error:
        if (rating is LatentLogRating) {
          return rating.variance;
        }
        if (rating is EloShooterRating) {
          return rating.standardError;
        }
        return rating.wrappedRating.error;
      case RatingSortMode.dispersion:
        if (rating is LatentLogRating) {
          return rating.dispersion;
        }
        return 0;
      case RatingSortMode.direction:
        if (rating is EloShooterRating) {
          return rating.direction;
        }
        return rating.trend.toDouble();
      case RatingSortMode.stages:
        return rating.length.toDouble();
      case RatingSortMode.pointsPerMatch:
        final mc = rating.matchCount ?? rating.length;
        if (mc == 0) return 0;
        return rating.scaledRating / mc;
      case RatingSortMode.classification:
      case RatingSortMode.firstName:
      case RatingSortMode.lastName:
        return rating.scaledRating;
    }
  }

  LeaderboardEntryDto _leaderboardEntry({
    required int place,
    required DbRatingProject project,
    required ShooterRating rating,
    required RatingSortMode sortMode,
    DateTime? changeSince,
  }) {
    final algo = project.settings.algorithm;
    final db = rating.wrappedRating;
    final sortValue = _sortValue(rating, algo, sortMode, changeSince: changeSince);

    double? lastChange;
    try {
      lastChange = _scaleChange(algo, rating.lastMatchChange);
    } catch (_) {
      lastChange = null;
    }

    return LeaderboardEntryDto(
      place: place,
      ratingId: db.id,
      firstName: rating.firstName,
      lastName: rating.lastName,
      name: "${rating.firstName} ${rating.lastName}".trim(),
      memberNumber: rating.memberNumber,
      rating: rating.scaledRating,
      agedRating: algo.scaleRating(rating.agedRating),
      sortValue: sortValue,
      lastSeen: rating.lastSeen,
      classification: db.lastClassificationName,
      division: db.divisionName,
      female: rating.female,
      ageCategory: db.ageCategoryName,
      categories: [...db.categoryNames],
      region: rating.region,
      regionSubdivision: rating.regionSubdivision,
      rawLocation: rating.rawLocation,
      matchCount: rating.matchCount,
      historyLength: rating.length,
      lastChange: lastChange,
    );
  }

  Future<MatchPrepHitDto> _matchPrepHit(MatchPrep prep, {required String projectName}) async {
    if (!prep.futureMatch.isLoaded) {
      await prep.futureMatch.load();
    }
    final match = prep.futureMatch.value;
    final sets = await db.getPredictionSetsForMatchPrep(prep);
    final latest = sets.isEmpty ? null : sets.first;
    return MatchPrepHitDto(
      id: prep.id.toString(),
      matchName: match?.eventName ?? "Unknown Match",
      matchDate: match?.date ?? practicalShootingZeroDate,
      projectName: projectName,
      predictionSetCount: sets.length,
      latestPredictionSet: latest == null
          ? null
          : PredictionSetStubDto(
              id: latest.id.toString(),
              name: latest.name,
              created: latest.created,
            ),
    );
  }

  Future<PredictionSetDto> _predictionSetDto(PredictionSet set) async {
    final count = await db.isar.dbAlgorithmPredictions
        .where()
        .predictionSetIdEqualTo(set.id)
        .count();
    return PredictionSetDto(
      id: set.id.toString(),
      name: set.name,
      created: set.created,
      predictionCount: count,
      note: (set.note == null || set.note!.trim().isEmpty) ? null : set.note,
      matchPrepId: set.matchPrepId.toString(),
    );
  }

  ResearchResult<int> _parseResearchId(String raw, String label) {
    final n = int.tryParse(raw.trim());
    if (n == null) {
      return Result.err(ResearchError("Invalid $label: $raw"));
    }
    return Result.ok(n);
  }

  Future<ResearchResult<PredictionSet>> _resolvePredictionSet({
    String? predictionSetId,
    String? prepId,
  }) async {
    if (predictionSetId != null && predictionSetId.trim().isNotEmpty) {
      final idRes = _parseResearchId(predictionSetId, "predictionSetId");
      if (idRes.isErr()) {
        return Result.errFrom(idRes);
      }
      final set = await db.isar.predictionSets.get(idRes.unwrap());
      if (set == null) {
        return Result.err(ResearchError(
          "Prediction set not found: id=$predictionSetId",
          statusCode: 404,
        ));
      }
      return Result.ok(set);
    }
    if (prepId == null || prepId.trim().isEmpty) {
      return Result.err(ResearchError("predictionSetId or prepId is required"));
    }
    final idRes = _parseResearchId(prepId, "prepId");
    if (idRes.isErr()) {
      return Result.errFrom(idRes);
    }
    final prep = await db.getMatchPrepById(idRes.unwrap());
    if (prep == null) {
      return Result.err(ResearchError("Match prep not found: id=$prepId", statusCode: 404));
    }
    final latest = prep.latestPredictionSet();
    if (latest == null) {
      return Result.err(ResearchError(
        "No prediction sets for match prep $prepId",
        statusCode: 404,
      ));
    }
    return Result.ok(latest);
  }

  Future<ResearchResult<DbRatingProject>> _projectForPredictionSet(PredictionSet set) async {
    if (!set.matchPrep.isLoaded) {
      await set.matchPrep.load();
    }
    final prep = set.matchPrep.value;
    if (prep == null) {
      final byId = await db.getMatchPrepById(set.matchPrepId);
      if (byId == null) {
        return Result.err(ResearchError(
          "Match prep not found for prediction set ${set.id}",
          statusCode: 500,
        ));
      }
      if (!byId.ratingProject.isLoaded) {
        await byId.ratingProject.load();
      }
      final project = byId.ratingProject.value;
      if (project == null) {
        return Result.err(ResearchError(
          "Rating project missing for match prep ${byId.id}",
          statusCode: 500,
        ));
      }
      return Result.ok(project);
    }
    if (!prep.ratingProject.isLoaded) {
      await prep.ratingProject.load();
    }
    final project = prep.ratingProject.value;
    if (project == null) {
      return Result.err(ResearchError(
        "Rating project missing for match prep ${prep.id}",
        statusCode: 500,
      ));
    }
    return Result.ok(project);
  }

  Future<List<PredictionRowDto>> _loadPredictionRows(
    PredictionSet set, {
    RatingGroup? scoringGroup,
  }) async {
    final loaded = await _loadPredictionsWithRatings(set, scoringGroup: scoringGroup);
    return loaded.map((e) => e.row).toList();
  }

  Future<List<({DbAlgorithmPrediction prediction, DbShooterRating? rating, PredictionRowDto row})>>
      _loadPredictionsWithRatings(
    PredictionSet set, {
    RatingGroup? scoringGroup,
  }) async {
    final preds = await db.isar.dbAlgorithmPredictions
        .where()
        .predictionSetIdEqualTo(set.id)
        .findAll();
    final out = <({DbAlgorithmPrediction prediction, DbShooterRating? rating, PredictionRowDto row})>[];
    for (final pred in preds) {
      final effectiveUuid = pred.scoringGroupUuid ?? pred.groupUuid;
      if (scoringGroup != null && effectiveUuid != scoringGroup.uuid) {
        continue;
      }
      if (!pred.rating.isLoaded) {
        await pred.rating.load();
      }
      if (!pred.scoringGroup.isLoaded) {
        await pred.scoringGroup.load();
      }
      if (!pred.group.isLoaded) {
        await pred.group.load();
      }
      final rating = pred.rating.value;
      final scoringName = pred.scoringGroup.value?.name
          ?? pred.group.value?.name
          ?? effectiveUuid
          ?? "unknown";
      final scoringUuid = effectiveUuid ?? "";
      final firstName = rating?.firstName ?? "";
      final lastName = rating?.lastName ?? "";
      final name = "$firstName $lastName".trim();
      out.add((
        prediction: pred,
        rating: rating,
        row: PredictionRowDto(
          memberNumber: pred.memberNumber,
          ratingId: rating?.id,
          name: name.isEmpty ? pred.memberNumber : name,
          firstName: firstName,
          lastName: lastName,
          classification: rating?.lastClassificationName,
          scoringGroup: scoringName,
          scoringGroupUuid: scoringUuid,
          medianPlace: pred.medianPlace,
          lowPlace: pred.lowPlace,
          highPlace: pred.highPlace,
          mean: pred.mean,
          oneSigma: pred.oneSigma,
          meanRatio: pred.meanRatio,
          oneSigmaRatio: pred.oneSigmaRatio,
        ),
      ));
    }
    return out;
  }
}

class _ResolvedMatchPool {
  _ResolvedMatchPool({
    required this.dbMatch,
    required this.shootingMatch,
    required this.filters,
    required this.scores,
    required this.pool,
    required this.kind,
    this.ageCategoryFilter,
    this.categoryFilter,
  });

  final DbShootingMatch dbMatch;
  final ShootingMatch shootingMatch;
  final FilterSet filters;
  final Map<MatchEntry, RelativeMatchScore> scores;
  final String pool;
  final String kind;
  final String? ageCategoryFilter;
  final String? categoryFilter;
}
