/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/model.dart';

class RatingChange {
  final Map<String, double> change;

  // Arguments used as inputs to sprintf
  final Map<String, List<dynamic>> info;

  final Map<String, dynamic> extraData;

  RatingChange({required this.change, this.info = const {}, this.extraData = const {}});

  @override
  String toString() {
    return "$change";
  }
}

abstract class RatingEvent {
  String get eventName => "${match.name}" + (stage == null ? "" : " - ${stage!.name}");

  PracticalMatch match;
  Stage? stage;
  RelativeScore score;
  Map<String, List<dynamic>> info;
  Map<String, dynamic> extraData;

  double get ratingChange;
  double get oldRating;
  double get newRating => oldRating + ratingChange;

  RatingEvent({required this.match, this.stage, required this.score, this.info = const {}, this.extraData = const {}});

  void apply(RatingChange change);

  RatingEvent.copy(RatingEvent other) :
        this.match = other.match,
        this.stage = other.stage,
        this.score = other.score,
        this.info = {}..addAll(other.info),
        this.extraData = {}..addAll(other.extraData);
}
