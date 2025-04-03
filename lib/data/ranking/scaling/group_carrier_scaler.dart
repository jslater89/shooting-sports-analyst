
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/scaling/rating_scaler.dart';

/// GroupCarrierScaler scales ratings based on 'carriers': people who shoot different
/// divisions at similar levels.
///
/// It linearly scales ratings according to the pairs in [groupSourceRatings], where
/// groupSourceRatings[group] is the rating that should equal [targetRating].
class GroupCarrierScaler extends RatingScaler {
  final Map<RatingGroup, double> groupSourceRatings;
  final double targetRating;


  GroupCarrierScaler({super.info, required this.groupSourceRatings, this.targetRating = 2000});

  @override
  double scaleRating(double rating, {RatingGroup? group}) {
    var sourceRating = groupSourceRatings[group];
    if(sourceRating == null) {
      return rating;
    }

    var scaleFactor = targetRating / sourceRating;
    return scaleFactor * rating;
  }

  @override
  double scaleNumber(double number, {required double originalRating, RatingGroup? group}) {
    var sourceRating = groupSourceRatings[group];
    if(sourceRating == null) {
      return number;
    }

    var scaleFactor = targetRating / sourceRating;
    return scaleFactor * number;
  }

  @override
  RatingScaler copy() {
    return GroupCarrierScaler(info: info.copy(), groupSourceRatings: {...groupSourceRatings}, targetRating: targetRating);
  }

}
