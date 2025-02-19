/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

enum _IntKeys {
  exactOldMarbles,
  marblesStaked,
  marblesWon,
  matchStake,
  totalCompetitors,
  exactChange,
}
class MarbleRatingEvent extends RatingEvent {
  int get marblesStaked => wrappedEvent.intData[_IntKeys.marblesStaked.index];
  set marblesStaked(int v) => wrappedEvent.intData[_IntKeys.marblesStaked.index] = v;

  int get marblesWon => wrappedEvent.intData[_IntKeys.marblesWon.index];
  set marblesWon(int v) => wrappedEvent.intData[_IntKeys.marblesWon.index] = v;

  int get matchStake => wrappedEvent.intData[_IntKeys.matchStake.index];
  set matchStake(int v) => wrappedEvent.intData[_IntKeys.matchStake.index] = v;

  int get exactOldMarbles => wrappedEvent.intData[_IntKeys.exactOldMarbles.index];
  set exactOldMarbles(int v) => wrappedEvent.intData[_IntKeys.exactOldMarbles.index] = v;

  int get totalCompetitors => wrappedEvent.intData[_IntKeys.totalCompetitors.index];
  set totalCompetitors(int v) => wrappedEvent.intData[_IntKeys.totalCompetitors.index] = v;

  int get exactChange => wrappedEvent.intData[_IntKeys.exactChange.index];

  @override
  double get ratingChange => exactChange.toDouble();

  void _updateChange() {
    wrappedEvent.intData[_IntKeys.exactChange.index] = marblesWon - marblesStaked;
    wrappedEvent.ratingChange = exactChange.toDouble();
  }

  MarbleRatingEvent({
    required int initialMarbles,
    required int marblesStaked,
    required int marblesWon,
    required int matchStake,
    required int totalCompetitors,
    required ShootingMatch match,
    MatchStage? stage,
    required RelativeScore score,
    required RelativeScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
  }) : super(wrappedEvent: DbRatingEvent(
    ratingChange: (marblesWon - marblesStaked).toDouble(),
    oldRating: initialMarbles.toDouble(),
    matchId: match.sourceIds.first,
    stageNumber: stage?.stageId ?? -1,
    score: DbRelativeScore.fromHydrated(score),
    matchScore: DbRelativeScore.fromHydrated(matchScore),
    entryId: score.shooter.entryId,
    date: match.date,
    intDataElements: _IntKeys.values.length,
    doubleDataElements: 0,
    infoLines: infoLines,
    infoData: infoData,
  )) {
    this.exactOldMarbles = initialMarbles;
    this.marblesStaked = marblesStaked;
    this.marblesWon = marblesWon;
    this.matchStake = matchStake;
    this.totalCompetitors = totalCompetitors;
  }
  
  @override
  void apply(RatingChange change) {
    marblesWon += change.change[MarbleRater.marblesWonKey]!.round();
    marblesStaked += change.change[MarbleRater.marblesStakedKey]!.round();
    matchStake += change.change[MarbleRater.matchStakeKey]!.round();
    totalCompetitors += change.change[MarbleRater.totalCompetitorsKey]!.round();

    _updateChange();
    extraData = change.extraData;
    infoLines = change.infoLines;
    infoData = change.infoData;
  }

  MarbleRatingEvent.copy(MarbleRatingEvent other) :
    super.copy(other) {
    this.exactOldMarbles = other.exactOldMarbles;
    this.marblesStaked = other.marblesStaked;
    this.marblesWon = other.marblesWon;
    this.matchStake = other.matchStake;
    this.totalCompetitors = other.totalCompetitors;
  }

  MarbleRatingEvent.wrap(DbRatingEvent e) :
    super(wrappedEvent: e);
}