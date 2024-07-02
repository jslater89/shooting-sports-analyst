/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';

class OpenskillRatingEvent extends RatingEvent {
  double muChange;
  double sigmaChange;

  double initialMu;

  double get oldRating => initialMu;
  double get ratingChange => muChange;

  OpenskillRatingEvent({
    required this.initialMu,
    required this.muChange,
    required this.sigmaChange,
    required PracticalMatch match,
    Stage? stage,
    required RelativeScore score,
    Map<String, List<dynamic>> info = const {}
  }) : super(
    match: match,
    stage: stage,
    score: score,
    info: info,
  );

  @override
  void apply(RatingChange change) {
    muChange += change.change[OpenskillRater.muKey]!;
    sigmaChange += change.change[OpenskillRater.sigmaKey]!;
  }

  OpenskillRatingEvent.copy(OpenskillRatingEvent other) :
      this.initialMu = other.initialMu,
      this.muChange = other.muChange,
      this.sigmaChange = other.sigmaChange,
      super.copy(other);
}