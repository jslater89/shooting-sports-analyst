/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

part 'prediction_user.g.dart';

/// A user
@collection
class PredictionGameUser {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'predictionGameUser')
  final serverUser = IsarLink<User>();

  /// The game this user is participating in.
  final game = IsarLink<PredictionGame>();

  /// The wagers this user has made.
  final wagers = IsarLinks<DbWager>();

  final transactions = IsarLinks<PredictionGameTransaction>();

  /// Audits the transactions for the user and updates the balance if needed.
  ///
  /// Returns true if the audit passes (i.e., the balance is consistent with the transactions).
  bool auditTransactionsSync({bool updateBalance = true}) {
    var totalDebit = 0.0;
    var totalCredit = 0.0;
    for(var transaction in transactions) {
      if(transaction.type.isDebit) {
        totalDebit += transaction.amount;
      }
      else {
        totalCredit += transaction.amount;
      }
    }
    var newBalance = totalCredit - totalDebit;
    if(updateBalance && newBalance != balance) {
      balance = newBalance;
    }
    return newBalance == balance;
  }

  double balance = 0.0;
}

@collection
class PredictionGameTransaction {
  Id id = Isar.autoIncrement;

  @enumerated
  PredictionGameTransactionType type;
  double amount;

  final user = IsarLink<PredictionGameUser>();
  final game = IsarLink<PredictionGame>();

  /// The wager that this transaction is associated with, if type is
  /// wager or payout.
  final wager = IsarLink<DbWager>();

  PredictionGameTransaction({
    required this.type,
    required this.amount,
  });
}

enum PredictionGameTransactionType {
  /// A top-up transaction is an automated deposit to a user's balance, either
  /// the initial deposit for user type, or a top-up to their starting balance
  /// if they're below the start at the end of some time period.
  topUp,

  /// A wager transaction is a wager made by a user.
  wager,
  payout;

  bool get isDebit => this == wager;
  bool get isCredit => this == topUp || this == payout;
}