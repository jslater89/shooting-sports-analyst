/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';

sealed class StageScoring {
  /// Provide a comparative value for a raw score, using this scoring system.
  num interpret(RawScore score);

  /// If true, better scores in this scoring system are higher numeric values,
  /// and lower scores are worse.
  ///
  /// The opposite is true when false.
  bool get highScoreBest;

  /// The opposite of [highScoreBest].
  bool get lowScoreBest => !highScoreBest;

  String get dbString => this.runtimeType.toString();

  /// Whether stages with this scoring system should be used in ratings.
  bool get countsInRatings => true;

  /// A label to use in the UI adjacent to a score value.
  String displayLabel(RawScore score) {
    switch(this) {
      case HitFactorScoring():
        return "Hit Factor";
      case TimePlusScoring():
        return "Time";
      case PointsScoring():
        return "Points";
      case IgnoredScoring():
        return "-";
      case TimePlusChronoScoring():
        return "Time";
    }
  }

  /// A displayable string interpreting this score.
  String displayString(RawScore score) {
    switch(this) {
      case HitFactorScoring():
        return "${interpret(score).toStringAsFixed(4)}HF";
      case TimePlusScoring():
        return "${interpret(score).toStringAsFixed(2)}s";
      case PointsScoring(allowDecimal: var allowDecimal):
        if(allowDecimal) {
          return "${interpret(score).toStringAsFixed(2)}pt";
        }
        else {
          return "${interpret(score).round()}pt";
        }
      case IgnoredScoring():
        return "-";
      case TimePlusChronoScoring():
        return "${interpret(score).toStringAsFixed(2)}s";
    }
  }

  /// Returns >0 if a is better than b, 0 if they are equal, and <0 is b is better than a.
  int compareScores(RawScore a, RawScore b) {
    var aInt = interpret(a);
    var bInt = interpret(b);
    if(highScoreBest) {
      if (aInt > bInt) return 1;
      if (aInt < bInt) return -1;
      return 0;
    }
    else {
      if (aInt < bInt) return 1;
      if (aInt > bInt) return -1;
      return 0;
    }
  }

  /// Returns true if a is better than b.
  bool firstScoreBetter(RawScore a, RawScore b) {
    return compareScores(a, b) > 0;
  }

  /// Returns the ratio of [score] to [comparedTo].
  ///
  /// If score is 95 and comparedTo is 100, this will return
  /// 0.95 for a highScoreBest scoring.
  double ratio(RawScore score, RawScore comparedTo) {
    var result = 0.0;

    // We may sometimes pass in a zero compared-to score,
    // and we don't want to NaN-poison future calculations.
    if(comparedTo.dnf) {
      return 0.0;
    }

    if(highScoreBest) {
      result = interpret(score) / interpret(comparedTo);
    }
    else {
      // In time-plus with time bonuses, subzero times are not
      // impossible. To calculate a meaningful ratio for them,
      // we need to normalize so that the dividend is greater than
      // zero.
      var dividend = interpret(comparedTo);
      var divisor = interpret(score);
      double adjustment = 0.0;
      if(dividend < 0) {
        adjustment = 0 - dividend + 1.0;
        dividend += adjustment;
        divisor += adjustment;
      }
      if(divisor == 0.0) {
        adjustment = 0.01;
        dividend += adjustment;
        divisor += adjustment;
      }
      result = dividend / divisor;
    }

    if(result.isNaN) {
      return 0.0;
    }
    else {
      return result;
    }
  }

  const StageScoring();

  static StageScoring fromDbString(String string) {
    if(string.startsWith(const HitFactorScoring().dbString)) return const HitFactorScoring();
    else if(string.startsWith(const TimePlusScoring().dbPrefix)) {
      var options = string.split("|");
      var rawZeroWithEventsIsNonDnf = false;
      if(options.length >= 2) {
        rawZeroWithEventsIsNonDnf = options[1] == "true";
      }
      return TimePlusScoring(rawZeroWithEventsIsNonDnf: rawZeroWithEventsIsNonDnf);
    }
    else if(string.startsWith(const PointsScoring(highScoreBest: true).dbPrefix)) {
      var options = string.split("|");
      var highScoreBest = options[1] == "true";

      var allowDecimal = false;
      if(options.length >= 3) {
        allowDecimal = options[2] == "true";
      }

      // If this gets any more gnarly, skip
      if(highScoreBest && allowDecimal) {
        return const PointsScoring(highScoreBest: true, allowDecimal: true);
      }
      else if(highScoreBest && !allowDecimal) {
        return const PointsScoring(highScoreBest: true, allowDecimal: false);
      }
      else if(!highScoreBest && allowDecimal) {
        return const PointsScoring(highScoreBest: false, allowDecimal: true);
      }
      else {
        return const PointsScoring(highScoreBest: false, allowDecimal: false);
      }
    }
    else if(string.startsWith(const TimePlusChronoScoring().dbString)) {
      return const TimePlusChronoScoring();
    }
    else {
      return const IgnoredScoring();
    }
  }
}

class HitFactorScoring extends StageScoring {
  num interpret(RawScore score) => score.hitFactor;
  bool get highScoreBest => true;

  const HitFactorScoring();
}

class TimePlusScoring extends StageScoring {
  num interpret(RawScore score) => score.finalTime;
  bool get highScoreBest => false;
  
  /// If true, a score with a zero raw time is not a DNF if it has
  /// target events.
  final bool rawZeroWithEventsIsNonDnf;

  String get dbPrefix => "${this.runtimeType.toString()}";
  String get dbString => "$dbPrefix|$rawZeroWithEventsIsNonDnf";

  const TimePlusScoring({this.rawZeroWithEventsIsNonDnf = false});
}

class PointsScoring extends StageScoring {
  num interpret(RawScore score) => score.points;
  final bool highScoreBest;
  final bool allowDecimal;

  String get dbPrefix => "${this.runtimeType.toString()}";
  String get dbString => "$dbPrefix|$highScoreBest|$allowDecimal";

  const PointsScoring({this.highScoreBest = true, this.allowDecimal = false});

  @override
  bool operator ==(Object other) {
    if(other is PointsScoring) {
      return highScoreBest == other.highScoreBest && allowDecimal == other.allowDecimal;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(highScoreBest, allowDecimal);
}

class IgnoredScoring extends StageScoring {
  num interpret(RawScore score) => 0;
  bool get highScoreBest => true;
  bool get countsInRatings => false;

  const IgnoredScoring();
}

/// In (at minimum) ICORE, stages with the 'chrono' scoring type have zero
/// time (and would thus appear as a DNF in [TimePlusScoring]), but are
/// not a DNF—chrono is either a 0.0 time, or a 360-second failure to
/// make chrono penalty.
///
/// This scoring type is used to represent that case, mainly by never counting
/// for a match/stage DNF.
/// 
/// Some ICORE matches (older templates?) use a normal stage template for
/// chrono, and use a 0.01 time for success, plus the penalty for failure,
/// which is handled correctly by [TimePlusScoring].
class TimePlusChronoScoring extends StageScoring {
  num interpret(RawScore score) => score.finalTime;
  bool get highScoreBest => false;
  bool get countsInRatings => false;

  const TimePlusChronoScoring();
}
