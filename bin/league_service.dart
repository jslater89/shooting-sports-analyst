import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa_utils/uspsa_fantasy_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/util.dart';

class LeagueService {
  final database = AnalystDatabase();

  /// /league/<leagueId>/player/<playerId>/scoring
  ///
  /// Returns the best score for each month for the given player.

  Future<Response> getScoring(Request request, String leagueId, String playerId) async {
    final ratingContext = await database.getRatingProjectByName("L2s Main");
    if(ratingContext == null) {
      return Response.notFound({"error": "Rating project not found"});
    }

    final groupRes = await ratingContext.groupForDivision(uspsaRevolver);
    if(groupRes.isErr()) {
      return Response.internalServerError(body: {"error": "Failed to get group for division"});
    }

    final group = groupRes.unwrap();
    if(group == null) {
      return Response.notFound({"error": "Group not found"});
    }

    final ratingRes = await ratingContext.lookupRating(group, playerId, allPossibleMemberNumbers: true);
    if(ratingRes.isErr()) {
      return Response.internalServerError(body: {"error": "Failed to lookup rating"});
    }

    final rating = ratingRes.unwrap();
    if(rating == null) {
      return Response.notFound({"error": "Rating not found"});
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
        return Response.internalServerError(body: {"error": "Failed to get match"});
      }
      final match = matchRes.unwrap();
      final year = match.date.year;
      final month = match.date.month;
      matchesByMonth[TempDate(year, month)] ??= [];
      matchesByMonth[TempDate(year, month)]!.add(match);
    }

    final scoresByMonth = <TempDate, List<FantasyScore<dynamic>>>{};
    const calculator = USPSAFantasyScoringCalculator();

    for(final date in matchesByMonth.keys) {
      final matches = matchesByMonth[date]!;
      for(final match in matches) {
        final scores = calculator.calculateFantasyScores(match);
        final entry = match.shooters.firstWhereOrNull((shooter) => rating.allPossibleMemberNumbers.intersects(shooter.allPossibleMemberNumbers));
        if(entry == null) {
          continue;
        }
        scoresByMonth[date] ??= [];
        scoresByMonth[date]!.add(scores[entry]!);
      }
    }

    final bestScoreByMonth = <String, Map<String, dynamic>>{};
    for(final date in scoresByMonth.keys) {
      final scores = scoresByMonth[date]!;
      final bestScore = scores.reduce((a, b) => a.points > b.points ? a : b);
      bestScoreByMonth[date.toString()] = bestScore.toJson();
    }

    return Response.ok(jsonEncode(bestScoreByMonth));
  }

  RouterPlus get router => Router().plus
    ..get("/league/<leagueId>/player/<playerId>/scoring", getScoring);
}

class TempDate {

  const TempDate(this.year, this.month);
  final int year;
  final int month;

  @override
  String toString() {
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
