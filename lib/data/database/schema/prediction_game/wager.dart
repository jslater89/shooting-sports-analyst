import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/db_entities.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_user.dart';
import 'package:shooting_sports_analyst/data/database/util.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';

part 'wager.g.dart';

/// A wager is a one-leg wager or multi-leg parlay.
@collection
class DbWager {
  Id id = Isar.autoIncrement;

  /// The prediction for the wager, or legs for a parlay.
  List<DbPrediction> legs;

  /// The match prep this wager is part of.
  final matchPrep = IsarLink<MatchPrep>();

  /// The game this wager is part of.
  final game = IsarLink<PredictionGame>();

  /// The user that made this wager.
  final user = IsarLink<PredictionGameUser>();

  /// The transaction that recorded the wager.
  final wagerTransaction = IsarLink<PredictionGameTransaction>();

  /// The transaction that recorded the payout.
  final payoutTransaction = IsarLink<PredictionGameTransaction>();

  /// Whether this is a parlay.
  bool get isParlay => legs.length > 1;

  /// If this is a parlay, the probability of the parlay.
  /// (If it's a single leg, the probability is in the prediction.)
  DbProbability? parlayProbability;

  /// The probability of the wager.
  @ignore
  DbProbability get wagerProbability => isParlay ? parlayProbability! : legs.first.probability;

  /// The amount of the wager.
  double amount;

  double payout({bool roundToMoneyline = true}) {
    if(!roundToMoneyline) {
      return amount * wagerProbability.decimalOdds;
    }
    else {
      var moneylineOddsDouble = double.parse(wagerProbability.moneylineOdds);
      if(moneylineOddsDouble > 0) {
        return amount + (amount * moneylineOddsDouble) / 100;
      }
      else {
        return amount + (amount * 100) / moneylineOddsDouble.abs();
      }
    }
  }

  @enumerated
  DbWagerStatus status = DbWagerStatus.pending;

  DbWager({
    required this.legs,
    required this.amount,
    this.parlayProbability,
  });
}

@embedded
class DbPrediction {
  @enumerated
  DbPredictionType type = DbPredictionType.percentage;
  DbProbability probability = DbProbability();

  /// If this is a percentage prediction, the percentage.
  /// If this is a spread prediction, the spread.
  double? percentage;

  /// If this is a place prediction, the place.
  int? place;

  /// The target of the prediction for place and percentage, or the favorite for a spread prediction.
  DbPredictionTarget target = DbPredictionTarget();

  /// The underdog for a spread prediction, or null otherwise.
  DbPredictionTarget? underdog;

  DbPrediction();
}

@embedded
class DbPredictionTarget with EmbeddedDbShooterRatingEntity {
  @override
  int projectId;
  @override
  String groupUuid;
  String firstName;
  String lastName;
  @override
  String memberNumber;

  DbPredictionTarget({
    this.projectId = -1,
    this.groupUuid = "",
    this.firstName = "",
    this.lastName = "",
    this.memberNumber = "",
  });
}

@embedded
class DbProbability {
  double probability;
  double houseEdge;
  double worstPossibleOdds;
  double bestPossibleOdds;
  List<DbDoubleKeyValue> info = [];

  DbProbability({
    this.probability = 0.0,
    this.houseEdge = 0.0,
    this.worstPossibleOdds = PredictionProbability.worstPossibleOddsDefault,
    this.bestPossibleOdds = PredictionProbability.bestPossibleOddsDefault,
  });

  @ignore
  /// Get the raw probability.
  double get rawProbability => probability;

  @ignore
  /// Get the probability adjusted for house edge.
  double get probabilityWithHouseEdge => probability / (1 - houseEdge);

  @ignore
  /// Get the raw decimal odds (before house edge).
  double get rawDecimalOdds => 1.0 / probability;

  @ignore
  /// Get the decimal odds (after house edge), clamped between worstPossibleOdds and bestPossibleOdds.
  double get decimalOdds => (1 / probabilityWithHouseEdge).clamp(worstPossibleOdds, bestPossibleOdds);

  @ignore
  /// Get the fractional odds as a string.
  String get fractionalOdds {
    var numerator = decimalOdds - 1.0;

    // Convert to fractional odds (e.g., 2.5 -> 3/2)
    // Find the simplest fraction representation
    var gcd = _gcd((numerator * 100).round(), 100);
    var num = (numerator * 100).round() ~/ gcd;
    var den = 100 ~/ gcd;

    return "$num/$den";
  }

  @ignore
  /// Get the moneyline odds as a string.
  String get moneylineOdds {
    if(decimalOdds == 2.0) {
      return "+100";
    }
    else if (decimalOdds > 2.0) {
      // Positive moneyline for underdogs
      var payout = (decimalOdds - 1.0) * 100;
      return "+${payout.round()}";
    } else {
      // Negative moneyline for favorites
      var stake = -100 / (decimalOdds - 1.0);
      return "${stake.round()}";
    }
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      var temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

}

enum DbPredictionType {
  /// An invalid prediction is one that has not yet had its data filled in.
  /// Predictions are invalid when created by the constructors; they can only
  /// be made valid by setting the various embedded fields.
  invalid,
  place,
  percentage,
  spread;
}

enum DbWagerStatus {
  /// The wagered event has not yet occurred.
  pending,
  /// The wager was won.
  won,
  /// The wager was lost.
  lost,
  /// The wager was voided and refunded.
  voided;
}