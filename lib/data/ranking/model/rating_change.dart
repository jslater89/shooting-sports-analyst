/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';

class RatingChange {
  final Map<String, double> change;

  /// A list of strings, each representing a line of extra information about this rating.
  /// 
  /// [infoData] should be used to embed dynamic information, to avoid string interpolation
  /// costs during rating math. A {{key}} in these strings enclosed in double curly braces
  /// will be replaced with the element having {{key}} in [infoData].
  List<String> infoLines;
  /// A list of info elements, each containing data that can be filled into infoLines.
  /// 
  /// [RatingEventInfoElement]s have a key property, and strings in infoLines can contain
  /// {{key}} strings; the {{key}} string will be replaced by the data contained by the
  /// relevant element in this list.
  List<RatingEventInfoElement> infoData;

  /// Other data that can't be represented as an int or double
  final Map<String, dynamic> extraData;

  RatingChange({required this.change, this.infoLines = const [], this.infoData = const [], this.extraData = const {}});

  @override
  String toString() {
    return "$change";
  }
}

abstract interface class IRatingEvent {
  double get ratingChange;
  double get oldRating;
  double get newRating;
}

abstract class RatingEvent implements IRatingEvent {
  String get eventName => "${match.name}" + (stage == null ? "" : " - ${stage!.name}");

  List<String> get infoLines => wrappedEvent.infoLines;
  List<RatingEventInfoElement> get infoData => wrappedEvent.infoData;
  set infoData(List<RatingEventInfoElement> v) => wrappedEvent.infoData = v;
  set infoLines(List<String> v) => wrappedEvent.infoLines = v;
  Map<String, dynamic> get extraData => wrappedEvent.extraData;
  set extraData(Map<String, dynamic> v) => wrappedEvent.extraData = v;
  DbRatingEvent wrappedEvent;

  // The following properties ([match] through [scoreForMatch]) are used for calculating
  // shooter stats in individual dialogs, and can be slow.

  ShootingMatch? _cachedMatch;
  ShootingMatch get match {
    if(_cachedMatch == null) {
      var res = HydratedMatchCache().getBySourceId(wrappedEvent.matchId);
      if(res.isOk()) {
        _cachedMatch = res.unwrap();
      }
    }
    if(_cachedMatch == null) {
      wrappedEvent.match.loadSync();
      var res = wrappedEvent.match.value!.hydrate(useCache: true);
      _cachedMatch = res.unwrap();
    }

    return _cachedMatch!;
  }
  set match(ShootingMatch v) {
    _cachedMatch = v;
    wrappedEvent.match.value = DbShootingMatch.from(v);
  }

  MatchStage? get stage {
    if(wrappedEvent.stageNumber < 0) return null;
    return match.stages.firstWhereOrNull((s) => s.stageId == wrappedEvent.stageNumber);
  }
  int get stageNumber => wrappedEvent.stageNumber;

  MatchEntry? _cachedEntry;
  MatchEntry get entry {
    if(_cachedEntry == null) {
      _cachedEntry = match.shooters.firstWhere((s) => s.entryId == wrappedEvent.entryId);
    }
    return _cachedEntry!;
  }

  bool get byStage => wrappedEvent.stageNumber >= 0;

  RelativeScore? _cachedScore;
  RelativeScore get score {
    if(_cachedScore == null) {
      if(!wrappedEvent.owner.isLoaded) {
        wrappedEvent.owner.loadSync();
      }
      var owner = wrappedEvent.owner.value!;
      if(!owner.group.isLoaded) {
        owner.group.loadSync();
      }
      var filters = owner.group.value!.filters;
      var scores = match.getScoresFromFilters(filters);
      _cachedScore = scores[entry];
    }
    return _cachedScore!;
  }
  RelativeStageScore get scoreForStage {
    if(byStage) return score as RelativeStageScore;
    else throw StateError("attempted to get stage score for match event");
  }

  RelativeMatchScore get scoreForMatch {
    if(stage == null) return score as RelativeMatchScore;
    else throw StateError("attempted to get match score for stage event");
  }

  // End individual dialog/slow-okay stats

  double get ratingChange => wrappedEvent.ratingChange;
  set ratingChange(double v) => wrappedEvent.ratingChange = v;
  double get oldRating => wrappedEvent.oldRating;
  set oldRating(double v) => wrappedEvent.oldRating = v;

  double get newRating => oldRating + ratingChange;

  RatingEvent({
    required this.wrappedEvent,
  });

  void apply(RatingChange change);

  RatingEvent.copy(RatingEvent other) :
        this.wrappedEvent = other.wrappedEvent.copy(),
        this._cachedScore = other._cachedScore,
        this._cachedEntry = other._cachedEntry,
        this._cachedMatch = other._cachedMatch;
}
