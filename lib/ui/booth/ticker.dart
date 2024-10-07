/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/ui/booth/ticker_settings.dart';

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

  @override
  Widget build(BuildContext context) {
    var model = context.watch<BroadcastBoothModel>();
    var controller = context.read<BroadcastBoothController>();
    var rowCount = model.scorecards.length;

    var timeUntilUpdate = model.tickerModel.timeUntilUpdate;
    if(timeUntilUpdate < Duration(seconds: 0)) {
      timeUntilUpdate = Duration(seconds: 0);
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
                      Text("Until next update: ${model.tickerModel.paused ? "-:--" : _timerFormat(timeUntilUpdate)}"),
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
                      TextButton(
                        child: Icon(Icons.settings),
                        onPressed: () async {
                          var result = await TickerSettingsDialog.show(context, tickerModel: model.tickerModel);
                          if(result != null) {
                            controller.tickerEdited(result);
                          }
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
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
            ],
          ),
        ),
      ),
    );
  }

  String _timerFormat(Duration duration) {
    return ["${duration.inMinutes}", "${duration.inSeconds.remainder(60)}".padLeft(2, "0")].join(":");
  }
}