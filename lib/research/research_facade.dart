/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/match.dart";
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

final _log = SSALogger("ResearchFacade");

/// Read-only research queries over [AnalystDatabase].
///
/// Shared by the stdio MCP server and the optional in-app localhost MCP host.
class ResearchFacade {
  ResearchFacade(this.db);

  final AnalystDatabase db;

  Future<List<RatingProjectDto>> listRatingProjects({String? name, int limit = 50}) async {
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
    return out;
  }

  Future<LeaderboardResponse> getLeaderboard({
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
      throw ResearchException("limit must be >= 1");
    }
    if (minMatches < 0) {
      throw ResearchException("minMatches must be >= 0");
    }

    final project = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }
    final group = _requireSingleGroup(project, groupUuid: groupUuid, groupName: groupName);
    final algo = project.settings.algorithm;
    final sortMode = _parseSortMode(sort, algo);
    final latestMatchDate = _latestMatchDate(project);
    final effectiveSeenSince = seenSince ?? DateTime(latestMatchDate.year - 1, 1, 1);

    final ratingsRes = await project.getRatings(group);
    if (ratingsRes.isErr()) {
      throw ResearchException(
        "Failed to load ratings for group ${group.name}: ${ratingsRes.unwrapErr()}",
        statusCode: 500,
      );
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

    return LeaderboardResponse(
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
    );
  }

  Future<List<MatchSummaryDto>> searchMatches({
    required String query,
    int limit = 10,
    DateTime? after,
    DateTime? before,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      throw ResearchException("query is required");
    }
    final matches = await db.matchNameTextSearch(
      q,
      limit: limit,
      after: after,
      before: before,
    );
    return matches.map(_matchSummary).toList();
  }

  Future<MatchWinnersResponse> getMatchWinners({
    int? matchId,
    String? matchQuery,
    String? projectName,
    bool byRatingGroup = false,
    int topN = 1,
  }) async {
    if (topN < 1) {
      throw ResearchException("topN must be >= 1");
    }
    final dbMatch = await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    final shootingMatch = await _hydrate(dbMatch);

    final winners = <MatchWinnerDto>[];
    if (byRatingGroup) {
      final project = await _requireProject(projectName ?? kDefaultResearchProjectName);
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

    return MatchWinnersResponse(
      match: _matchSummary(dbMatch),
      winners: winners,
    );
  }

  /// Fuller standings for one scoring pool (division, rating group, or overall).
  ///
  /// Optional [femaleOnly], [ageCategory], and [category] narrow the competitor
  /// pool before scoring (same semantics as UI [FilterSet]).
  Future<MatchResultsResponse> getMatchResults({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    int? topN,
    bool overall = false,
  }) async {
    final resolved = await _resolveMatchPool(
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
    final scored = resolved.scores.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));
    final limit = topN != null && topN > 0 ? topN : scored.length;
    final results = <MatchCompetitorResultDto>[];
    for (final e in scored.take(limit)) {
      results.add(_competitorResult(e.key, e.value));
    }

    return MatchResultsResponse(
      match: _matchSummary(resolved.dbMatch),
      pool: resolved.pool,
      kind: resolved.kind,
      femaleOnly: femaleOnly,
      ageCategory: resolved.ageCategoryFilter,
      category: resolved.categoryFilter,
      competitorCount: scored.length,
      results: results,
    );
  }

  /// Detailed match scores for one scoring pool, with optional stages and event counts.
  Future<MatchScoresResponse> getMatchScores({
    int? matchId,
    String? matchQuery,
    String? projectName,
    String? division,
    String? groupUuid,
    String? groupName,
    bool femaleOnly = false,
    String? ageCategory,
    String? category,
    int? topN,
    bool overall = false,
    bool includeStages = false,
    bool includeScoringEventCounts = false,
  }) async {
    final resolved = await _resolveMatchPool(
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
    final scoringKind = _scoringKind(resolved.shootingMatch.sport);
    final scored = resolved.scores.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));
    final limit = topN != null && topN > 0 ? topN : scored.length;
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

    return MatchScoresResponse(
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
    );
  }

  /// One competitor's stage scores at a match.
  ///
  /// If no pool is specified, defaults to the competitor's entered division.
  Future<CompetitorStageScoresResponse> getCompetitorStageScores({
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
    final dbMatch = await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    final shootingMatch = await _hydrate(dbMatch);
    final sport = shootingMatch.sport;

    final entry = await _resolveMatchEntry(
      shootingMatch,
      memberNumber: memberNumber,
      ratingId: ratingId,
      projectName: projectName,
    );

    final hasExplicitPool = overall ||
        (division != null && division.trim().isNotEmpty) ||
        (groupUuid != null && groupUuid.isNotEmpty) ||
        (groupName != null && groupName.isNotEmpty);

    late final _ResolvedMatchPool resolved;
    if (hasExplicitPool) {
      resolved = await _resolveMatchPool(
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
        throw ResearchException(
          "Competitor has no entered division; specify division, group/groupUuid, or overall=true",
        );
      }
      resolved = await _resolveMatchPool(
        matchId: dbMatch.id,
        projectName: projectName,
        division: entered.name,
        preloadedDbMatch: dbMatch,
        preloadedShootingMatch: shootingMatch,
      );
    }

    final score = resolved.scores[entry];
    if (score == null) {
      throw ResearchException(
        "Competitor ${entry.memberNumber} is not in scoring pool '${resolved.pool}'",
        statusCode: 404,
      );
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

    return CompetitorStageScoresResponse(
      match: _matchSummary(dbMatch),
      pool: resolved.pool,
      kind: resolved.kind,
      scoringKind: scoringKind,
      competitor: competitorRow,
      stages: stages,
      includeScoringEventCounts: includeScoringEventCounts,
    );
  }

  Future<List<ShooterHitDto>> searchShooters({
    required String query,
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int limit = 20,
    bool includeInternal = false,
  }) async {
    final project = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }
    final groups = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
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
      return hits.take(limit).toList();
    }

    final q = query.trim();
    if (q.length < 2) {
      throw ResearchException("query must be at least 2 characters (or pass memberNumber)");
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
    return hits.take(limit).toList();
  }

  Future<ShooterSummaryDto> getShooterSummary({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    bool includeInternal = false,
  }) async {
    final resolved = await _resolveShooterRating(
      projectName: projectName,
      groupUuid: groupUuid,
      groupName: groupName,
      memberNumber: memberNumber,
      ratingId: ratingId,
    );
    final rating = resolved.rating;
    final group = resolved.group;
    final project = resolved.project;
    final wrapped = project.wrapDbRatingSync(rating);
    final algo = project.settings.algorithm;

    return ShooterSummaryDto(
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
    );
  }

  Future<List<RatingEventDto>> getRatingHistory({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool matchLevelOnly = true,
    bool includeInternal = false,
  }) async {
    final resolved = await _resolveShooterRating(
      projectName: projectName,
      groupUuid: groupUuid,
      groupName: groupName,
      memberNumber: memberNumber,
      ratingId: ratingId,
    );
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
    return out;
  }

  Future<List<ShooterMatchResultDto>> getShooterMatchResults({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
    int limit = 50,
    bool includeInternal = false,
  }) async {
    final resolved = await _resolveShooterRating(
      projectName: projectName,
      groupUuid: groupUuid,
      groupName: groupName,
      memberNumber: memberNumber,
      ratingId: ratingId,
    );
    final algo = resolved.project.settings.algorithm;
    final events = await db.getRatingEventsFor(resolved.rating, limit: limit * 8);
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
      if (byMatch.length >= limit) {
        break;
      }
    }
    return byMatch.values.toList();
  }

  MatchSummaryDto _matchSummary(DbShootingMatch m) => MatchSummaryDto(
        id: m.id,
        name: m.eventName,
        date: m.date,
        sportName: m.sportName,
        sourceIds: [...m.sourceIds],
      );

  Future<DbShootingMatch> _resolveMatch({int? matchId, String? matchQuery}) async {
    if (matchId != null) {
      final m = await db.getMatch(matchId);
      if (m == null) {
        throw ResearchException("Match not found: id=$matchId", statusCode: 404);
      }
      return m;
    }
    final q = matchQuery?.trim();
    if (q == null || q.isEmpty) {
      throw ResearchException("matchId or matchQuery is required");
    }
    final hits = await db.matchNameTextSearch(q, limit: 5);
    if (hits.isEmpty) {
      throw ResearchException("No matches found for query: $q", statusCode: 404);
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
    return hits.first;
  }

  Future<ShootingMatch> _hydrate(DbShootingMatch dbMatch) async {
    if (dbMatch.shootersStoredSeparately) {
      await dbMatch.shooterLinks.load();
    }
    final hydrated = await dbMatch.hydrate();
    if (hydrated.isErr()) {
      throw ResearchException(
        "Failed to hydrate match ${dbMatch.eventName}: ${hydrated.unwrapErr()}",
        statusCode: 500,
      );
    }
    return hydrated.unwrap();
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

  Future<_ResolvedMatchPool> _resolveMatchPool({
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
    final dbMatch = preloadedDbMatch ??
        await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    final shootingMatch = preloadedShootingMatch ?? await _hydrate(dbMatch);
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
      final project = await _requireProject(projectName ?? kDefaultResearchProjectName);
      if (!project.dbGroups.isLoaded) {
        await project.dbGroups.load();
      }
      final groups = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
      if (groups.length != 1) {
        throw ResearchException(
          "Specify a single rating group (got ${groups.length}). Pass groupUuid or a unique group name.",
        );
      }
      filters = groups.first.filters;
      pool = groups.first.name;
      kind = "ratingGroup";
    }
    else if (division != null && division.trim().isNotEmpty) {
      final div = _lookupDivision(sport, division.trim());
      filters = FilterSet.forDivision(sport, div);
      pool = div.displayName;
      kind = "division";
    }
    else {
      throw ResearchException(
        "Specify division, group/groupUuid, or overall=true",
      );
    }

    filters.femaleOnly = femaleOnly;
    final ageFilter = ageCategory?.trim();
    final categoryFilter = category?.trim();
    if (ageFilter != null && ageFilter.isNotEmpty) {
      final age = sport.ageCategories.lookupByName(ageFilter);
      if (age == null) {
        throw ResearchException("Unknown age category: $ageFilter", statusCode: 404);
      }
      for (final key in filters.ageCategories.keys.toList()) {
        filters.ageCategories[key] = key == age;
      }
    }
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      final cat = sport.categories.lookupByName(categoryFilter);
      if (cat == null) {
        throw ResearchException("Unknown competitor category: $categoryFilter", statusCode: 404);
      }
      for (final key in filters.categories.keys.toList()) {
        filters.categories[key] = key == cat;
      }
    }

    final scores = shootingMatch.getScoresFromFilters(filters);
    return _ResolvedMatchPool(
      dbMatch: dbMatch,
      shootingMatch: shootingMatch,
      filters: filters,
      scores: scores,
      pool: pool,
      kind: kind,
      ageCategoryFilter: (ageFilter == null || ageFilter.isEmpty) ? null : ageFilter,
      categoryFilter: (categoryFilter == null || categoryFilter.isEmpty) ? null : categoryFilter,
    );
  }

  Future<MatchEntry> _resolveMatchEntry(
    ShootingMatch match, {
    String? memberNumber,
    int? ratingId,
    String? projectName,
  }) async {
    String? mn = memberNumber?.trim();
    if ((mn == null || mn.isEmpty) && ratingId != null) {
      final resolved = await _resolveShooterRating(
        projectName: projectName,
        ratingId: ratingId,
      );
      mn = resolved.rating.memberNumber;
    }
    if (mn == null || mn.isEmpty) {
      throw ResearchException("memberNumber or ratingId is required");
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
      throw ResearchException(
        "Competitor not found in match: memberNumber=$mn",
        statusCode: 404,
      );
    }
    // Prefer non-reentry when multiple entries exist.
    final primary = matches.firstWhereOrNull((s) => !s.reentry) ?? matches.first;
    return primary;
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

  Division _lookupDivision(Sport sport, String name) {
    final exact = sport.divisions.lookupByName(name);
    if (exact != null) {
      return exact;
    }
    final lower = name.toLowerCase();
    final fuzzy = sport.divisions.values.where((d) {
      return d.name.toLowerCase().contains(lower) ||
          d.displayName.toLowerCase().contains(lower);
    }).toList();
    if (fuzzy.length == 1) {
      return fuzzy.first;
    }
    if (fuzzy.isEmpty) {
      throw ResearchException("Unknown division: $name", statusCode: 404);
    }
    throw ResearchException(
      "Ambiguous division '$name': ${fuzzy.map((d) => d.displayName).join(", ")}",
    );
  }

  Future<DbRatingProject> _requireProject(String name) async {
    final project = await db.getRatingProjectByName(name);
    if (project == null) {
      throw ResearchException("Rating project not found: $name", statusCode: 404);
    }
    return project;
  }

  List<RatingGroup> _resolveGroups(
    DbRatingProject project, {
    String? groupUuid,
    String? groupName,
  }) {
    final all = [...project.groups];
    if (groupUuid != null && groupUuid.isNotEmpty) {
      final g = all.firstWhereOrNull((g) => g.uuid == groupUuid);
      if (g == null) {
        throw ResearchException("Rating group not found: uuid=$groupUuid", statusCode: 404);
      }
      return [g];
    }
    if (groupName != null && groupName.isNotEmpty) {
      final lower = groupName.toLowerCase();
      final matches = all.where((g) => g.name.toLowerCase().contains(lower)).toList();
      if (matches.isEmpty) {
        throw ResearchException("Rating group not found: name=$groupName", statusCode: 404);
      }
      return matches;
    }
    return all;
  }

  Future<({DbRatingProject project, RatingGroup group, DbShooterRating rating})> _resolveShooterRating({
    String? projectName,
    String? groupUuid,
    String? groupName,
    String? memberNumber,
    int? ratingId,
  }) async {
    if (ratingId != null) {
      final rating = await db.getRatingById(ratingId);
      if (rating == null) {
        throw ResearchException("Shooter rating not found: id=$ratingId", statusCode: 404);
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
        throw ResearchException("Shooter rating $ratingId missing project/group links", statusCode: 500);
      }
      return (project: proj, group: group, rating: rating);
    }

    final project = await _requireProject(projectName ?? kDefaultResearchProjectName);
    if (!project.dbGroups.isLoaded) {
      await project.dbGroups.load();
    }

    final mn = memberNumber?.trim();
    if (mn == null || mn.isEmpty) {
      throw ResearchException("memberNumber or ratingId is required");
    }

    final groups = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
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
      throw ResearchException(
        "Shooter not found: memberNumber=$mn project=${project.name}",
        statusCode: 404,
      );
    }
    return (project: project, group: foundGroup, rating: found);
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
      latestMatchDate: p.matchPointers.isEmpty ? null : _latestMatchDate(p),
      byStage: algo.byStage,
    );
  }

  RatingGroup _requireSingleGroup(
    DbRatingProject project, {
    String? groupUuid,
    String? groupName,
  }) {
    final groups = _resolveGroups(project, groupUuid: groupUuid, groupName: groupName);
    if (groups.length == 1) {
      return groups.first;
    }
    if (groups.isEmpty) {
      throw ResearchException("No rating groups in project ${project.name}", statusCode: 404);
    }
    throw ResearchException(
      "Specify group or groupUuid; project has multiple groups: "
      "${groups.map((g) => g.name).join(", ")}",
    );
  }

  DateTime _latestMatchDate(DbRatingProject project) {
    final dated = project.matchPointers.where((m) => m.date != null).toList();
    if (dated.isEmpty) {
      throw ResearchException(
        "Project ${project.name} has no dated matches",
        statusCode: 500,
      );
    }
    dated.sort((a, b) => b.date!.compareTo(a.date!));
    return dated.first.date!;
  }

  RatingSortMode _parseSortMode(String? raw, RatingSystem algo) {
    if (raw == null || raw.trim().isEmpty) {
      return algo.supportedSorts.first;
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
      throw ResearchException(
        "Unknown sort '$raw'. Supported: "
        "${algo.supportedSorts.map((m) => m.name).join(", ")}",
      );
    }
    if (!algo.supportedSorts.contains(match)) {
      throw ResearchException(
        "Sort '${match.name}' is not supported by this project's algorithm. "
        "Supported: ${algo.supportedSorts.map((m) => m.name).join(", ")}",
      );
    }
    return match;
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
