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

class RatingComparisonModel extends ChangeNotifier {
  ShooterRating _rating1;
  ShooterRating _rating2;

  RatingComparisonModel({required ShooterRating rating1, required ShooterRating rating2})
    : _rating1 = rating1,
      _rating2 = rating2 {
        if(rating1.sport != rating2.sport) {
          throw ArgumentError("Ratings must be for the same sport");
        }
        _init();
      }

  bool get ready => _careerStats1 != null && _careerStats2 != null;

  ShooterRating get rating1 => _rating1;
  ShooterRating get rating2 => _rating2;

  CareerStats? _careerStats1;
  CareerStats? _careerStats2;

  CareerStats get careerStats1 => _careerStats1!;
  CareerStats get careerStats2 => _careerStats2!;

  PeriodicStats? get displayedStats1 => _careerStats1!.statsForYear(year);
  PeriodicStats? get displayedStats2 => _careerStats2!.statsForYear(year);

  Map<String, PairedMatchHistory> _pairedMatchResults = {};
  Map<String, PairedMatchHistory> get pairedMatchResults => _pairedMatchResults;

  Map<String, PairedMatchHistory> get matchesWithBothResults => _pairedMatchResults.values
    .where((e) => e.hasBothResults)
    .map((e) => MapEntry(e.matchId, e))
    .toMap();

  bool _showOnlyMatchesWithBothResults = false;
  bool get showOnlyMatchesWithBothResults => _showOnlyMatchesWithBothResults;
  set showOnlyMatchesWithBothResults(bool value) {
    _showOnlyMatchesWithBothResults = value;
    notifyListeners();
  }

  /// The year to display. 0 for career.
  int year = 0;

  String? _highlightedMatchId;
  String? get highlightedMatchId => _highlightedMatchId;
  set highlightedMatchId(String? value) {
    _highlightedMatchId = value;
    notifyListeners();
  }

  void _init() {
    _careerStats1 = CareerStats(rating1.sport, rating1);
    _careerStats2 = CareerStats(rating2.sport, rating2);

    for(var match in careerStats1.annualStats.map((e) => e.matchHistory).flattened) {
      _pairedMatchResults[match.match.sourceIds.first] = PairedMatchHistory(
        matchId: match.match.sourceIds.first,
        match1: match,
      );
    }
    for(var match in careerStats2.annualStats.map((e) => e.matchHistory).flattened) {
      _pairedMatchResults[match.match.sourceIds.first] ??= PairedMatchHistory(
        matchId: match.match.sourceIds.first,
      );
      _pairedMatchResults[match.match.sourceIds.first]!.match2 = match;
    }

    notifyListeners();
  }

  void setRating1(ShooterRating rating) {
    _rating1 = rating;
    notifyListeners();
  }

  void setRating2(ShooterRating rating) {
    _rating2 = rating;
    notifyListeners();
  }
}


class PairedMatchHistory {
  String matchId;
  MatchHistoryEntry? match1;
  MatchHistoryEntry? match2;

  bool get hasBothResults => match1 != null && match2 != null;

  ShootingMatch? get match => match1?.match ?? match2?.match;

  PairedMatchHistory({
    required this.matchId,
    this.match1,
    this.match2,
  });
}