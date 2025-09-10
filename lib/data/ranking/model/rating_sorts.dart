/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rating.dart';

enum RatingSortMode {
  rating,
  classification,
  firstName,
  lastName,
  error,
  lastChange,
  trend,
  direction,
  stages,
  pointsPerMatch,
}

extension RatingSortModeNames on RatingSortMode {
  String get uiLabel {
    switch(this) {
      case RatingSortMode.rating:
        return "Rating";
      case RatingSortMode.classification:
        return "Class";
      case RatingSortMode.error:
        return "Error";
      case RatingSortMode.lastChange:
        return "Last ±";
      case RatingSortMode.trend:
        return "Trend";
      case RatingSortMode.stages:
        return "History";
      case RatingSortMode.firstName:
        return "First Name";
      case RatingSortMode.lastName:
        return "Last Name";
      case RatingSortMode.pointsPerMatch:
        return "Points/Match";
      case RatingSortMode.direction:
        return "Direction";
    }
  }
}

extension SortFunctions on RatingSortMode {
  Comparator<ShooterRating> comparator({DateTime? changeSince}) {
    switch(this) {
      case RatingSortMode.rating:
        return (a, b) => b.rating.compareTo(a.rating);
      case RatingSortMode.classification:
        return (a, b) {
          if(a.lastClassification != null && b.lastClassification != null && a.lastClassification != b.lastClassification) {
            return a.lastClassification!.index.compareTo(b.lastClassification!.index);
          }
          else {
            return b.rating.compareTo(a.rating);
          }
        };
      case RatingSortMode.error:
          return (a, b) {
            if(a is EloShooterRating && b is EloShooterRating) {
              double aError;
              double bError;

              if(MultiplayerPercentEloRater.doBackRating) {
                aError = a.backRatingError;
                bError = b.backRatingError;
              }
              else {
                aError = a.standardError;
                bError = b.standardError;
              }
              return aError.compareTo(bError);
            }
            else throw ArgumentError();
          };
      case RatingSortMode.lastChange:
        return (a, b) {
          if(a is EloShooterRating && b is EloShooterRating) {
            double aLastMatchChange = a.lastMatchChange;
            double bLastMatchChange = b.lastMatchChange;
            return bLastMatchChange.compareTo(aLastMatchChange);
          }
          throw ArgumentError();
        };
      case RatingSortMode.direction:
        return (a, b) {
          if(a is EloShooterRating && b is EloShooterRating) {
            double aLastMatchChange = a.direction;
            double bLastMatchChange = b.direction;

            return bLastMatchChange.compareTo(aLastMatchChange);
          }
          throw ArgumentError();
        };
      case RatingSortMode.trend:
        if(changeSince != null) {
          return (a, b) {
            double aChange = a.rating - a.ratingForDate(changeSince);
            double bChange = b.rating - b.ratingForDate(changeSince);
            return bChange.compareTo(aChange);
          };
        }
        else {
          return (a, b) {
            var aTrend = a.trend;
            var bTrend = b.trend;
            return bTrend.compareTo(aTrend);
          };
        }
      case RatingSortMode.stages:
        return (a, b) => b.length.compareTo(a.length);
      case RatingSortMode.firstName:
        return (a, b) => a.firstName.compareTo(b.firstName);
      case RatingSortMode.lastName:
        return (a, b) => a.lastName.compareTo(b.lastName);
      case RatingSortMode.pointsPerMatch:
        return (a, b) {
          if(a is PointsRating && b is PointsRating) {
            var aPpm = a.rating / a.usedEvents().length;
            var bPpm = b.rating / b.usedEvents().length;
            return bPpm.compareTo(aPpm);
          }
          else {
            return b.rating.compareTo(a.rating);
          }
        };
    }
  }
}
