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
      result = interpret(comparedTo) / interpret(score);
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
    else if(string.startsWith(const TimePlusScoring().dbString)) return TimePlusScoring();
    else if(string.startsWith(const PointsScoring(highScoreBest: true).dbString)) {
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
    else return const IgnoredScoring();
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

  const TimePlusScoring();
}

class PointsScoring extends StageScoring {
  num interpret(RawScore score) => score.points;
  final bool highScoreBest;
  final bool allowDecimal;

  String get dbString => "${this.runtimeType.toString()}|$highScoreBest|$allowDecimal";

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

  const IgnoredScoring();
}
