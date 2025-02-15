/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/help/broadcast_help.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/booth/controller.dart';
import 'package:shooting_sports_analyst/ui/booth/model.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/ui/booth/scorecard_grid.dart';
import 'package:shooting_sports_analyst/ui/booth/ticker.dart';
import 'package:shooting_sports_analyst/ui/database/match/match_db_select_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("BroadcastBoothPage");

class BroadcastBoothPage extends StatefulWidget {
  const BroadcastBoothPage({super.key, required this.match});

  final ShootingMatch? match;

  @override
  State<BroadcastBoothPage> createState() => _BroadcastBoothPageState();
}

class _BroadcastBoothPageState extends State<BroadcastBoothPage> {
  BroadcastBoothModel? model;
  BroadcastBoothController? controller;

  String scaffoldTitle = "Broadcast Mode";

  @override
  void initState() {
    if(widget.match != null) {
      model = BroadcastBoothModel(match: widget.match!);
      controller = BroadcastBoothController(model!);
      model!.addListener(() {
        if(!mounted) return;

        if(model!.ready) {
          if(model!.latestMatch.name != scaffoldTitle) {
            setState(() {
              scaffoldTitle = model!.latestMatch.name;
            });
          }
        }
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _openExistingProject() async {
    var c = controller;

    var projectJson = await HtmlOr.pickAndReadFileNow();
    if(projectJson != null) {
      var projectMap = jsonDecode(projectJson);
      _log.i("Creating new booth model...");
      var newModel = BroadcastBoothModel.fromJson(projectMap);
      _log.i("New booth model created");
      if(c == null) {
        model = newModel;
        controller = BroadcastBoothController(model!);
        await controller!.refreshMatch();
      }
      else {
        await c.loadFrom(newModel);
      }
      _log.i("New booth model ready");
      setState(() {
        scaffoldTitle = model!.latestMatch.name;
      });
    }
  }

  Future<bool> _saveProject() {
    var projectJson = jsonEncode(model!.toJson());
    return HtmlOr.saveFile("${model!.latestMatch.name.safeFilename()}-booth.json", projectJson);
  }

  @override
  Widget build(BuildContext context) {
    var m = model;
    var c = controller;
    if(m == null || c == null) {
      return Scaffold(
        appBar: AppBar(
          title: Center(child: Text(scaffoldTitle)),
        ),
        body: Center(child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            GestureDetector(
              onTap: () {
                _openExistingProject();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 230, color: Colors.grey,),
                  Text("Open an existing broadcast project", style: Theme
                      .of(context)
                      .textTheme
                      .titleMedium!
                      .apply(color: Colors.grey)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                var match = await MatchDbSelectDialog.show(context);
                if(match != null) {
                  model = BroadcastBoothModel(match: match);
                  controller = BroadcastBoothController(model!);
                  await controller!.refreshMatch();
                  setState(() {});
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dataset_rounded, size: 230, color: Colors.grey,),
                  Text("Open a match as a new broadcast project", style: Theme
                      .of(context)
                      .textTheme
                      .titleMedium!
                      .apply(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ))
      );
    }
    else if(!m.ready) {
      return Scaffold(
        appBar: AppBar(
          title: Center(child: Text(scaffoldTitle)),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    else {
      return WillPopScope(
        onWillPop: () async {
          // Show confirmation dialog
          final result = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("Exit broadcast mode?"),
                content: const Text("Any unsaved changes will be lost."),
                actions: <Widget>[
                  TextButton(
                    child: const Text("CANCEL"),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                  TextButton(
                    child: const Text("SAVE AND EXIT"),
                    onPressed: () async {
                      var success = await _saveProject();
                      Navigator.of(context).pop(success);
                    },
                  ),
                  TextButton(
                    child: const Text("EXIT WITHOUT SAVING", style: TextStyle(color: Colors.red)),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              );
            },
          );
          
          return result ?? false;
        },
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            Provider.value(value: controller),
          ],
          child: Scaffold(
            appBar: AppBar(
              title: Center(child: Text(scaffoldTitle)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () {
                    _saveProject();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    _openExistingProject();
                  },
                ),
                HelpButton(helpTopicId: broadcastHelpId),
              ],
            ),
            body: Column(
              children: [
                BoothTicker(),
                Expanded(child: BoothScorecardGrid()),
              ],
            ),
          ),
        ),
      );
    }
  }
}