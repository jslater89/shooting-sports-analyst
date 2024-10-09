/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/global_card_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/ui/booth/ticker_settings.dart';
import 'package:shooting_sports_analyst/ui/booth/timewarp_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/ticker_text.dart';

SSALogger _log = SSALogger("BoothTicker");

class BoothTicker extends StatefulWidget {
  const BoothTicker({super.key});

  @override
  State<BoothTicker> createState() => _BoothTickerState();
}

class _BoothTickerState extends State<BoothTicker> {
  late Timer _tickerTimer;



  @override
  void initState() {
    super.initState();
    _tickerTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      setState(() {
        // update timer
      });
    });
  }

  @override
  void dispose() {
    _tickerTimer.cancel();
    super.dispose();
  }

  var tickerController = TickerTextController(autoStart: false);

  DateTime lastAutoscrollTime = DateTime(0);

  List<Widget> _cachedTickerWidgets = [];

  @override
  Widget build(BuildContext context) {
    var model = context.watch<BroadcastBoothModel>();
    var controller = context.read<BroadcastBoothController>();
    var rowCount = model.scorecards.length;

    var timeUntilUpdate = model.tickerModel.timeUntilUpdate;
    if(timeUntilUpdate < Duration(seconds: 0)) {
      timeUntilUpdate = Duration(seconds: 0);
    }

    if(model.tickerModel.hasNewEvents) {
      if(model.inTimewarp && model.calculateTimewarpTickerEvents && model.timewarpScoresBefore != lastAutoscrollTime) {
        _cachedTickerWidgets = _buildTickerWidgets(model);
        lastAutoscrollTime = model.timewarpScoresBefore!;
        tickerController.stopScroll();
        Timer(const Duration(seconds: 1), () => tickerController.startScroll());
        _log.i("Restarting ticker after timewarp");
        setState(() {});
      }
      else if(!model.inTimewarp && model.tickerModel.lastUpdateTime != lastAutoscrollTime) {
        _cachedTickerWidgets = _buildTickerWidgets(model);
        lastAutoscrollTime = model.tickerModel.lastUpdateTime;
        tickerController.stopScroll();
        Timer(const Duration(seconds: 1), () => tickerController.startScroll());
        _log.i("Restarting ticker after update");
        setState(() {});
      }
      model.tickerModel.hasNewEvents = false;
    }

    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Text("Updated at: ${DateFormat.Hm().format(model.tickerModel.lastUpdateTime)}"),
                      SizedBox(width: 10),
                      Text("Since last update: ${_timerFormat(model.tickerModel.timeSinceUpdate)}"),
                      SizedBox(width: 10),
                      Text("Until next update: ${model.tickerModel.paused ? "(paused)" : _timerFormat(timeUntilUpdate)}"),
                      SizedBox(width: 10),
                      TextButton(
                        child: model.tickerModel.paused ? Icon(Icons.play_arrow) : Icon(Icons.pause),
                        onPressed: () {
                          controller.toggleUpdatePause();
                        },
                      ),
                      TextButton(
                        child: Icon(Icons.refresh),
                        onPressed: () {
                          controller.refreshMatch();
                        },
                      ),
                      Tooltip(
                        message: "Adjust ticker settings and match update frequency.",
                        child: TextButton(
                          child: Icon(Icons.settings),
                          onPressed: () async {
                            var result = await TickerSettingsDialog.show(context, tickerModel: model.tickerModel);
                            if(result != null) {
                              controller.tickerEdited(result);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Tooltip(
                        message: "View scores at earlier points in time.",
                        child: TextButton(
                          child: Row(
                            children: [
                              Icon(Icons.restore),
                              Text("Time warp${model.inTimewarp ? " (${DateFormat.yMd().format(model.timewarpScoresBefore!)} ${DateFormat.Hm().format(model.timewarpScoresBefore!)})" : ""}"),
                            ],
                          ),
                          onPressed: () async {
                            var result = await TimewarpDialog.show(
                              context, match: model.latestMatch, initialDateTime: model.timewarpScoresBefore
                            );
                            controller.timewarp(result);
                          }
                        ),
                      ),
                      if(model.inTimewarp) Tooltip(
                        message: "Rewind time warp by one update interval.",
                        child: TextButton(
                          child: Icon(Icons.fast_rewind),
                          onPressed: () {
                            controller.timewarp(model.timewarpScoresBefore!.subtract(Duration(seconds: model.tickerModel.updateInterval)));
                          },
                        ),
                      ),
                      if(model.inTimewarp) Tooltip(
                        message: "Fast forward time warp by one update interval.",
                        child: TextButton(
                          child: Icon(Icons.fast_forward),
                          onPressed: () {
                            controller.timewarp(model.timewarpScoresBefore!.add(Duration(seconds: model.tickerModel.updateInterval)));
                          },
                        ),
                      ),
                      Tooltip(
                        message: "Adjust scoring and display settings for all scorecards.",
                        child: TextButton(
                          child: Row(
                            children: [
                              Icon(Icons.dashboard),
                              Text("Card settings"),
                            ],
                          ),
                          onPressed: () async {
                            var result = await GlobalScorecardSettingsDialog.show(context, settings: model.globalScorecardSettings);
                            if(result != null) {
                              controller.globalScorecardSettingsEdited(result);
                            }
                          }
                        ),
                      ),
                      TextButton(
                        child: Row(
                          children: [
                            Icon(Icons.add),
                            Text("Row"),
                          ],
                        ),
                        onPressed: () {
                          controller.addScorecardRow();
                        },
                      ),
                      if(rowCount > 0) SizedBox(width: 10),
                      if(rowCount > 0) TextButton(
                        child: Row(
                          children: [
                            Icon(Icons.add),
                            Text("Column"),
                          ],
                        ),
                        onPressed: () {
                          controller.addScorecardColumn(model.scorecards.first);
                        },
                      ),
                    ],
                  )
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Tooltip(
                    message: "Restart the ticker from the beginning.",
                    child: TextButton(
                      child: Icon(Icons.refresh),
                      onPressed: () {
                        tickerController.stopScroll();
                        Timer(Duration(seconds: 1), () => tickerController.startScroll());
                      },
                    ),
                  ),
                  Expanded(
                    child: TickerText(
                      controller: tickerController,
                      scrollDirection: Axis.horizontal,
                      speed: model.tickerModel.tickerSpeed,
                      startPauseDuration: Duration(seconds: 2),
                      returnDuration: Duration(milliseconds: 500),
                      child: Row(
                        key: ValueKey(lastAutoscrollTime),
                        mainAxisSize: MainAxisSize.min,
                        children: _cachedTickerWidgets,
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTickerWidgets(BroadcastBoothModel model) {
    var widgets = <Widget>[];
    var events = model.inTimewarp ? model.tickerModel.timewarpTickerEvents : model.tickerModel.liveTickerEvents;
    for(var event in events) {
      var style = event.priority.textStyle;
      widgets.add(Text(event.message, style: style));
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Text('•'),
      ));
    }
    if(widgets.isNotEmpty) {
      widgets.removeLast();
    }
    // _log.v("Ticker events: ${events.length}");
    return widgets;
  }

  String _timerFormat(Duration duration) {
    return ["${duration.inMinutes}", "${duration.inSeconds.remainder(60)}".padLeft(2, "0")].join(":");
  }
}