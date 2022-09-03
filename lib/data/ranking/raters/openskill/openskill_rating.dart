
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rating_change.dart';

class OpenskillRating extends ShooterRating<OpenskillRating> {
  @override
  double get rating => ordinal;

  double mu;
  double sigma;

  double get ordinal => mu - 2*sigma;

  @override
  List<RatingEvent> ratingEvents = [];

  OpenskillRating(Shooter shooter, this.mu, this.sigma, {DateTime? date}) :
      super(shooter, date: date);

  OpenskillRating.copy(OpenskillRating other) :
      this.mu = other.mu,
      this.sigma = other.sigma,
      this.ratingEvents = other.ratingEvents.map((e) => OpenskillRatingEvent.copy(e as OpenskillRatingEvent)).toList(),
      super.copy(other);

  @override
  void updateFromEvents(List<RatingEvent> events) {
    for(var event in events) {
      event as OpenskillRatingEvent;
      mu += event.muChange;
      sigma += event.sigmaChange;
    }
  }

  @override
  void updateTrends(List<RatingEvent> changes) {
    // TODO: implement updateTrends
  }

  @override
  void copyRatingFrom(OpenskillRating other) {
    super.copyRatingFrom(other);
    mu = other.mu;
    sigma = other.sigma;
  }

  @override
  String toString() {
    return "${shooter.getName(suffixes: false)} ${rating.round()} ($hashCode)";
  }
}