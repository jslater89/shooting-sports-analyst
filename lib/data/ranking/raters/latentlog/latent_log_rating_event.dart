
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
  oldVolatility,
  varianceChange,
  volatilityChange,
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
    required double oldVolatility,
    required double varianceChange,
    required double volatilityChange,
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
    this.oldVolatility = oldVolatility;
    this.varianceChange = varianceChange;
    this.volatilityChange = volatilityChange;
    wrappedEvent.setMatchId(match.sourceIds.first, load: false);
  }

  double get oldVariance => wrappedEvent.doubleData[_DoubleKeys.oldVariance.index];
  set oldVariance(double v) => wrappedEvent.doubleData[_DoubleKeys.oldVariance.index] = v;

  double get oldVolatility => wrappedEvent.doubleData[_DoubleKeys.oldVolatility.index];
  set oldVolatility(double v) => wrappedEvent.doubleData[_DoubleKeys.oldVolatility.index] = v;

  double get varianceChange => wrappedEvent.doubleData[_DoubleKeys.varianceChange.index];
  set varianceChange(double v) => wrappedEvent.doubleData[_DoubleKeys.varianceChange.index] = v;

  double get volatilityChange => wrappedEvent.doubleData[_DoubleKeys.volatilityChange.index];
  set volatilityChange(double v) => wrappedEvent.doubleData[_DoubleKeys.volatilityChange.index] = v;

  LatentLogSettings settings;

  double get newRating => oldRating + ratingChange;
  double get newVariance => oldVariance + varianceChange;
  double get newVolatility => oldVolatility + volatilityChange;

  double get oldDisplayRating => oldRating * settings.scaleFactor + settings.scaleOffset;
  double get newDisplayRating => newRating * settings.scaleFactor + settings.scaleOffset;

  double get oldDisplayVariance => oldVariance * settings.scaleFactor;
  double get newDisplayVariance => newVariance * settings.scaleFactor;

  double get oldDisplayVolatility => oldVolatility * settings.scaleFactor;
  double get newDisplayVolatility => newVolatility * settings.scaleFactor;

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
    oldVolatility = change.change[LatentLogRater.oldVolatilityKey]!;
    varianceChange = change.change[LatentLogRater.varianceChangeKey]!;
    volatilityChange = change.change[LatentLogRater.volatilityChangeKey]!;
    stages = change.change[LatentLogRater.stagesKey]!.round();

    // Base class keys — [RatingSystem.ratingKey] is the new absolute internal rating.
    ratingChange = change.change[RatingSystem.ratingChangeKey]!;
    extraData = change.extraData;
    infoLines = change.infoLines;
    infoData = change.infoData;
  }

}