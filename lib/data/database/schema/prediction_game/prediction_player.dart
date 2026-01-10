/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

part 'prediction_player.g.dart';

/// A player in a prediction game, which may optionally be backed by a server user.
@collection
class PredictionGamePlayer {
  Id id = Isar.autoIncrement;

  /// A name to use for this user in place of their
  /// server user's display name, or if this is a non-server-user-backed
  /// player.
  String? nickname;

  /// The server user that this player is backed by, if any.
  @Backlink(to: 'predictionGamePlayer')
  final serverUser = IsarLink<User>();

  /// The game this user is participating in.
  final game = IsarLink<PredictionGame>();

  /// The wagers this user has made.
  @Backlink(to: 'user')
  final wagers = IsarLinks<DbWager>();

  /// The transactions for the user.
  @Backlink(to: 'user')
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
    var isConsistent = newBalance == balance;
    if(updateBalance && !isConsistent) {
      balance = newBalance;
    }
    return isConsistent;
  }

  double balance = 0.0;
}

@collection
class PredictionGameTransaction {
  Id id = Isar.autoIncrement;

  @enumerated
  PredictionGameTransactionType type;
  double amount;

  /// The user that this transaction is associated with.
  final user = IsarLink<PredictionGamePlayer>();

  /// The game that this transaction is associated with.
  final game = IsarLink<PredictionGame>();

  /// The wager that this transaction is associated with, if type is
  /// wager, payout, or refund.
  final wager = IsarLink<DbWager>();

  /// Whether this transaction debits the user's balance (i.e. is a wager)
  bool get isDebit => type.isDebit;

  /// Whether this transaction credits the user's balance (i.e. is a top-up or payout)
  bool get isCredit => type.isCredit;

  DateTime created;

  PredictionGameTransaction({
    required this.type,
    required this.amount,
    required this.created,
  });
}

enum PredictionGameTransactionType {
  /// A top-up transaction is an automated deposit to a user's balance, either
  /// the initial deposit for user type, or a top-up to their starting balance
  /// if they're below the start at the end of some time period.
  topUp,

  /// A wager transaction is a wager made by a user.
  wager,

  /// A payout transaction is a payout made to a user for a winning wager.
  payout,

  /// A refund transaction is a payout made to a user for a voided wager.
  /// (i.e., the set of competitors present changed significantly enough to invalidate the wager)
  refund;

  bool get isDebit => this == wager;
  bool get isCredit => this == topUp || this == payout || this == refund;

  @ignore
  String get displayName => switch(this) {
    topUp => "Top-up",
    wager => "Wager",
    payout => "Payout",
    refund => "Refund",
  };
}