import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/db_entities.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/util.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'wager.g.dart';

/// A wager is a one-leg wager or multi-leg parlay.
@collection
class DbWager {
  Id id = Isar.autoIncrement;

  /// The prediction for the wager, or legs for a parlay.
  List<DbPrediction> legs;

  /// The match prep this wager is part of.
  final matchPrep = IsarLink<MatchPrep>();

  /// The prediction set this wager references.
  final predictionSet = IsarLink<PredictionSet>();

  /// The rating group this wager references.
  final ratingGroup = IsarLink<RatingGroup>();

  /// The game this wager is part of.
  final game = IsarLink<PredictionGame>();

  /// The user that made this wager.
  final user = IsarLink<PredictionGamePlayer>();

  /// The transaction that recorded the wager.
  final wagerTransaction = IsarLink<PredictionGameTransaction>();

  /// The transaction that recorded the payout, for a winning wager,
  /// or the refund transaction, for a voided wager.
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

  @ignore
  String get descriptiveString {
    if(isParlay) {
      return "${legs.length}-leg parlay";
    }
    else {
      return legs.first.descriptiveString;
    }
  }

  @enumerated
  DbWagerStatus status = DbWagerStatus.pending;

  DbWager({
    required this.legs,
    required this.amount,
    this.parlayProbability,
  });

  factory DbWager.fromWager(Wager wager) {
    var ratingGroup = wager.prediction.shooter.wrappedRating.group.value;
    var dbWager = DbWager(
      legs: [DbPrediction.fromWager(wager)],
      amount: wager.amount,
    );
    dbWager.ratingGroup.value = ratingGroup;
    return dbWager;
  }

  factory DbWager.fromParlay(Parlay parlay) {
    var ratingGroup = parlay.legs.first.prediction.shooter.wrappedRating.group.value;
    var dbWager = DbWager(
      legs: parlay.legs.map((leg) => DbPrediction.fromWager(leg)).toList(),
      amount: parlay.amount,
    );
    dbWager.parlayProbability = DbProbability.fromParlay(parlay);
    dbWager.ratingGroup.value = ratingGroup;
    return dbWager;
  }

  IWager hydrate() {
    final db = AnalystDatabase();
    final project = matchPrep.value!.ratingProject.value!;
    ShooterRating target = project.wrapDbRatingSync(legs.first.target.getShooterRatingSync(db)!);
    ShooterRating? underdog;
    if(legs.first.underdog != null) {
      underdog = project.wrapDbRatingSync(legs.first.underdog!.getShooterRatingSync(db)!);
    }
    if(isParlay) {
      return _hydrateParlay(db, project);
    }
    else {
      return _hydrateWager(db, project, target, underdog);
    }
  }

  Wager _hydrateWager(AnalystDatabase db, DbRatingProject project, ShooterRating target, ShooterRating? underdog) {
    var dbPrediction = legs.first;
    var dbProbability = dbPrediction.probability;

    UserPrediction prediction = _hydratePrediction(dbPrediction, target, underdog);

    return Wager(
      prediction: prediction,
      probability: PredictionProbability.fromDecimalOdds(
        dbProbability.decimalOdds,
        houseEdge: dbProbability.houseEdge,
        bestPossibleOdds: dbProbability.bestPossibleOdds,
        worstPossibleOdds: dbProbability.worstPossibleOdds,
      ),
      amount: amount,
    );
  }

  UserPrediction _hydratePrediction(DbPrediction dbPrediction, ShooterRating target, ShooterRating? underdog) {
    UserPrediction prediction;
    switch(dbPrediction.type) {
      case DbPredictionType.place:
        prediction = PlacePrediction(
          shooter: target,
          bestPlace: dbPrediction.bestPlace!,
          worstPlace: dbPrediction.worstPlace!);
      case DbPredictionType.percentage:
        prediction = PercentagePrediction(
          shooter: target,
          ratio: dbPrediction.percentage!,
          above: dbPrediction.abovePercentage,
        );
      case DbPredictionType.spread:
        prediction = PercentageSpreadPrediction(
          shooter: target,
          underdog: underdog!,
          ratioSpread: dbPrediction.percentage!,
          favoriteCovers: dbPrediction.favoriteCovers,
        );
      default:
        throw ArgumentError("Invalid prediction type: ${dbPrediction.type}");
    }
    return prediction;
  }

  Parlay _hydrateParlay(AnalystDatabase db, DbRatingProject project) {
    var outLegs = <Wager>[];
    for(var dbPrediction in legs) {
      ShooterRating target = project.wrapDbRatingSync(legs.first.target.getShooterRatingSync(db)!);
      ShooterRating? underdog;
      if(legs.first.underdog != null) {
        underdog = project.wrapDbRatingSync(legs.first.underdog!.getShooterRatingSync(db)!);
      }
      var prediction = _hydratePrediction(dbPrediction, target, underdog);
      outLegs.add(Wager(
        prediction: prediction,
        probability: PredictionProbability.fromDecimalOdds(dbPrediction.probability.decimalOdds),
        amount: amount,
      ));
    }

    return Parlay(
      legs: outLegs,
      amount: amount,
    );
  }
}

@embedded
class DbPrediction {
  @enumerated
  DbPredictionType type = DbPredictionType.percentage;
  DbProbability probability = DbProbability();

  /// If this is a percentage prediction, the percentage.
  /// If this is a spread prediction, the spread.
  double? percentage;

  /// If this is a percentage prediction, true if the percentage is above the target.
  /// If this is a spread prediction, true if the favorite covers the spread.
  bool abovePercentage = true;

  @ignore
  bool get favoriteCovers => abovePercentage;
  @ignore
  bool get underdogCovers => !abovePercentage;

  /// If this is a place prediction, the best place.
  int? bestPlace;

  /// If this is a place prediction, the worst place.
  int? worstPlace;

  /// The target of the prediction for place and percentage, or the favorite for a spread prediction.
  DbPredictionTarget target = DbPredictionTarget();

  /// The underdog for a spread prediction, or null otherwise.
  DbPredictionTarget? underdog;

  @ignore
  String get descriptiveString {
    switch(type) {
      case DbPredictionType.place:
        if(bestPlace == worstPlace) {
          return "${target.name} ${bestPlace?.ordinalPlace}";
        }
        else {
          return "${target.name} ${bestPlace?.ordinalPlace}-${worstPlace?.ordinalPlace}";
        }
      case DbPredictionType.percentage:
        return "${target.name} ${abovePercentage ? "≥" : "≤"} ${percentage!.asPercentage(decimals: 2, includePercent: true)}";
      case DbPredictionType.spread:
        if(favoriteCovers) {
          return "${target.name} covers -${percentage!.asPercentage(decimals: 2, includePercent: true)} vs. ${underdog!.name}";
        }
        else {
          return "${underdog!.name} covers +${percentage!.asPercentage(decimals: 2, includePercent: true)} vs. ${target.name}";
        }
      default:
        throw ArgumentError("Invalid prediction type: ${type}");
    }
  }

  DbPrediction();

  factory DbPrediction.fromWager(Wager wager) {
    var userPrediction = wager.prediction;
    var dbPrediction = DbPrediction();
    switch(userPrediction.runtimeType) {
      case PlacePrediction:
        userPrediction as PlacePrediction;
        dbPrediction.type = DbPredictionType.place;
        dbPrediction.bestPlace = userPrediction.bestPlace;
        dbPrediction.worstPlace = userPrediction.worstPlace;
        dbPrediction.target = DbPredictionTarget.fromShooterRating(userPrediction.shooter);
      case PercentagePrediction:
        userPrediction as PercentagePrediction;
        dbPrediction.type = DbPredictionType.percentage;
        dbPrediction.percentage = userPrediction.ratio;
        dbPrediction.abovePercentage = userPrediction.above;
        dbPrediction.target = DbPredictionTarget.fromShooterRating(userPrediction.shooter);
      case PercentageSpreadPrediction:
        userPrediction as PercentageSpreadPrediction;
        dbPrediction.type = DbPredictionType.spread;
        dbPrediction.percentage = userPrediction.ratioSpread;
        dbPrediction.abovePercentage = userPrediction.favoriteCovers;
        dbPrediction.target = DbPredictionTarget.fromShooterRating(userPrediction.shooter);
        dbPrediction.underdog = DbPredictionTarget.fromShooterRating(userPrediction.underdog!);
      default:
        throw ArgumentError("Invalid prediction type: ${userPrediction.runtimeType}");
    }
    dbPrediction.probability = DbProbability.fromWager(wager);
    return dbPrediction;
  }
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

  factory DbPredictionTarget.fromShooterRating(ShooterRating shooter) {
    return DbPredictionTarget(
      projectId: shooter.wrappedRating.project.value!.id,
      groupUuid: shooter.wrappedRating.group.value!.uuid,
      memberNumber: shooter.memberNumber,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
    );
  }

  @ignore
  String get name {
    return "${firstName} ${lastName}";
  }
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

  factory DbProbability.fromWager(Wager wager) {
    return DbProbability(
      probability: wager.probability.probability,
      houseEdge: wager.probability.houseEdge,
      worstPossibleOdds: wager.probability.worstPossibleOdds,
      bestPossibleOdds: wager.probability.bestPossibleOdds,
    );
  }

  factory DbProbability.fromParlay(Parlay parlay) {
    return DbProbability(
      probability: parlay.probability.probability,
      houseEdge: parlay.probability.houseEdge,
      worstPossibleOdds: parlay.probability.worstPossibleOdds,
      bestPossibleOdds: parlay.probability.bestPossibleOdds,
    );
  }

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

  /// Whether this wager is closed.
  bool get isResolved => this != pending;
}