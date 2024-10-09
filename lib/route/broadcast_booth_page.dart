/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_grid.dart';
import 'package:shooting_sports_analyst/ui/booth/ticker.dart';

SSALogger _log = SSALogger("BroadcastBoothPage");

class BroadcastBoothPage extends StatefulWidget {
  const BroadcastBoothPage({super.key, required this.match});

  final ShootingMatch match;

  @override
  State<BroadcastBoothPage> createState() => _BroadcastBoothPageState();
}

class _BroadcastBoothPageState extends State<BroadcastBoothPage> {
  late BroadcastBoothModel model;
  late BroadcastBoothController controller;

  @override
  void initState() {
    model = BroadcastBoothModel(match: widget.match);
    controller = BroadcastBoothController(model);
    model.addListener(() {
      if(!mounted) return;

      if(model.ready) {
        if(model.latestMatch.name != widget.match.name) {
          setState(() {});
        }
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: model),
        Provider.value(value: controller),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Center(child: Text(model.latestMatch.name)),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () {
                var projectJson = jsonEncode(model.toJson());
                HtmlOr.saveFile("project.json", projectJson);
              },
            ),
            IconButton(
              icon: const Icon(Icons.file_open),
              onPressed: () async {
                var projectJson = await HtmlOr.pickAndReadFileNow();
                if(projectJson != null) {
                  var projectMap = jsonDecode(projectJson);
                  _log.i("Creating new booth model...");
                  var newModel = BroadcastBoothModel.fromJson(projectMap);
                  _log.i("New booth model created");
                  await controller.loadFrom(newModel);
                  _log.i("New booth model ready");
                  setState(() {});
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.help),
              onPressed: () {
                showDialog(context: context, builder: (context) => BoothHelpDialog());
              },
            ),
          ],
        ),
        body: Column(
          children: [
            BoothTicker(),
            Expanded(child: BoothScorecardGrid()),
          ],
        ),
      ),
    );
  }
}