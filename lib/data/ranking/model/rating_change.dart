/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

class RatingChange {
  final Map<String, double> change;

  /// Arguments used as inputs to sprintf
  final Map<String, List<dynamic>> info;

  /// Other data that can't be represented as an int or double
  final Map<String, dynamic> extraData;

  RatingChange({required this.change, this.info = const {}, this.extraData = const {}});

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

  Map<String, List<dynamic>> get info => wrappedEvent.info;
  set info(Map<String, List<dynamic>> v) => wrappedEvent.info = v;
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

  bool get byStage => wrappedEvent.stageNumber >= 0;

  // TODO: calculate/cache
  // will probably need byStage in here too
  late RelativeScore score;
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
        this.score = other.score;
}
