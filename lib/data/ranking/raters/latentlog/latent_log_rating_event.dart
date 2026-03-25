
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_relative_score.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/latentlog/latent_log_settings.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

enum _IntKeys {
  stages,
}

enum _DoubleKeys {
  oldVariance,
  oldDispersion,
  varianceChange,
  dispersionChange,
}

class LatentLogRatingEvent extends RatingEvent {
  @override
  LatentLogRatingEvent({
    required this.settings,
    required ShootingMatch match,
    MatchStage? stage,
    required RelativeScore score,
    required RelativeScore matchScore,
    List<String> infoLines = const [],
    List<RatingEventInfoElement> infoData = const [],
    required double ratingChange,
    required double oldRating,
    required double oldVariance,
    required double oldDispersion,
    required double varianceChange,
    required double dispersionChange,
  }) : super(wrappedEvent: DbRatingEvent(
    ratingChange: ratingChange,
    oldRating: oldRating,
    matchId: match.sourceIds.first,
    stageNumber: stage?.stageId ?? -1,
    score: DbRelativeScore.fromHydrated(score),
    matchScore: DbRelativeScore.fromHydrated(matchScore),
    entryId: score.shooter.entryId,
    date: match.date,
    intDataElements: _IntKeys.values.length,
    doubleDataElements: _DoubleKeys.values.length,
    infoLines: infoLines,
    infoData: infoData,
  )) {
    this.oldRating = oldRating;
    this.oldVariance = oldVariance;
    this.oldDispersion = oldDispersion;
    this.varianceChange = varianceChange;
    this.dispersionChange = dispersionChange;
    wrappedEvent.setMatchId(match.sourceIds.first, load: false);
  }

  double get oldVariance => wrappedEvent.doubleData[_DoubleKeys.oldVariance.index];
  set oldVariance(double v) => wrappedEvent.doubleData[_DoubleKeys.oldVariance.index] = v;

  double get oldDispersion => wrappedEvent.doubleData[_DoubleKeys.oldDispersion.index];
  set oldDispersion(double v) => wrappedEvent.doubleData[_DoubleKeys.oldDispersion.index] = v;

  double get varianceChange => wrappedEvent.doubleData[_DoubleKeys.varianceChange.index];
  set varianceChange(double v) => wrappedEvent.doubleData[_DoubleKeys.varianceChange.index] = v;

  double get dispersionChange => wrappedEvent.doubleData[_DoubleKeys.dispersionChange.index];
  set dispersionChange(double v) => wrappedEvent.doubleData[_DoubleKeys.dispersionChange.index] = v;

  LatentLogSettings settings;

  double get newRating => oldRating + ratingChange;
  double get newVariance => oldVariance + varianceChange;
  double get newDispersion => oldDispersion + dispersionChange;

  double get oldDisplayRating => oldRating * settings.scaleFactor + settings.scaleOffset;
  double get newDisplayRating => newRating * settings.scaleFactor + settings.scaleOffset;

  double get oldDisplayVariance => oldVariance * settings.scaleFactor;
  double get newDisplayVariance => newVariance * settings.scaleFactor;

  double get oldDisplayDispersion => oldDispersion * settings.scaleFactor;
  double get newDisplayDispersion => newDispersion * settings.scaleFactor;

  int get stages => wrappedEvent.intData[_IntKeys.stages.index];
  set stages(int v) => wrappedEvent.intData[_IntKeys.stages.index] = v;

  LatentLogRatingEvent.wrap(DbRatingEvent event, {required this.settings}) :
    super(wrappedEvent: event) {
    this.settings = settings;
  }

  @override
  void apply(RatingChange change) {
    // LatentLog-specific keys
    oldVariance = change.change[LatentLogRater.oldVarianceKey]!;
    oldDispersion = change.change[LatentLogRater.oldDispersionKey]!;
    varianceChange = change.change[LatentLogRater.varianceChangeKey]!;
    dispersionChange = change.change[LatentLogRater.dispersionChangeKey]!;
    stages = change.change[LatentLogRater.stagesKey]!.round();

    // Base class keys — [RatingSystem.ratingKey] is the new absolute internal rating.
    ratingChange = change.change[RatingSystem.ratingChangeKey]!;
    extraData = change.extraData;
    infoLines = change.infoLines;
    infoData = change.infoData;
  }

}