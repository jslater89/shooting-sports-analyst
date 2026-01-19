/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/prediction_player.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/prediction_game/prediction_game_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("WagerList");

/// A list of wagers for a prediction game, match prep, or prediction game player.
///
/// Requires a [WagerListModel] to be provided.
class WagerList extends StatelessWidget {
  WagerList({super.key, this.trailingWidth, this.dimResolvedWagers = true});

  final double? trailingWidth;
  final bool dimResolvedWagers;

  final db = AnalystDatabase();

  @override
  Widget build(BuildContext context) {
    var model = Provider.of<WagerListModel>(context);
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    bool canDelete = model.player != null && model.showDelete;
    bool canResolve = model.matchPrep != null && model.showResolve;
    bool canVoid = model.matchPrep != null && model.showResolve;
    bool showPlayer = model.player == null;
    bool showMatchName = model.matchPrep == null;

    final futureMatch = model.matchPrep?.futureMatch.value;
    final matchPrepName = futureMatch?.eventName;
    ShootingMatch? matchResult;
    if(futureMatch != null) {
      var dbMatchResult = futureMatch.dbMatch.value;
      if(dbMatchResult != null) {
        var result = HydratedMatchCache().get(dbMatchResult);
        if(result.isOk()) {
          matchResult = result.unwrap();
        }
      }
    }

    Map<DbWager, WagerScores> relevantScores = {};

    if(matchResult != null) {
      relevantScores = model.managerModel.manager.getAllRelevantScores(model.wagers, match: matchResult);
    }

    var listView = ListView.builder(
      itemCount: model.wagers.length,
      itemBuilder: (context, index) {
        var wager = model.wagers[index];
        var playerName = wager.user.value!.nickname ?? wager.user.value!.serverUser.value?.username ?? "(no username)";
        var hydratedWager = wager.hydrate();
        var prediction = "${hydratedWager.descriptiveString} (${wager.ratingGroup.value?.name ?? "unknown group"})";
        var tooltipString = hydratedWager.parlayDescription;

        var moneylineOdds = hydratedWager.probability.moneylineOdds;
        var stake = hydratedWager.amount;
        var payout = hydratedWager.moneylinePayout;

        bool showTooltip = wager.isParlay;
        String oddsString;
        if(wager.isOpen) {
          oddsString = "${moneylineOdds} - ${stake.toStringAsFixed(2)} → ${payout.toStringAsFixed(2)}";
        }
        else {
          if(wager.status == DbWagerStatus.won) {
            oddsString = "${moneylineOdds} - ${(wager.payout() - wager.amount).toStringAsFixed(2)} profit";
          }
          else if(wager.status == DbWagerStatus.lost) {
            oddsString = "${moneylineOdds} - ${(wager.amount).toStringAsFixed(2)} loss";
          }
          else if(wager.status == DbWagerStatus.voided) {
            oddsString = "${moneylineOdds} - refunded ${(wager.refundTransaction.value?.amount ?? 0).toStringAsFixed(2)}";
          }
          else {
            oddsString = "${moneylineOdds} - unknown status";
          }
        }

        Widget predictionText = Text(prediction);
        if(showTooltip) {
          predictionText = Tooltip(
            message: tooltipString,
            child: predictionText,
          );
        }
        Widget descriptionText = Row(
          children: [
            Expanded(flex: 4, child: predictionText),
            Expanded(flex: 2, child: Text(oddsString)),
          ],
        );

        List<Widget> subtitleText = [];
        if(showPlayer) {
          subtitleText.add(
            Expanded(flex: 1, child: Text(playerName)),
          );
        }
        if(showMatchName) {
          subtitleText.add(
            Expanded(flex: 6, child: Text(matchPrepName ?? "", overflow: TextOverflow.ellipsis)),
          );
        }

        List<Widget> trailing = [];
        if(canDelete) {
          trailing.add(IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              var confirm = await ConfirmDialog.show(context, title: "Delete wager", content: Text("Are you sure you want to delete this wager?"));
              if(confirm ?? false) {
                await model.removeWager(wager);
              }
            },
          ));
        }
        bool hitsOnMainResult = false;
        bool hitsOnPredictionSetResult = false;
        Map<DbPrediction, bool>? legResults;
        Map<DbPrediction, bool>? predictionSetLegResults;
        WagerScores? relevantScores;
        if(matchResult != null) {
          relevantScores = model.managerModel.manager.getRelevantScores(wager);
          legResults = wager.evaluateLegs(relevantScores.scores);
          predictionSetLegResults = wager.evaluateLegs(relevantScores.predictionSetScores);
          hitsOnMainResult = legResults.entries.every((e) => e.value);
          hitsOnPredictionSetResult = predictionSetLegResults.entries.every((e) => e.value);
        }
        if(model.showScores && relevantScores != null) {
          if(wager.isParlay) {
            var hitLegs = legResults!.entries.where((e) => e.value).length;
            var predictionSetHitLegs = predictionSetLegResults!.entries.where((e) => e.value).length;
            var totalLegs = legResults.length;
            var legText = "Parlay: $hitLegs/$totalLegs - $predictionSetHitLegs/$totalLegs";
            List<String> tooltipElements = [];
            for(var prediction in wager.legs) {
              tooltipElements.add(wagerScoreString(prediction, relevantScores, includeLastNames: true, separator: " - "));
            }
            var tooltipText = tooltipElements.join("\n");
            trailing.add(Tooltip(message: tooltipText, child: Text(legText)));
          }
          else {
            var prediction = wager.legs.first;
            var scoreText = wagerScoreString(prediction, relevantScores);
            trailing.add(Text(scoreText));
          }
        }
        if(canResolve && matchResult != null && wager.isOpen) {
          String mainResolveMessage = ", for a house profit of ${wager.amount.toStringAsFixed(2)}";
          if(hitsOnMainResult) {
            mainResolveMessage = ", paying out ${wager.payout().toStringAsFixed(2)} to ${wager.user.value!.nickname}";
          }

          String predictionSetResolveMessage = ", for a house profit of ${wager.amount.toStringAsFixed(2)}";
          if(hitsOnPredictionSetResult) {
            predictionSetResolveMessage = ", paying out ${wager.payout().toStringAsFixed(2)} to ${wager.user.value!.nickname}";
          }
          trailing.add(Tooltip(
            message: hitsOnMainResult ? "Pay out hit wager against main result" : "Close missed wager against main result",
            child: IconButton(
              icon: Icon(hitsOnMainResult ? Icons.payments : Icons.payments_outlined),
              onPressed: () async {
                var confirm = await ConfirmDialog.show(
                  context,
                  title: "Resolve wager",
                  content: Text("Are you sure you want to resolve this wager${mainResolveMessage}?"),
                  positiveButtonLabel: "${hitsOnMainResult ? "PAY" : "CLOSE"} WAGER",
                );
                if(confirm ?? false) {
                  await model.managerModel.resolveWager(wager, hitsOnMainResult ? DbWagerStatus.won : DbWagerStatus.lost);
                }
              },
            ),
          ));
          trailing.add(Tooltip(
            message: hitsOnPredictionSetResult ? "Pay out hit wager against prediction set result" : "Close missed wager against prediction set result",
            child: IconButton(
              icon: Icon(hitsOnPredictionSetResult ? Icons.payments : Icons.payments_outlined),
              onPressed: () async {
                var confirm = await ConfirmDialog.show(
                  context,
                  title: "Resolve wager",
                  content: Text("Are you sure you want to resolve this wager${predictionSetResolveMessage}?"),
                  positiveButtonLabel: "${hitsOnPredictionSetResult ? "PAY" : "CLOSE"} WAGER",
                );
                if(confirm ?? false) {
                  await model.managerModel.resolveWager(wager, hitsOnPredictionSetResult ? DbWagerStatus.won : DbWagerStatus.lost);
                }
              },
            ),
          ));
        }
        if(canVoid && wager.status != DbWagerStatus.voided) {
          trailing.add(Tooltip(
            message: "Void wager",
            child: IconButton(
              icon: Icon(Icons.clear),
              onPressed: () async {
                double totalRefund = wager.amount;
                if(wager.payoutTransaction.value != null) {
                  totalRefund -= wager.payoutTransaction.value!.amount;
                }

                String message;
                if(wager.status == DbWagerStatus.pending) {
                  message = "Are you sure you want to void this wager, refunding ${totalRefund.toStringAsFixed(2)} to ${wager.user.value!.nickname}?";
                }
                else if(totalRefund > 0) {
                  message = "Are you SURE you want to void this already-resolved wager, refunding ${totalRefund.toStringAsFixed(2)} to ${wager.user.value!.nickname}?";
                }
                else {
                  message = "Are you SURE you want to void this already-voided wager, reclaiming ${totalRefund.toStringAsFixed(2)} in winnings from ${wager.user.value!.nickname}?";
                }
                var confirm = await ConfirmDialog.show(
                  context,
                  title: "Void wager",
                  width: 350 * uiScaleFactor,
                  content: Text(message),
                  positiveButtonLabel: "VOID WAGER",
                );
                if(confirm ?? false) {
                  await model.managerModel.resolveWager(wager, DbWagerStatus.voided);
                }
              },
            ),
          ));
        }

        Widget trailingWidget;
        if(trailing.length > 1) {
          trailingWidget = Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: trailing,
          );
        }
        else if(trailing.length == 1) {
          trailingWidget = trailing.first;
        }
        else {
          trailingWidget = const SizedBox.shrink();
        }

        if(trailingWidth != null) {
          trailingWidget = SizedBox(
            width: trailingWidth! * uiScaleFactor,
            child: trailingWidget,
          );
        }

        bool disabled = dimResolvedWagers && !wager.isOpen;
        return ListTile(
          enabled: !disabled,
          title: descriptionText,
          subtitle: Row(children: subtitleText),
          trailing: trailingWidget,
        );
      },
    );

    if(!canDelete) {
      return listView;
    }
    else {
      return Column(
        children: [
          Expanded(child: listView),
        ],
      );
    }
  }

  String wagerScoreString(DbPrediction prediction, WagerScores relevantScores, {bool includeLastNames = false, String separator = "\n"}) {
    if(prediction.type == DbPredictionType.spread) {
      var mainTargetScore = relevantScores.scores[prediction.target.memberNumber];
      var mainDogScore = relevantScores.scores[prediction.underdog!.memberNumber];
      var predictionSetMainTargetScore = relevantScores.predictionSetScores[prediction.target.memberNumber];
      var predictionSetMainDogScore = relevantScores.predictionSetScores[prediction.underdog!.memberNumber];
      var scoreText = "";

      if(mainTargetScore != null && mainDogScore != null) {
        var mainTargetName = prediction.target.lastName;
        // var mainDogName = prediction.underdog!.lastName;

        var mainRatio = mainTargetScore.ratio;
        var mainDogRatio = mainDogScore.ratio;
        var mainSpread = mainRatio - mainDogRatio;
        mainSpread = -mainSpread;
        var positiveSign = mainSpread > 0 ? "+" : "";

        scoreText += "$mainTargetName $positiveSign${mainSpread.asPercentage(decimals: 2, includePercent: true)}";
      }
      else {
        scoreText += "(missing scores)";
      }

      if(predictionSetMainTargetScore != null && predictionSetMainDogScore != null) {
        var predictionSetTargetName = prediction.target.lastName;
        // var predictionSetDogName = prediction.underdog!.lastName;
        var predictionSetRatio = predictionSetMainTargetScore.ratio;
        var predictionSetDogRatio = predictionSetMainDogScore.ratio;
        var predictionSetSpread = predictionSetRatio - predictionSetDogRatio;
        predictionSetSpread = -predictionSetSpread;
        var positiveSign = predictionSetSpread > 0 ? "+" : "";
        scoreText += "\n$predictionSetTargetName $positiveSign${predictionSetSpread.asPercentage(decimals: 2, includePercent: true)}";
      }
      else {
        scoreText += "\n(missing scores)";
      }
      return scoreText;
    }
    else {
      var mainScore = relevantScores.scores[prediction.target.memberNumber];
      var predictionSetScore = relevantScores.predictionSetScores[prediction.target.memberNumber];
      var scoreText = "";
      if(mainScore != null) {
        var decimals = mainScore.ratio == 1.0 ? 0 : 2;
        if(includeLastNames) {
          scoreText += "${prediction.target.lastName} ";
        }
        scoreText += "${mainScore.place.ordinalPlace} (${mainScore.ratio.asPercentage(decimals: decimals, includePercent: true)})";
      }
      if(predictionSetScore != null) {
        var decimals = predictionSetScore.ratio == 1.0 ? 0 : 2;
        scoreText += separator;
        if(includeLastNames) {
          scoreText += "${prediction.target.lastName} ";
        }
        scoreText += "${predictionSetScore.place.ordinalPlace} (${predictionSetScore.ratio.asPercentage(decimals: decimals, includePercent: true)})";
      }
      return scoreText;
    }
  }
}

/// A model for a [WagerList].
///
/// If [matchPrep] is provided, the wagers will be filtered to only include wagers for that match prep.
///
/// If [player] is provided, the wagers will be filtered to only include wagers for that player, and
/// the widget will also include UI to manage the player's wagers.
class WagerListModel extends ChangeNotifier {
  WagerListModel({
    required this.managerModel,
    PredictionGamePlayer? player,
    MatchPrep? matchPrep,
    bool openOnly = false,
    this.dimResolvedWagers = true,
  }) : _openOnly = openOnly {
    playerId = player?.id;
    matchPrepId = matchPrep?.id;
    loadWagers();
    managerModel.addListener(loadWagers);
  }

  @override
  void dispose() {
    managerModel.removeListener(loadWagers);
    super.dispose();
  }

  bool dimResolvedWagers;

  bool _showDelete = true;
  set showDelete(bool value) {
    _showDelete = value;
    notifyListeners();
  }
  bool get showDelete => _showDelete;

  bool _showResolve = false;
  set showResolve(bool value) {
    _showResolve = value;
    notifyListeners();
  }
  bool get showResolve => _showResolve;

  bool _showScores = false;
  set showScores(bool value) {
    _showScores = value;
    notifyListeners();
  }
  bool get showScores => _showScores;

  PredictionGameManagerModel managerModel;
  int? playerId;
  int? matchPrepId;
  bool _openOnly = false;
  set openOnly(bool value) {
    _openOnly = value;
    loadWagers();
  }
  bool get openOnly => _openOnly;

  PredictionGamePlayer? get player => playerId != null ? managerModel.getPlayerById(playerId!) : null;
  MatchPrep? get matchPrep => matchPrepId != null ? managerModel.getMatchPrepById(matchPrepId!) : null;

  List<DbWager> wagers = [];

  Future<void> loadWagers() async {
    var newWagers = await managerModel.getWagers(openOnly: openOnly, matchPrep: matchPrep, player: player);
    _setWagers(newWagers);
  }

  void _setWagers(List<DbWager> wagers) {
    this.wagers = wagers;
    notifyListeners();
  }

  Future<void> addWager(DbWager wager) async {
    if(wager.user.value == null) {
      throw ArgumentError("Wager has no user");
    }
    await managerModel.addWager(wager);
    notifyListeners();
  }

  Future<void> removeWager(DbWager wager) async {
    await managerModel.removeWager(wager);
    notifyListeners();
  }

  Future<void> setMatchPrep(MatchPrep? matchPrep) async {
    matchPrepId = matchPrep?.id;
    await loadWagers();
    notifyListeners();
  }

  Future<void> setPlayer(PredictionGamePlayer? player) async {
    playerId = player?.id;
    await loadWagers();
    notifyListeners();
  }
}
