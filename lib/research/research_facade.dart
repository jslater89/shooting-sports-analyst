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
      out.add(RatingProjectDto(
        id: p.id,
        name: p.name,
        sportName: p.sportName,
        matchCount: p.matchPointers.length,
        groups: p.groups
            .map((g) => RatingGroupDto(uuid: g.uuid, name: g.name))
            .toList(),
      ));
    }
    return out;
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
    final dbMatch = await _resolveMatch(matchId: matchId, matchQuery: matchQuery);
    final shootingMatch = await _hydrate(dbMatch);
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
        "Specify division, group/groupUuid, or overall=true for getMatchResults",
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
    final scored = scores.entries.toList()
      ..sort((a, b) => a.value.place.compareTo(b.value.place));
    final limit = topN != null && topN > 0 ? topN : scored.length;
    final results = <MatchCompetitorResultDto>[];
    for (final e in scored.take(limit)) {
      results.add(_competitorResult(e.key, e.value));
    }

    return MatchResultsResponse(
      match: _matchSummary(dbMatch),
      pool: pool,
      kind: kind,
      femaleOnly: femaleOnly,
      ageCategory: (ageFilter == null || ageFilter.isEmpty) ? null : ageFilter,
      category: (categoryFilter == null || categoryFilter.isEmpty) ? null : categoryFilter,
      competitorCount: scored.length,
      results: results,
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
      final displayOld = algo.scaleRating(e.oldRating);
      final displayNew = algo.scaleRating(e.newRating);
      byMatch[e.matchId] = ShooterMatchResultDto(
        matchId: e.matchId,
        matchName: matchName,
        date: e.date,
        place: e.matchScore.place,
        ratio: e.matchScore.ratio,
        percentage: e.matchScore.percentage,
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
}
