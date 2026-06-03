/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/cache/match/match_cache.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/prediction_game/audit_result.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/odds/wager.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("PredictionGameManager");

class PredictionGameManager {
  PredictionGameManager({required this.predictionGame});

  final db = AnalystDatabase();
  PredictionGame predictionGame;

  // ======================
  // Match prep management
  // ======================

  /// Add a match prep to the prediction game.
  Future<void> addMatchPrep(MatchPrep matchPrep) async {
    predictionGame.matchPreps.add(matchPrep);
    await db.savePredictionGame(predictionGame, saveLinks: true);
    await loadPredictionGame();
  }

  void addMatchPrepSync(MatchPrep matchPrep) {
    predictionGame.matchPreps.add(matchPrep);
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<void> removeMatchPrep(MatchPrep matchPrep) async {
    var wagers = await getWagers(matchPrep: matchPrep);
    for(var wager in wagers) {
      await removeWager(wager);
    }
    predictionGame.matchPreps.remove(matchPrep);
    await db.savePredictionGame(predictionGame, saveLinks: true);
    await loadPredictionGame();
  }

  void removeMatchPrepSync(MatchPrep matchPrep) {
    predictionGame.matchPreps.remove(matchPrep);
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<void> enableMatchPrep(MatchPrep matchPrep) async {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.remove(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    await db.savePredictionGame(predictionGame);
    await loadPredictionGame();
  }

  void enableMatchPrepSync(MatchPrep matchPrep) {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.remove(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<void> disableMatchPrep(MatchPrep matchPrep) async {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.add(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    await db.savePredictionGame(predictionGame);
    await loadPredictionGame();
  }

  void disableMatchPrepSync(MatchPrep matchPrep) {
    var matchPreps = predictionGame.disabledMatchPreps.toList();
    matchPreps.add(matchPrep.id);
    predictionGame.disabledMatchPreps = matchPreps;
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  Future<List<MatchPrep>> getMatchPreps({bool futureOnly = true, bool hasPredictionsOnly = true, bool enabledOnly = false, bool reloadGameIfNeeded = true}) async {
    List<int> disabledMatchPreps = [];
    if(enabledOnly) {
      disabledMatchPreps = predictionGame.disabledMatchPreps.toList();
      if(reloadGameIfNeeded) {
        var queryResult = await db.getDisabledMatchPreps(predictionGame);
        if(queryResult != null) {
          disabledMatchPreps = queryResult;
        }
      }
    }

    var dbPreps = await db.getMatchPreps(predictionGame, futureOnly: futureOnly, hasPredictionsOnly: hasPredictionsOnly);
    if(enabledOnly) {
      return dbPreps.where((prep) => !disabledMatchPreps.contains(prep.id)).toList();
    }
    return dbPreps;
  }

  List<MatchPrep> getMatchPrepsSync({bool futureOnly = true, bool hasPredictionsOnly = true, bool enabledOnly = false, bool reloadGameIfNeeded = true}) {
    List<int> disabledMatchPreps = [];
    if(enabledOnly) {
      disabledMatchPreps = predictionGame.disabledMatchPreps.toList();
      if(reloadGameIfNeeded) {
        disabledMatchPreps = db.getDisabledMatchPrepsSync(predictionGame) ?? [];
      }
    }
    var dbPreps = db.getMatchPrepsSync(predictionGame, futureOnly: futureOnly, hasPredictionsOnly: hasPredictionsOnly);
    if(enabledOnly) {
      return dbPreps.where((prep) => !disabledMatchPreps.contains(prep.id)).toList();
    }
    return dbPreps;
  }

  Map<PredictionSet, List<RatingGroup>> availableRatingGroups(MatchPrep prep) {
    return predictionGame.availableRatingGroups(prep);
  }

  /// Gets the given match prep by its ID.
  ///
  /// This method does not verify that the match prep is part of the prediction game.
  Future<MatchPrep?> getMatchPrepById(int id) async {
    return db.getMatchPrepById(id);
  }

  /// Gets the given match prep by its ID.
  ///
  /// This method does not verify that the match prep is part of the prediction game.
  MatchPrep? getMatchPrepByIdSync(int id) {
    return db.getMatchPrepByIdSync(id);
  }

  Future<DbAlgorithmPrediction?> getAlgorithmPredictionForRating({required ShooterRating rating, required MatchPrep matchPrep, required RatingGroup scoringContext, PredictionSet? predictionSet}) async {
    return db.getAlgorithmPredictionForRating(rating, matchPrep, scoringContext, predictionSet: predictionSet);
  }

  DbAlgorithmPrediction? getAlgorithmPredictionForRatingSync({required ShooterRating rating, required MatchPrep matchPrep, required RatingGroup scoringContext, PredictionSet? predictionSet}) {
    return db.getAlgorithmPredictionForRatingSync(rating, matchPrep, scoringContext, predictionSet: predictionSet);
  }

  Future<void> clearMatchPrepResolutionInformation(MatchPrep matchPrep) async {
    var wagers = await getWagers(matchPrep: matchPrep);
    for(var wager in wagers) {
      wager.clearResolutionInformation();
      await db.saveWager(wager, saveLinks: false, createWagerTransaction: false);
    }
    await loadPredictionGame();
  }

  // ======================
  // Leaderboard
  // ======================

  /// Get the leaderboard for the prediction game.
  Future<List<PredictionLeaderboardEntry>> getLeaderboard(
    LeaderboardSortMode sortMode, {
    bool preload = false,
    List<DbWager>? preloadedWagers,
    List<PredictionGameTransaction>? preloadedTransactions,
  }) async {
    if(preload) {
      if(preloadedWagers == null) {
        preloadedWagers = await getWagers();
      }
      if(preloadedTransactions == null) {
        preloadedTransactions = await getTransactions();
      }
    }
    return db.getLeaderboard(predictionGame, sortMode, preloadedWagers: preloadedWagers, preloadedTransactions: preloadedTransactions);
  }

  // ======================
  // Player management
  // ======================

  Future<PredictionGamePlayer> savePlayer(PredictionGamePlayer player, {List<PredictionGameTransaction>? newTransactions}) async {
    await db.savePredictionGamePlayer(player, newTransactions: newTransactions, saveLinks: true);
    await loadPredictionGame();
    return player;
  }

  PredictionGamePlayer savePlayerSync(PredictionGamePlayer player) {
    db.savePredictionGamePlayerSync(player);
    loadPredictionGameSync();
    return player;
  }

  Future<void> deletePlayer(PredictionGamePlayer player) async {
    await db.deletePredictionGamePlayer(player);
    await loadPredictionGame();
  }

  void deletePlayerSync(PredictionGamePlayer player) {
    db.deletePredictionGamePlayerSync(player);
    loadPredictionGameSync();
  }

  // ======================
  // Wager management
  // ======================

  /// Add a wager to the prediction game.
  ///
  /// If [player] is provided, the wager will be added to that player.
  /// If [limits] is provided, the wager will be checked against the limits. Player must be provided if limits are provided.
  Future<AddWagerResult> addWager(DbWager wager, {PredictionGamePlayer? player, PredictionGamePlayerLimits? limits}) async {
    double? maximumWager;
    if(player != null) {
      if(player.balance < wager.amount) {
        return Result.err(InsufficientFundsError());
      }
      maximumWager = player.balance;
    }
    if(limits != null) {
      if(limits.maxWager != null) {
        if(limits.maxWager! < wager.amount) {
          return Result.err(ExceededMaxWagerError());
        }
        maximumWager = min(maximumWager ?? double.infinity, limits.maxWager!);
      }

      var openWagers = player!.wagers.filter().statusEqualTo(DbWagerStatus.pending).countSync();
      if(limits.maxConcurrentWagers != null && limits.maxConcurrentWagers! < openWagers + 1) {
        return Result.err(ExceededMaxWagerCountError());
      }
    }

    wager.maximumWager = maximumWager;

    // It's already backlinked to everything else, so we can just save it
    // and its links.
    try {
      await db.saveWager(wager, saveLinks: true, createWagerTransaction: true);
    }
    catch(e) {
      _log.e("Error adding wager: $e");
      return Result.err(UnknownError());
    }
    await loadPredictionGame();
    return Result.ok(null);
  }

  /// Add a wager to the prediction game.
  ///
  /// If [player] is provided, the wager will be added to that player.
  /// If [limits] is provided, the wager will be checked against the limits. Player must be provided if limits are provided.
  AddWagerResult addWagerSync(DbWager wager, {PredictionGamePlayer? player, PredictionGamePlayerLimits? limits}) {
    double? maximumWager;
    if(player != null) {
      if(player.balance < wager.amount) {
        return Result.err(InsufficientFundsError());
      }
      maximumWager = player.balance;
    }
    if(limits != null) {
      if(limits.maxWager != null) {
        if(limits.maxWager! < wager.amount) {
          return Result.err(ExceededMaxWagerError());
        }
        maximumWager = min(maximumWager ?? double.infinity, limits.maxWager!);
      }

      var openWagers = player!.wagers.filter().statusEqualTo(DbWagerStatus.pending).countSync();
      if(limits.maxConcurrentWagers != null && limits.maxConcurrentWagers! < openWagers + 1) {
        return Result.err(ExceededMaxWagerCountError());
      }
    }

    wager.maximumWager = maximumWager;

    db.saveWagerSync(wager, createWagerTransaction: true);
    loadPredictionGameSync();
    return Result.ok(null);
  }


  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  Future<void> removeWager(DbWager wager) async {
    await db.deleteWager(wager);
    await loadPredictionGame();
  }

  /// Fully deletes a wager from the database, also deleting
  /// associated transactions.
  void removeWagerSync(DbWager wager) {
    db.deleteWagerSync(wager);
    db.savePredictionGameSync(predictionGame);
    loadPredictionGameSync();
  }

  /// Get the wagers from the prediction game with various filters.
  Future<List<DbWager>> getWagers({
    bool openOnly = false,
    DbShooterRating? subject,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    return db.getWagers(game: predictionGame, openOnly: openOnly, subject: subject, matchPrep: matchPrep, player: player);
  }

  /// Get the wagers from the prediction game with various filters.
  List<DbWager> getWagersSync({
    bool openOnly = false,
    DbShooterRating? subject,
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return db.getWagersSync(game: predictionGame, openOnly: openOnly, subject: subject, matchPrep: matchPrep, player: player);
  }

  // /// Process the wagers for a particular match prep.
  // Future<void> processWagersForMatch(MatchPrep matchPrep) async {
  //   var wagers = await getWagers(matchPrep: matchPrep);
  //   for(var wager in wagers) {
  //   }
  //   await db.savePredictionGame(predictionGame, saveLinks: true);
  //   await loadPredictionGame();
  // }

  // /// Process the wagers for a particular match prep.
  // void processWagersForMatchSync(MatchPrep matchPrep) {
  //   var wagers = predictionGame.wagers.where((wager) => wager.matchPrep.value!.id == matchPrep.id).toList();
  //   for(var wager in wagers) {
  //   }
  //   db.savePredictionGameSync(predictionGame);
  //   loadPredictionGameSync();
  // }

  /// Resolve a wager with the given status, creating a payout or refund transaction
  /// as necessary and updating the wager player's balance.
  Future<Result<DbWager, WagerResolutionError>> resolveWager(DbWager wager, DbWagerStatus status) async {
    if(wager.status.isResolved) {
      return Result.err(WagerResolutionError.alreadyResolved);
    }

    if(!wager.hasResolutionInformation && status != DbWagerStatus.voided) {
      return Result.err(WagerResolutionError.noResolutionInformation);
    }

    wager.status = status;

    double playerBalanceChange = 0;

    if(status == DbWagerStatus.won) {
      if(wager.payoutTransaction.value == null) {
        playerBalanceChange = wager.payout();
        var payoutTransaction = PredictionGameTransaction(
          type: PredictionGameTransactionType.payout,
          amount: playerBalanceChange,
          created: DateTime.now(),
        );
        payoutTransaction.game.value = wager.game.value;
        payoutTransaction.user.value = wager.user.value;
        payoutTransaction.wager.value = wager;

        var savedTxn = await db.savePredictionGameTransaction(payoutTransaction);
        wager.payoutTransaction.value = savedTxn;
      }
      else {
        _log.w("Wager ${wager.id} was already resolved as won, but is being resolved again");
      }
    }
    else if(status == DbWagerStatus.voided) {
      if(wager.refundTransaction.value == null) {
        playerBalanceChange = wager.amount;

        // If we're voiding a wager that was already paid out for some reason,
        // we need to refund the player the amount they were paid.
        if(wager.payoutTransaction.value != null) {
          playerBalanceChange -= wager.payoutTransaction.value!.amount;
        }
        var refundTransaction = PredictionGameTransaction(
          type: PredictionGameTransactionType.refund,
          amount: playerBalanceChange,
          created: DateTime.now(),
        );
        refundTransaction.game.value = wager.game.value;
        refundTransaction.user.value = wager.user.value;
        refundTransaction.wager.value = wager;

        var savedTxn = await db.savePredictionGameTransaction(refundTransaction);
        wager.refundTransaction.value = savedTxn;
      }
      else {
        _log.w("Wager ${wager.id} was already resolved as voided, but is being resolved again");
      }
    }

    if(playerBalanceChange != 0) {
      await db.updatePlayerBalance(wager.user.value!, playerBalanceChange);
    }
    await db.saveWager(wager, saveLinks: true, createWagerTransaction: false);
    await loadPredictionGame();
    return Result.ok(wager);
  }

  /// Resolve a wager with the given status, creating a payout or refund transaction
  /// as necessary and updating the wager player's balance.
  Result<DbWager, WagerResolutionError> resolveWagerSync(DbWager wager, DbWagerStatus status) {
    if(wager.status.isResolved) {
      return Result.err(WagerResolutionError.alreadyResolved);
    }

    if(!wager.hasResolutionInformation && status != DbWagerStatus.voided) {
      return Result.err(WagerResolutionError.noResolutionInformation);
    }

    wager.status = status;
    double playerBalanceChange = 0;
    if(status == DbWagerStatus.won) {
      playerBalanceChange = wager.payout();
      var payoutTransaction = PredictionGameTransaction(
        type: PredictionGameTransactionType.payout,
        amount: playerBalanceChange,
        created: DateTime.now(),
      );
      payoutTransaction.game.value = wager.game.value;
      payoutTransaction.user.value = wager.user.value;
      payoutTransaction.wager.value = wager;
      wager.payoutTransaction.value = payoutTransaction;
    }
    else if(status == DbWagerStatus.voided) {
      playerBalanceChange = wager.amount;
      var refundTransaction = PredictionGameTransaction(
        type: PredictionGameTransactionType.refund,
        amount: playerBalanceChange,
        created: DateTime.now(),
      );
      refundTransaction.game.value = wager.game.value;
      refundTransaction.user.value = wager.user.value;
      refundTransaction.wager.value = wager;
      wager.refundTransaction.value = refundTransaction;
    }

    if(playerBalanceChange != 0) {
      db.updatePlayerBalanceSync(wager.user.value!, playerBalanceChange);
    }
    db.saveWagerSync(wager, createWagerTransaction: false);
    loadPredictionGameSync();
    return Result.ok(wager);
  }

  // ======================
  // Transaction management
  // ======================

  /// Get the transactions from the prediction game with various filters.
  Future<List<PredictionGameTransaction>> getTransactions({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) async {
    return db.getTransactions(game: predictionGame, matchPrep: matchPrep, player: player);
  }

  /// Get the transactions from the prediction game with various filters.
  List<PredictionGameTransaction> getTransactionsSync({
    MatchPrep? matchPrep,
    PredictionGamePlayer? player,
  }) {
    return db.getTransactionsSync(game: predictionGame, matchPrep: matchPrep, player: player);
  }

  /// Get relevant scores for a list of given wagers: scores for all of
  /// the shooters in the wager's legs, for both the match result and the result within the
  /// relevant prediction set.
  ///
  /// Any matches provided in [matches] will be used to calculate scores. Other matches will be
  /// loaded from the database as needed.
  Future<Map<DbWager, WagerScores>> getAllRelevantScores(List<DbWager> wagers, {Map<DbWager, ShootingMatch>? matches}) async {
    /// First load all matches we need, if not provided.
    if(matches == null) {
      matches = {};
    }
    for(var wager in wagers) {
      var match = matches[wager];
      if(match == null) {
        var dbMatch = wager.matchPrep.value?.futureMatch.value?.dbMatch.value;
        if(dbMatch != null) {
          var matchRes = await MatchCache.instance.get(dbMatch);
          if(matchRes.isOk()) {
            match = matchRes.unwrap();
          }
        }
      }
    }

    // Get lists of data we're interested in: rating groups, prediction sets, and shooters.
    Map<ShootingMatch, Set<RatingGroup>> matchesToGroups = {};
    Map<ShootingMatch, Set<PredictionSet>> matchesToPredictionSets = {};
    Map<ShootingMatch, List<DbShooterRating>> matchesToWageredShooters = {};
    Map<String, List<String>> memberNumbersToAllPossibleMemberNumbers = {};
    for(var wager in wagers) {
      var match = matches[wager];
      if(match != null) {
        for(var leg in wager.legs) {
          var shooter = leg.target.getShooterRatingSync(db);
          var underdog = leg.underdog?.getShooterRatingSync(db);
          var shooters = [shooter, underdog].nonNulls.toList();
          for(var s in shooters) {
            var allPossibleMemberNumbers = [...s.allPossibleMemberNumbers];
            for(var n in allPossibleMemberNumbers) {
              memberNumbersToAllPossibleMemberNumbers[n] = allPossibleMemberNumbers;
            }
            matchesToWageredShooters.addToListIfMissingByEquality(match, s, (a, b) => a.equalsShooter(b, allPossibleMemberNumbers: true));
          }
        }

        // Rating groups and prediction sets both implement DB equality.
        // For groups, we want the scoring group, so we ask the wager directly.
        matchesToGroups.addToSet(match, wager.scoringGroup.value!);
        matchesToPredictionSets.addToSet(match, wager.predictionSet.value!);
      }
    }

    Set<PredictionSet> predictionSetsToProcess = matchesToPredictionSets.values.flattenedToSet;
    Map<PredictionSet, List<Shooter>> predictionSetShooters = {};
    for(var predictionSet in predictionSetsToProcess) {
      predictionSetShooters[predictionSet] = predictionSet.algorithmPredictions.map((p) {
        var shooter = p.asShooter(loadFromRating: false);
        var allPossibleMemberNumbers = memberNumbersToAllPossibleMemberNumbers[p.memberNumber] ?? [];
        shooter.allPossibleMemberNumbers.addAll(allPossibleMemberNumbers);
        return shooter;
      }).nonNulls.toList();
    }

    // Get the scores of interest.
    Set<ShootingMatch> matchesToProcess = matchesToGroups.keys.toSet();
    Map<ShootingMatch, Map<RatingGroup, Map<String, RelativeMatchScore>>> groupScores = {};
    Map<ShootingMatch, Map<RatingGroup, Map<PredictionSet, Map<String, RelativeMatchScore>>>> setScores = {};
    for(var match in matchesToProcess) {
      // For each match, we need to calculate scores for each rating group of interest, both
      // overall, and within each prediction set of interest.
      groupScores[match] = {};
      setScores[match] = {};
      for(var group in matchesToGroups[match]!) {
        var overallShooters = match.filterShooters(divisions: group.divisions);
        var overallScores = match.getScores(shooters: overallShooters);
        var filteredOverall = Map.fromEntries(
          overallScores.entries
            .where((element) => matchesToWageredShooters[match]!
              .any((s) => element.key.equalsShooter(s, allPossibleMemberNumbers: true))
            )
          );

        Map<String, RelativeMatchScore> overallByNumber = {};
        for(var entry in filteredOverall.entries) {
          for(var number in entry.key.allPossibleMemberNumbers) {
            overallByNumber[number] = entry.value;
          }
        }
        groupScores[match]![group] = overallByNumber;

        setScores[match]![group] = {};
        for(var predictionSet in matchesToPredictionSets[match]!) {
          var shootersInSet = predictionSetShooters[predictionSet]!;
          var filteredShooters = overallShooters.where((s) =>
            shootersInSet.any((p) => p.equalsShooter(s, allPossibleMemberNumbers: true))
          ).toList();

          var predictionSetScores = match.getScores(shooters: filteredShooters);
          var relevantScores = Map.fromEntries(
            predictionSetScores.entries
              .where((element) => matchesToWageredShooters[match]!
                .any((s) => element.key.equalsShooter(s, allPossibleMemberNumbers: true))
              )
            );

          Map<String, RelativeMatchScore> predictionSetByNumber = {};
          for(var entry in relevantScores.entries) {
            for(var number in entry.key.allPossibleMemberNumbers) {
              predictionSetByNumber[number] = entry.value;
            }
          }
          setScores[match]![group]![predictionSet] = predictionSetByNumber;
        }
      }
    }

    Map<DbWager, WagerScores> relevantScores = {};
    for(var wager in wagers) {
      var match = matches[wager];
      if(match != null) {
        var group = wager.scoringGroup.value!;
        var predictionSet = wager.predictionSet.value!;
        var scores = WagerScores(wager: wager);
        scores.scores = groupScores[match]![group]!;
        scores.predictionSetScores = setScores[match]![group]![predictionSet]!;
        relevantScores[wager] = scores;
      }
    }

    return relevantScores;
  }

  /// Get the relevant scores for a wager: scores for all of the shooters in the wager's legs,
  /// for both the match result and the result within the prediction set.
  ///
  /// If [match] is provided, it will be used to calculate the scores
  Future<WagerScores> getRelevantScores(DbWager wager, {ShootingMatch? match}) async {
    var scores = WagerScores(wager: wager);
    ShootingMatch? actualMatch;
    var dbMatch = wager.matchPrep.value?.futureMatch.value?.dbMatch.value;
    if(dbMatch == null) {
      return scores;
    }
    if(match == null) {
      var matchRes = await MatchCache.instance.get(dbMatch);
      if(matchRes.isOk()) {
        actualMatch = matchRes.unwrap();
      }
      else {
        _log.e("Error hydrating match: ${matchRes.unwrapErr().message}");
        return scores;
      }
    }
    else {
      actualMatch = match;
    }

    List<Shooter> shooters = [];
    for(var leg in wager.legs) {
      var shooter = leg.target.getShooterRatingSync(db);
      var underdog = leg.underdog?.getShooterRatingSync(db);
      if(shooter != null) {
        shooters.add(shooter);
      }
      if(underdog != null) {
        shooters.add(underdog);
      }
    }

    var group = wager.scoringGroup.value!;
    var predictionSet = wager.predictionSet.value;

    scores.scores = _getScoresForShooters(shooters, group, actualMatch, null);
    scores.predictionSetScores = _getScoresForShooters(shooters, group, actualMatch, predictionSet);

    return scores;

  }

  /// Audit the transactions for a player and update the balance if needed, returning
  /// the change in balance, or 0 if the balance was consistent.
  Future<PredictionGameAuditResult> auditUserBalance(PredictionGamePlayer player) async {
    double priorBalance = player.balance;
    bool auditPassed = db.auditPlayerTransactionsSync(player);
    double balanceChange = player.balance - priorBalance;
    if(!auditPassed) {
      await db.savePredictionGamePlayer(player, saveLinks: false);
      _log.w("Audit of player ${player.id} failed: balance changed from ${priorBalance.toStringAsFixed(2)} to ${player.balance.toStringAsFixed(2)}");
    }

    await loadPredictionGame();
    return PredictionGameAuditResult(balanceChange: balanceChange, linksChanged: !auditPassed && balanceChange == 0);
  }

  /// Audit the transactions for a player and update the balance if needed.
  PredictionGameAuditResult auditUserBalanceSync(PredictionGamePlayer player) {
    double priorBalance = player.balance;
    bool auditPassed = db.auditPlayerTransactionsSync(player);
    double balanceChange = player.balance - priorBalance;
    if(!auditPassed) {
      db.savePredictionGamePlayerSync(player);
      _log.w("Audit of player ${player.id} failed: balance changed from ${priorBalance.toStringAsFixed(2)} to ${player.balance.toStringAsFixed(2)}");
    }
    loadPredictionGameSync();
    return PredictionGameAuditResult(balanceChange: balanceChange, linksChanged: !auditPassed && balanceChange == 0);
  }

  // ======================
  // Internal utilities
  // ======================

  Future<void> loadPredictionGame() async {
    var game = await db.getPredictionGame(predictionGame.id);
    if(game != null) {
      predictionGame = game;
    }
    else {
      _log.w("Prediction game not found: ${predictionGame.id}");
    }
  }

  void loadPredictionGameSync({bool notify = false}) {
    var game = db.getPredictionGameSync(predictionGame.id);
    if(game != null) {
      predictionGame = game;
    }
    else {
      _log.w("Prediction game not found: ${predictionGame.id}");
    }
  }

  Map<String, RelativeMatchScore> _getScoresForShooters(List<Shooter> relevantShooters, RatingGroup group, ShootingMatch match, PredictionSet? predictionSet) {
    Map<String, RelativeMatchScore> scores = {};
    for(var shooter in relevantShooters) {
      RelativeMatchScore? score;
      if(predictionSet != null) {
        score = _getMatchScore(
          shooter: shooter,
          ratingGroup: group,
          match: match,
          predictionSet: predictionSet,
        );
      }
      else {
        score = _getMatchScore(
          shooter: shooter,
          ratingGroup: group,
          match: match,
        );
      }
      if(score != null) {
        scores[shooter.memberNumber] = score;
      }
    }
    return scores;
  }

  RelativeMatchScore? _getMatchScore({
    required Shooter shooter,
    required RatingGroup ratingGroup,
    required ShootingMatch match,
    PredictionSet? predictionSet,
  }) {
    // TODO: cache, maybe?
    // var memberNumber = shooter.memberNumber;
    // if(predictionSet != null) {
    //   var cachedScore = _predictionSetMemberNumberScoreCache[memberNumber];
    //   if(cachedScore != null) {
    //     return cachedScore;
    //   }
    // }
    // else {
    //   var cachedScore = _memberNumberScoreCache[memberNumber];
    //   if(cachedScore != null) {
    //     return cachedScore;
    //   }
    // }

    final divisions = ratingGroup.divisions;
    if(predictionSet != null) {
      List<Shooter> predictedShooters = predictionSet.algorithmPredictions.map((p) => p.asShooter(loadFromRating: false)).nonNulls.toList();
      var entries = match.getEntriesFor(predictedShooters, divisions: divisions);
      var scores = match.getScores(shooters: entries);
      var matchScores = scores;

      var score = matchScores.entries.firstWhereOrNull((element) => shooter.equalsShooter(element.key))?.value;
      if(score != null) {
        return score;
      }
      return null;
    }
    else {
      var entries = match.filterShooters(divisions: divisions);
      var scores = match.getScores(shooters: entries);
      var matchScores = scores;

      var score = matchScores.entries.firstWhereOrNull((element) => shooter.equalsShooter(element.key))?.value;
      if(score != null) {
        return score;
      }
      return null;
    }
  }
}

sealed class AddWagerError implements ResultErr {
  const AddWagerError();

  @override
  String get message => "Unknown error";
}

class InsufficientFundsError extends AddWagerError {
  const InsufficientFundsError();

  @override
  String get message => "Insufficient funds";
}

class ExceededMaxWagerError extends AddWagerError {
  const ExceededMaxWagerError();

  @override
  String get message => "Exceeded max wager";
}

class ExceededMaxWagerCountError extends AddWagerError {
  const ExceededMaxWagerCountError();

  @override
  String get message => "Exceeded max wager count";
}

class MatchAlreadyStartedError extends AddWagerError {
  const MatchAlreadyStartedError();

  @override
  String get message => "Match already started";
}

class InvalidParlayError extends AddWagerError {
  final ParlayValidity validity;

  InvalidParlayError({required this.validity});

  @override
  String get message => "Invalid parlay: ${validity.shortDescription}";
}

class UnknownError extends AddWagerError {
  const UnknownError();

  @override
  String get message => "Unknown error";
}

typedef AddWagerResult = Result<void, AddWagerError>;

class WagerScores {
  DbWager wager;
  Map<String, RelativeMatchScore> scores = {};
  Map<String, RelativeMatchScore> predictionSetScores = {};

  WagerScores({required this.wager});
}

enum WagerResolutionError implements ResultErr {
  alreadyResolved,
  noResolutionInformation,
  unknown;

  @override
  String get message => switch(this) {
    alreadyResolved => "Wager already resolved",
    noResolutionInformation => "Wager has no resolution information",
    unknown => "Unknown error",
  };
}