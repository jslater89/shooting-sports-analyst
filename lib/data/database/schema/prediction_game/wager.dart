/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/db_entities.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/util.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/prediction.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/probability.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
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

  /// The rating group this wager references. In AlgorithmPrediction
  /// parlance, this is the scoring group, not the rating group: the
  /// legs' subjects/targets belong to the rating group (e.g. LO/CO), but may be
  /// scored against a narrower group contained here (e.g. CO only).
  @Name('ratingGroup')
  final scoringGroup = IsarLink<RatingGroup>();

  /// The game this wager is part of.
  final game = IsarLink<PredictionGame>();

  /// The user that made this wager.
  final user = IsarLink<PredictionGamePlayer>();

  /// The transaction that recorded the wager.
  final wagerTransaction = IsarLink<PredictionGameTransaction>();

  /// The transaction that recorded the payout, for a winning wager.
  final payoutTransaction = IsarLink<PredictionGameTransaction>();

  /// The transaction that recorded the refund, for a voided wager.
  final refundTransaction = IsarLink<PredictionGameTransaction>();

  @Index(type: IndexType.hashElements)
  /// The member numbers of the subjects of the wager.
  List<String> get subjectMemberNumbers => legs.map((leg) => leg.subjectMemberNumbers).flattenedToSet.toList();

  /// Whether this is a parlay.
  bool get isParlay => legs.length > 1;

  @ignore
  bool get isOpen => status.isOpen;
  @ignore
  bool get isResolved => status.isResolved;

  @ignore
  bool get hasResolutionInformation => legs.every((leg) => leg.resolutionInformation != null);

  bool resolutionInformationValid({required DateTime matchLastUpdated}) {
    if(!hasResolutionInformation) {
      return false;
    }
    return legs.every((leg) =>
      leg.resolutionInformation!.scoresTimestamp.isAtSameMomentAs(matchLastUpdated)
      || leg.resolutionInformation!.scoresTimestamp.isAfter(matchLastUpdated)
    );
  }

  /// If this is a parlay, the probability of the parlay.
  /// (If it's a single leg, the probability is in the prediction.)
  DbProbability? parlayProbability;

  /// The probability of the wager.
  @ignore
  DbProbability get wagerProbability => isParlay ? parlayProbability! : legs.first.probability;

  /// The date and time the wager was created.
  DateTime created = practicalShootingZeroDate;

  /// The amount of the wager.
  double amount;

  /// The maximum wager the player could make at the time this wager was placed. This is
  /// the lowest of the player's bankroll, the player's tier-specific maximum wager,
  /// and any time-based wager limits for distance from the match.
  double? maximumWager;

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
  double get moneylinePayout => payout(roundToMoneyline: true);

  /// Evaluate the legs of the wager against the given scores.
  ///
  /// Returns a map of the legs to their evaluation results.
  ///
  /// [mode] determines whether to use the actual or prediction set scores.
  ///
  /// [buildResolutionInformation] must have been called for the wager (or
  /// its legs individually) before calling this method.
  Map<DbPrediction, bool> evaluateLegs(WagerEvaluationMode mode) {
    Map<DbPrediction, bool> results = {};
    for(var leg in legs) {
      results[leg] = leg.evaluate(mode);
    }
    return results;
  }

  /// Build the resolution information for the wager's legs.
  Map<DbPrediction, ResolutionInformation> buildResolutionInformation({
    required AnalystDatabase db,
    required WagerScores scores,
    required DateTime scoresTimestamp,
  }) {
    Map<DbPrediction, ResolutionInformation> results = {};
    for(var leg in legs) {
      results[leg] = leg.buildResolutionInformation(
        db: db,
        scoresTimestamp: scoresTimestamp,
        actualScores: scores.scores,
        predictionSetScores: scores.predictionSetScores,
      );
    }
    return results;
  }

  void clearResolutionInformation() {
    for(var leg in legs) {
      leg.clearResolutionInformation();
    }
  }

  /// Get preexisting resolution information for the wager's legs.
  ///
  /// This will throw if any legs do not have resolution information.
  /// Check with [hasResolutionInformation] before calling this method.
  Map<DbPrediction, ResolutionInformation> getResolutionInformation() {
    Map<DbPrediction, ResolutionInformation> results = {};
    for(var leg in legs) {
      results[leg] = leg.resolutionInformation!;
    }
    return results;
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
  }) {
    created = DateTime.now();
  }

  factory DbWager.fromWager(Wager wager, RatingGroup scoringGroup) {
    var dbWager = DbWager(
      legs: [DbPrediction.fromWager(wager)],
      amount: wager.amount,
    );
    dbWager.scoringGroup.value = scoringGroup;
    return dbWager;
  }

  factory DbWager.fromParlay(Parlay parlay, {
    double? bestPossibleOdds,
    double? worstPossibleOdds,
    double? houseEdgePerLeg,
    double? parlayEdge,
    required RatingGroup scoringGroup,
  }) {
    var dbWager = DbWager(
      legs: parlay.legs.map((leg) => DbPrediction.fromWager(leg)).toList(),
      amount: parlay.amount,
    );
    dbWager.parlayProbability = DbProbability.fromParlay(
      parlay,
      bestPossibleOdds: bestPossibleOdds,
      worstPossibleOdds: worstPossibleOdds,
      parlayEdge: parlayEdge,
      houseEdgePerLeg: houseEdgePerLeg,
    );
    dbWager.scoringGroup.value = scoringGroup;
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
        dbProbability.rawDecimalOdds,
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
      ShooterRating target = project.wrapDbRatingSync(dbPrediction.target.getShooterRatingSync(db)!);
      ShooterRating? underdog;
      if(dbPrediction.underdog != null) {
        underdog = project.wrapDbRatingSync(dbPrediction.underdog!.getShooterRatingSync(db)!);
      }
      var prediction = _hydratePrediction(dbPrediction, target, underdog);
      outLegs.add(Wager(
        prediction: prediction,
        probability: PredictionProbability.fromDecimalOdds(dbPrediction.probability.rawDecimalOdds),
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
  ///
  /// Always specificed in ratio form (0.0-1.0).
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

  /// The resolution information for the prediction.
  ResolutionInformation? resolutionInformation;

  /// The member numbers of the subjects of the prediction.
  List<String> get subjectMemberNumbers => [
    ...target.knownMemberNumbers,
    if(underdog != null) ...underdog!.knownMemberNumbers,
  ];

  void clearResolutionInformation() {
    resolutionInformation = null;
  }

  /// Build the resolution information for the prediction.
  ResolutionInformation buildResolutionInformation({
    required AnalystDatabase db,
    required DateTime scoresTimestamp,
    required Map<String, RelativeMatchScore> actualScores,
    required Map<String, RelativeMatchScore> predictionSetScores,
  }) {
    RelativeMatchScore? actualScore;
    RelativeMatchScore? predictionSetScore;
    RelativeMatchScore? actualUnderdogScore;
    RelativeMatchScore? predictionSetUnderdogScore;

    var targetPossibleMemberNumbers = target.getAllPossibleMemberNumbersSync(db);

    actualScore = actualScores[target.memberNumber];
    predictionSetScore = predictionSetScores[target.memberNumber];
    if(actualScore == null) {
      for(var n in targetPossibleMemberNumbers) {
        actualScore = actualScores[n];
        if(actualScore != null) {
          break;
        }
      }
    }
    if(predictionSetScore == null) {
      for(var n in targetPossibleMemberNumbers) {
        predictionSetScore = predictionSetScores[n];
        if(predictionSetScore != null) {
          break;
        }
      }
    }

    if(type.hasUnderdog) {
      var underdogPossibleMemberNumbers = underdog!.getAllPossibleMemberNumbersSync(db);
      actualUnderdogScore = actualScores[underdog!.memberNumber];
      predictionSetUnderdogScore = predictionSetScores[underdog!.memberNumber];
      if(actualUnderdogScore == null) {
        for(var n in underdogPossibleMemberNumbers) {
          actualUnderdogScore = actualScores[n];
          if(actualUnderdogScore != null) {
            break;
          }
        }
      }
      if(predictionSetUnderdogScore == null) {
        for(var n in underdogPossibleMemberNumbers) {
          predictionSetUnderdogScore = predictionSetScores[n];
          if(predictionSetUnderdogScore != null) {
            break;
          }
        }
      }
    }

    if(type.hasUnderdog) {
      this.resolutionInformation = ResolutionInformation.fromScores(
        scoresTimestamp: scoresTimestamp,
        actualScore: actualScore,
        predictionSetScore: predictionSetScore,
        actualUnderdogScore: actualUnderdogScore,
        predictionSetUnderdogScore: predictionSetUnderdogScore,
      );
      return this.resolutionInformation!;
    }
    else {
      this.resolutionInformation = ResolutionInformation.fromScore(
        scoresTimestamp: scoresTimestamp,
        actualScore: actualScore,
        predictionSetScore: predictionSetScore,
      );
      return this.resolutionInformation!;
    }
  }

  // TODO: replicate on hydrated wagers
  // and/or move to utility function so it's not duplicated
  /// Evaluate the prediction against the given type of score, retrieved from
  /// the resolution information.
  ///
  /// [buildResolutionInformation] must have been called for the prediction.
  /// [mode] determines whether to use the actual or prediction set scores.
  bool evaluate(WagerEvaluationMode mode) {
    if(resolutionInformation == null) {
      throw StateError("Resolution information not built for prediction: ${descriptiveString}");
    }

    // Misses if: target not in actual, or target not in predictions
    if(mode == WagerEvaluationMode.actualScores) {
      if(!resolutionInformation!.targetInActualScores) {
        return false;
      }
      if(type.hasUnderdog && !(resolutionInformation!.underdogInActualScores ?? false)) {
        return false;
      }
    }
    else if(mode == WagerEvaluationMode.predictionSetScores) {
      if(!resolutionInformation!.targetInSetScores) {
        return false;
      }
      if(type.hasUnderdog && !(resolutionInformation!.underdogInSetScores ?? false)) {
        return false;
      }
    }

    switch(type) {
      case DbPredictionType.place:
        var targetScore = mode == WagerEvaluationMode.actualScores ?
          resolutionInformation!.actualPlace :
          resolutionInformation!.predictionSetPlace;

        return targetScore >= bestPlace! && targetScore <= worstPlace!;
      case DbPredictionType.percentage:
        var targetScore = mode == WagerEvaluationMode.actualScores ?
          resolutionInformation!.actualRatio :
          resolutionInformation!.predictionSetRatio;
        if(abovePercentage) {
          return targetScore >= percentage!;
        }
        else {
          return targetScore <= percentage!;
        }
      case DbPredictionType.spread:
        var targetScore = mode == WagerEvaluationMode.actualScores ?
          resolutionInformation!.actualRatio :
          resolutionInformation!.predictionSetRatio;
        var underdogScore = mode == WagerEvaluationMode.actualScores ?
          resolutionInformation!.actualUnderdogRatio :
          resolutionInformation!.predictionSetUnderdogRatio;
        if(underdogScore == null) {
          return false;
        }
        var actualSpread = targetScore - underdogScore;
        if(favoriteCovers) {
          return actualSpread >= percentage!;
        }
        else {
          return actualSpread <= percentage!;
        }
      case DbPredictionType.invalid:
        throw ArgumentError("Invalid prediction type: ${type}");
    }
  }

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
          return "${target.name} -${percentage!.asPercentage(decimals: 2, includePercent: true)} vs. ${underdog!.name}";
        }
        else {
          return "${underdog!.name} +${percentage!.asPercentage(decimals: 2, includePercent: true)} vs. ${target.name}";
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
        dbPrediction.underdog = DbPredictionTarget.fromShooterRating(userPrediction.underdog);
      default:
        throw ArgumentError("Invalid prediction type: ${userPrediction.runtimeType}");
    }
    dbPrediction.probability = DbProbability.fromWager(wager);
    return dbPrediction;
  }

  factory DbPrediction.fromBayesianOddsWager({
    required double percentage,
    required bool abovePercentage,
    required DbPredictionTarget target,
  }) {
    var dbPrediction = DbPrediction();
    dbPrediction.type = DbPredictionType.percentage;
    dbPrediction.percentage = percentage;
    dbPrediction.abovePercentage = abovePercentage;
    dbPrediction.target = target;
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

  List<String> knownMemberNumbers;

  Set<String> getAllPossibleMemberNumbersSync( AnalystDatabase db) {
    var rating = getShooterRatingSync(db);
    if(rating == null) {
      return {};
    }
    return rating.allPossibleMemberNumbers;
  }

  Future<Set<String>> getAllPossibleMemberNumbers(AnalystDatabase db) async {
    var rating = await getShooterRating(db);
    if(rating == null) {
      return {};
    }
    return rating.allPossibleMemberNumbers;
  }

  DbPredictionTarget({
    this.projectId = -1,
    this.groupUuid = "",
    this.firstName = "",
    this.lastName = "",
    this.memberNumber = "",
    this.knownMemberNumbers = const [],
  });

  factory DbPredictionTarget.fromShooterRating(ShooterRating shooter) {
    return DbPredictionTarget(
      projectId: shooter.wrappedRating.project.value!.id,
      groupUuid: shooter.wrappedRating.group.value!.uuid,
      memberNumber: shooter.memberNumber,
      knownMemberNumbers: [...shooter.knownMemberNumbers],
      firstName: shooter.firstName,
      lastName: shooter.lastName,
    );
  }

  @ignore
  String get name {
    return "${firstName} ${lastName}";
  }

  bool isSameAs(DbPredictionTarget other) {
    if(this == other) {
      return true;
    }

    if(this.projectId != other.projectId) {
      return false;
    }
    if(this.groupUuid != other.groupUuid) {
      return false;
    }

    return this.memberNumber == other.memberNumber
      || this.knownMemberNumbers.intersects(other.knownMemberNumbers);
  }

  Future<bool> matchesShooter(AnalystDatabase db, Shooter shooter) async {
    var allPossibleMemberNumbers = await getAllPossibleMemberNumbers(db);

    return allPossibleMemberNumbers.intersects(shooter.allPossibleMemberNumbers);
  }

  bool matchesShooterSync(AnalystDatabase db, Shooter shooter) {
    var allPossibleMemberNumbers = getAllPossibleMemberNumbersSync(db);
    return allPossibleMemberNumbers.intersects(shooter.allPossibleMemberNumbers);
  }
}

@embedded
class DbProbability {
  double probability;
  double houseEdge;
  double? houseEdgePerLeg;
  double worstPossibleOdds;
  double bestPossibleOdds;
  List<DbDoubleKeyValue> info = [];

  DbProbability({
    this.probability = 0.0,
    this.houseEdge = 0.0,
    this.houseEdgePerLeg,
    this.worstPossibleOdds = PredictionProbability.worstPossibleOddsDefault,
    this.bestPossibleOdds = PredictionProbability.bestPossibleOddsDefault,
  });

  factory DbProbability.fromWager(Wager wager) {
    return DbProbability(
      probability: wager.probability.probability,
      houseEdge: wager.probability.houseEdge,
      houseEdgePerLeg: null,
      worstPossibleOdds: wager.probability.worstPossibleOdds,
      bestPossibleOdds: wager.probability.bestPossibleOdds,
    );
  }

  factory DbProbability.fromParlay(Parlay parlay, {
    double? bestPossibleOdds,
    double? worstPossibleOdds,
    double? parlayEdge,
    double? houseEdgePerLeg,
  }) {
    final probability = parlay.calculateProbabilityWith(
      houseEdgePerLeg: houseEdgePerLeg,
      parlayEdge: parlayEdge,
      bestPossibleOdds: bestPossibleOdds,
      worstPossibleOdds: worstPossibleOdds,
    );
    return DbProbability(
      probability: probability.probability,
      houseEdge: probability.houseEdge,
      houseEdgePerLeg: houseEdgePerLeg,
      worstPossibleOdds: probability.worstPossibleOdds,
      bestPossibleOdds: probability.bestPossibleOdds,
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

  bool get hasUnderdog => this == DbPredictionType.spread;
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
  bool get isOpen => this == pending;
}

/// Statistics etc. used to determine the resolution of a wager.
///
/// Contains both the actual and prediction set scores for the wager.
@embedded
class ResolutionInformation {
  /// Whether the target is in the actual scores.
  bool targetInActualScores;
  /// Whether the target is in the prediction set scores.
  bool targetInSetScores;
  /// The actual place of the target.
  int actualPlace;
  /// The place of the target in the prediction set scores.
  int predictionSetPlace;
  /// The actual ratio of the target.
  double actualRatio;
  /// The ratio of the target in the prediction set scores.
  double predictionSetRatio;

  /// Whether the underdog is in the actual scores.
  bool? underdogInActualScores;
  /// Whether the underdog is in the prediction set scores.
  bool? underdogInSetScores;
  /// The actual place of the underdog.
  int? actualUnderdogPlace;
  /// The place of the underdog in the prediction set scores.
  int? predictionSetUnderdogPlace;
  /// The actual ratio of the underdog.
  double? actualUnderdogRatio;
  /// The ratio of the underdog in the prediction set scores.
  double? predictionSetUnderdogRatio;

  /// The time of the scores.
  DateTime? dbScoresTimestamp;
  DateTime get scoresTimestamp => dbScoresTimestamp ?? practicalShootingZeroDate;
  set scoresTimestamp(DateTime value) {
    dbScoresTimestamp = value;
  }

  ResolutionInformation({
    this.actualPlace = -1,
    this.predictionSetPlace = -1,
    this.actualRatio = 0.0,
    this.predictionSetRatio = 0.0,
    this.actualUnderdogPlace,
    this.predictionSetUnderdogPlace,
    this.actualUnderdogRatio,
    this.predictionSetUnderdogRatio,
    this.targetInActualScores = false,
    this.targetInSetScores = false,
    this.underdogInActualScores = false,
    this.underdogInSetScores = false,
    this.dbScoresTimestamp,
  });

  ResolutionInformation.fromScore({
    required DateTime scoresTimestamp,
    required RelativeMatchScore? actualScore,
    required RelativeMatchScore? predictionSetScore,
  }) :
    dbScoresTimestamp = scoresTimestamp,
    actualPlace = actualScore?.place ?? -1,
    predictionSetPlace = predictionSetScore?.place ?? -1,
    actualRatio = actualScore?.ratio ?? 0.0,
    predictionSetRatio = predictionSetScore?.ratio ?? 0.0,
    targetInActualScores = actualScore != null,
    targetInSetScores = predictionSetScore != null;

  ResolutionInformation.fromScores({
    required DateTime scoresTimestamp,
    required RelativeMatchScore? actualScore,
    required RelativeMatchScore? predictionSetScore,
    required RelativeMatchScore? actualUnderdogScore,
    required RelativeMatchScore? predictionSetUnderdogScore,
  }) :
    dbScoresTimestamp = scoresTimestamp,
    actualPlace = actualScore?.place ?? -1,
    predictionSetPlace = predictionSetScore?.place ?? -1,
    actualRatio = actualScore?.ratio ?? 0.0,
    predictionSetRatio = predictionSetScore?.ratio ?? 0.0,
    actualUnderdogPlace = actualUnderdogScore?.place ?? -1,
    predictionSetUnderdogPlace = predictionSetUnderdogScore?.place ?? -1,
    actualUnderdogRatio = actualUnderdogScore?.ratio ?? 0.0,
    predictionSetUnderdogRatio = predictionSetUnderdogScore?.ratio ?? 0.0,
    targetInActualScores = actualScore != null,
    targetInSetScores = predictionSetScore != null,
    underdogInActualScores = actualUnderdogScore != null,
    underdogInSetScores = predictionSetUnderdogScore != null;
}

enum WagerEvaluationMode {
  actualScores,
  predictionSetScores;
}