
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/db_rating_event.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rating_change.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/util.dart';

enum _IntKeys {
  marbles,
  trend3,
  trend30,
}

class MarbleRating extends ShooterRating<MarbleRatingEvent> {
  MarbleRating(MatchEntry shooter,
    {
      required int initialMarbles,
      required super.sport,
      required DateTime date,
    }
  ) : super(
    shooter, date: date, intDataElements: _IntKeys.values.length, doubleDataElements: 0
  ) {
    this.marbles = initialMarbles;
  }

  @override
  double get rating => marbles.toDouble();

  int get marbles => wrappedRating.intData[_IntKeys.marbles.index];
  set marbles(int v) => wrappedRating.intData[_IntKeys.marbles.index] = v;

  @override
  double get trend => wrappedRating.intData[_IntKeys.trend30.index].toDouble();
  set trend(double v) => wrappedRating.intData[_IntKeys.trend30.index] = v.round();

  double get trend3 => wrappedRating.intData[_IntKeys.trend3.index].toDouble();
  set trend3(double v) => wrappedRating.intData[_IntKeys.trend3.index] = v.round();

  int calculateStake(double ante) {
    return (marbles * ante).round();
  }

  int takeStake(double ante) {
    int stake = calculateStake(ante);
    marbles -= stake;
    return stake;
  }

  @override
  List<MarbleRatingEvent> get combinedRatingEvents => []..addAll(ratingEvents)..addAll(emptyRatingEvents);

  @override
  List<MarbleRatingEvent> get emptyRatingEvents => [];

  @override
  void updateFromEvents(List<RatingEvent> events) {
    super.updateFromEvents(events);
    for(var event in events) {
      event as MarbleRatingEvent;
      wrappedRating.newRatingEvents.add(event.wrappedEvent);

      marbles -= event.marblesStaked;
      marbles += event.marblesWon;
    }
  }

  @override
  void updateTrends(List<RatingEvent> changes) {
    var trendWindow = ShooterRating.baseTrendWindow;

    var meaningfulChanges = changes.where((e) => e.ratingChange != 0.0).toList();

    var newEventContribution = meaningfulChanges.length;
    var dbRequirement = trendWindow - newEventContribution;

    List<double> marbleValues = [];
    if(dbRequirement > 0) {
      marbleValues.addAll(
        // We want to get the rating prior to the event to correctly calculate the trend
        AnalystDatabase().getRatingEventRatingForSync(
          wrappedRating, 
          limit: dbRequirement,
          offset: 0,
          order: Order.descending,
          nonzeroChange: true,
          newRating: false,
        ).reversed
      );
    }

    marbleValues.addAll(meaningfulChanges.map((e) => e.newRating));

    if(marbleValues.isEmpty) {
      this.trend = rating - MarbleSettings.defaultStartingMarbles.toDouble();
      this.trend3 = rating - MarbleSettings.defaultStartingMarbles.toDouble();
      return;
    }

    double firstRating = marbleValues.getTailWindow(trendWindow).first;
    double firstRating3 = marbleValues.getTailWindow(3).first;
    if(marbleValues.length < trendWindow) {
      firstRating = MarbleSettings.defaultStartingMarbles.toDouble();
    }
    if(marbleValues.length < 3) {
      firstRating3 = MarbleSettings.defaultStartingMarbles.toDouble();
    }


    this.trend = rating - firstRating;
    this.trend3 = rating - firstRating3;
  }

  @override
  MarbleRatingEvent wrapEvent(DbRatingEvent e) {
    return MarbleRatingEvent.wrap(e);
  }

  MarbleRating.wrapDbRating(DbShooterRating rating) : super.wrapDbRating(rating);

  MarbleRating.copy(MarbleRating other) : super.copy(other) {
    this.replaceAllRatingEvents(other.ratingEvents.map((e) => MarbleRatingEvent.copy(e)).toList());
    this.marbles = other.marbles;
  }
}