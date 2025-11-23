/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Serves league endpoints, with a first path element of the league id.
class LeagueService {
  LeagueService([List<Middleware> middleware = const []]) {
    for(final m in middleware) {
      router.use(m);
    }
    router.get("/<leagueId>/player/<playerId>/scoring", getScoring);
  }

  final database = AnalystDatabase();
  final router = Router().plus;

  /// /<leagueId>/player/<playerId>/scoring
  ///
  /// Returns the best score for each month for the given player.
  Future<Response> getScoring(Request request, String leagueId, String playerId) async {
    final ratingContext = await database.getRatingProjectByName("L2s Main");
    if(ratingContext == null) {
      return Response.notFound('Rating project not found');
    }

    final groupRes = await ratingContext.groupForDivision(uspsaRevolver);
    if(groupRes.isErr()) {
      return Response.internalServerError(body: 'Failed to get group for division');
    }

    final group = groupRes.unwrap();
    if(group == null) {
      return Response.notFound('Group not found');
    }

    final ratingRes = await ratingContext.lookupRating(group, playerId, allPossibleMemberNumbers: true);
    if(ratingRes.isErr()) {
      return Response.internalServerError(body: 'Failed to lookup rating');
    }

    final rating = ratingRes.unwrap();
    if(rating == null) {
      return Response.notFound('Rating not found');
    }

    final matchIds = <String>{};
    final matchesByMonth = <TempDate, List<ShootingMatch>>{};
    for(final event in rating.events) {
      final dbMatch = event.match.value;
      if(dbMatch == null) {
        continue;
      }
      if(matchIds.contains(dbMatch.sourceIds.first)) {
        continue;
      }
      matchIds.add(dbMatch.sourceIds.first);
      final matchRes = HydratedMatchCache().get(dbMatch);
      if(matchRes.isErr()) {
        return Response.internalServerError(body: 'Failed to get match');
      }
      final match = matchRes.unwrap();
      final year = match.date.year;
      final month = match.date.month;
      matchesByMonth[TempDate(year, month)] ??= [];
      matchesByMonth[TempDate(year, month)]!.add(match);
    }

    final scoresByMonth = <TempDate, List<FantasyScoreContainer>>{};
    const calculator = USPSAFantasyScoringCalculator();

    for(final date in matchesByMonth.keys) {
      final matches = matchesByMonth[date]!;
      for(final match in matches) {
        final scores = calculator.calculateFantasyScores(stats: calculator.calculateFantasyStats(match), pointsAvailable: FantasyScoringCategory.defaultCategoryPoints);
        final entry = match.shooters.firstWhereOrNull((shooter) => rating.allPossibleMemberNumbers.intersects(shooter.allPossibleMemberNumbers));
        if(entry == null) {
          continue;
        }
        scoresByMonth[date] ??= [];
        scoresByMonth[date]!.add(FantasyScoreContainer(match.name, match.date, scores[entry]!));
      }
    }

    final bestScoreByMonth = <TempDate, FantasyScoreContainer>{};
    for(final date in scoresByMonth.keys) {
      final scores = scoresByMonth[date]!;
      final bestScore = scores.reduce((a, b) => a.points > b.points ? a : b);
      bestScoreByMonth[date] = bestScore;
    }

    return Response.ok(bestScoreByMonth.toJson());
  }
}

extension _ScoringToJson on Map<TempDate, FantasyScoreContainer> {
  Map<String, dynamic> toJson() {
    return map((key, value) => MapEntry(key.toJson(), value.toJson()));
  }
}

class FantasyScoreContainer {
  final String matchName;
  final DateTime matchDate;
  final FantasyScore score;

  double get points => score.points;

  FantasyScoreContainer(this.matchName, this.matchDate, this.score);

  Map<String, dynamic> toJson() {
    return {
      "matchName": matchName,
      "matchDate": matchDate.toIso8601String(),
      "points": points,
      "details": score.categoryScores.map((key, value) => MapEntry(key.toString(), value)),
    };
  }
}

class TempDate {

  const TempDate(this.year, this.month);
  final int year;
  final int month;

  @override
  String toString() {
    return "$year-$month";
  }

  String toJson() {
    return "$year-$month";
  }

  @override
  int get hashCode => year.hashCode ^ month.hashCode;

  @override
  bool operator ==(Object other) {
    if(other is TempDate) {
      return year == other.year && month == other.month;
    }
    return false;
  }
}
