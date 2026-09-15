/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/career_stats.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/util.dart';

/// Maximum number of competitors in a rating comparison.
const int maxComparisonCompetitors = 3;

class RatingComparisonModel extends ChangeNotifier {
  final List<ShooterRating> _ratings = [];
  final List<CareerStats?> _careerStats = [];

  RatingComparisonModel({required List<ShooterRating> ratings}) {
    if(ratings.length < 2 || ratings.length > maxComparisonCompetitors) {
      throw ArgumentError("Comparison requires 2–$maxComparisonCompetitors ratings");
    }
    final sport = ratings.first.sport;
    for(var rating in ratings) {
      if(rating.sport != sport) {
        throw ArgumentError("Ratings must be for the same sport");
      }
    }
    _ratings.addAll(ratings);
    _careerStats.addAll(List.filled(ratings.length, null));
    _init();
  }

  /// Convenience constructor for the common two-person case.
  factory RatingComparisonModel.pair({
    required ShooterRating rating1,
    required ShooterRating rating2,
  }) {
    return RatingComparisonModel(ratings: [rating1, rating2]);
  }

  bool get ready => _careerStats.every((s) => s != null);

  int get competitorCount => _ratings.length;
  bool get canAddCompetitor => _ratings.length < maxComparisonCompetitors;
  bool get canRemoveCompetitor => _ratings.length > 2;

  List<ShooterRating> get ratings => List.unmodifiable(_ratings);

  ShooterRating get rating1 => _ratings[0];
  ShooterRating get rating2 => _ratings[1];
  ShooterRating? get rating3 => _ratings.length > 2 ? _ratings[2] : null;

  CareerStats careerStatsAt(int index) => _careerStats[index]!;
  CareerStats get careerStats1 => careerStatsAt(0);
  CareerStats get careerStats2 => careerStatsAt(1);
  CareerStats? get careerStats3 => _ratings.length > 2 ? careerStatsAt(2) : null;

  PeriodicStats? displayedStatsAt(int index) => _careerStats[index]!.statsForYear(year);
  PeriodicStats? get displayedStats1 => displayedStatsAt(0);
  PeriodicStats? get displayedStats2 => displayedStatsAt(1);
  PeriodicStats? get displayedStats3 => _ratings.length > 2 ? displayedStatsAt(2) : null;

  Map<String, SharedMatchHistory> _sharedMatchResults = {};
  Map<String, SharedMatchHistory> get sharedMatchResults => _sharedMatchResults;

  /// Matches where every competitor in the comparison has a result.
  Map<String, SharedMatchHistory> get matchesWithAllResults => _sharedMatchResults.values
    .where((e) => e.hasAllResults)
    .map((e) => MapEntry(e.matchId, e))
    .toMap();

  /// Matches where at least two competitors have a result.
  Map<String, SharedMatchHistory> get matchesWithAnyOverlap => _sharedMatchResults.values
    .where((e) => e.hasAnyOverlap)
    .map((e) => MapEntry(e.matchId, e))
    .toMap();

  bool _showOnlyMatchesWithAllResults = false;
  bool get showOnlyMatchesWithAllResults => _showOnlyMatchesWithAllResults;
  set showOnlyMatchesWithAllResults(bool value) {
    _showOnlyMatchesWithAllResults = value;
    notifyListeners();
  }

  /// The year to display. 0 for career.
  int year = 0;

  String? _highlightedMatchId;
  String? get highlightedMatchId => _highlightedMatchId;
  set highlightedMatchId(String? value) {
    if(_highlightedMatchId == value) {
      return;
    }
    _highlightedMatchId = value;
    notifyListeners();
  }

  String get title {
    return _ratings.map((r) => r.name).join(" vs. ");
  }

  void _init() {
    for(int i = 0; i < _ratings.length; i++) {
      if(_careerStats[i] == null) {
        _careerStats[i] = CareerStats(_ratings[i].sport, _ratings[i]);
      }
    }
    _rebuildSharedMatchResults();
    notifyListeners();
  }

  void _rebuildSharedMatchResults() {
    _sharedMatchResults = {};
    final count = _ratings.length;

    for(int i = 0; i < count; i++) {
      final career = _careerStats[i]!;
      for(var match in career.annualStats.map((e) => e.matchHistory).flattened) {
        final matchId = match.match.sourceIds.first;
        _sharedMatchResults[matchId] ??= SharedMatchHistory(
          matchId: matchId,
          competitorCount: count,
        );
        _sharedMatchResults[matchId]!.entries[i] = match;
      }
    }
  }

  /// Add a third competitor. No-op if already at max.
  void addCompetitor(ShooterRating rating) {
    if(!canAddCompetitor) return;
    if(rating.sport != _ratings.first.sport) {
      throw ArgumentError("Ratings must be for the same sport");
    }
    if(_ratings.any((r) => identical(r, rating) || r.wrappedRating.id == rating.wrappedRating.id)) {
      return;
    }

    _ratings.add(rating);
    _careerStats.add(CareerStats(rating.sport, rating));
    _rebuildSharedMatchResults();
    notifyListeners();
  }

  /// Remove the competitor at [index]. No-op if only two remain or index is invalid.
  void removeCompetitorAt(int index) {
    if(!canRemoveCompetitor) return;
    if(index < 0 || index >= _ratings.length) return;

    _ratings.removeAt(index);
    _careerStats.removeAt(index);
    _rebuildSharedMatchResults();
    notifyListeners();
  }

  /// Pairwise head-to-head record between competitors [i] and [j].
  /// Returns (iWins, jWins) counting only matches both attended.
  (int, int) pairwiseRecord(int i, int j) {
    int iWins = 0;
    int jWins = 0;
    for(var shared in _sharedMatchResults.values) {
      final entryI = shared.entries[i];
      final entryJ = shared.entries[j];
      if(entryI == null || entryJ == null) continue;
      if(entryI.place < entryJ.place) {
        iWins++;
      }
      else if(entryJ.place < entryI.place) {
        jWins++;
      }
    }
    return (iWins, jWins);
  }

  /// Number of matches where every competitor attended.
  int get allCompetitorMatchCount => matchesWithAllResults.length;
}


class SharedMatchHistory {
  String matchId;
  late List<MatchHistoryEntry?> entries;

  SharedMatchHistory({
    required this.matchId,
    required int competitorCount,
    List<MatchHistoryEntry?>? entries,
  }) {
    this.entries = entries ?? List.filled(competitorCount, null);
  }

  bool get hasAllResults => entries.every((e) => e != null);

  bool get hasAnyOverlap {
    int present = 0;
    for(var e in entries) {
      if(e != null) present++;
      if(present >= 2) return true;
    }
    return false;
  }

  int get presentCount => entries.where((e) => e != null).length;

  ShootingMatch? get match {
    for(var e in entries) {
      if(e != null) return e.match;
    }
    return null;
  }

  /// Among present competitors, the index of the best (lowest) place, or null if none/tie across all.
  /// Returns the first index with the best place (ties: all sharing best place are "winners").
  Set<int> bestPlaceIndices() {
    int? bestPlace;
    final winners = <int>{};
    for(int i = 0; i < entries.length; i++) {
      final e = entries[i];
      if(e == null) continue;
      if(bestPlace == null || e.place < bestPlace) {
        bestPlace = e.place;
        winners
          ..clear()
          ..add(i);
      }
      else if(e.place == bestPlace) {
        winners.add(i);
      }
    }
    return winners;
  }
}
