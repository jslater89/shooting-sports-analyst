// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/project_loader.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/deduplication_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("LoadRatingsPage");

/// LoadRatingsPage accepts a configured DbRatingProject from ConfigureRatingsPage,
/// then handles displaying progress while the rating project calculates ratings
/// (if a full update is called for), or forwarding to ViewRatingsPage, if we're
/// ready to go.

class LoadRatingsPage extends StatefulWidget {
  const LoadRatingsPage({super.key, required this.project, this.forceRecalculate = false, required this.onRatingsComplete});
  
  final bool forceRecalculate;
  final DbRatingProject project;
  final VoidCallback onRatingsComplete;

  @override
  State<LoadRatingsPage> createState() => _LoadRatingsPageState();
}

class _LoadRatingsPageState extends State<LoadRatingsPage> {
  LoadingState currentState = LoadingState.notStarted;

  late RatingProjectLoader loader;
  late RatingProjectLoaderHost host;

  int _currentProgress = 0;
  int _totalProgress = 0;
  String? _loadingEventName;
  String? _loadingGroupName;
  var _loadingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    RatingProjectLoaderHost host = RatingProjectLoaderHost(
      progressCallback: callback,
      deduplicationCallback: deduplicationCallback,
    );

    loader = RatingProjectLoader(widget.project, host);
    calculateRatings();
  }

  Future<void> calculateRatings() async {
    
    setState(() {
      currentState = LoadingState.readingMatches;
    });

    var result = await loader.calculateRatings(fullRecalc: widget.forceRecalculate);
    if(result.isErr()) {
      _log.e(result.unwrapErr());
    }
  }

  Future<Result<List<DeduplicationAction>, DeduplicationError>> deduplicationCallback(List<DeduplicationCollision> deduplicationResult) async {
    var userApproves = await DeduplicationDialog.show(context, widget.project.sport, deduplicationResult);
    if(userApproves ?? false) {
      return Result.ok(deduplicationResult.map((e) => e.proposedActions).flattened.toList());
    }
    else {
      return Result.err(DeduplicationError("User requested cancelation."));
    }
  }

  Future<void> callback({
    required int progress,
    required int total,
    required LoadingState state,
    String? eventName,
    String? groupName,
  }) async {
    if(state != currentState) {
      _log.i("Rating calculation state changed: $state");
    }
    else {
      _log.vv("$progress/$total");
    }
    setStateIfMounted(() {
      currentState = state;
      _loadingEventName = eventName;
      _loadingGroupName = groupName;
      _currentProgress = progress;
      _totalProgress = total;
    });
    // Allow a UI update
    await Future.delayed(const Duration(microseconds: 1));

    if(state == LoadingState.done) {
      _log.i(Timings());
      widget.onRatingsComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Loading..."),
      ),
      body: _matchLoadingIndicator(),
    );
  }

  Widget _matchLoadingIndicator() {
    Widget loadingText;

    if(_loadingEventName != null) {
      var parts = _loadingEventName!.split(" - ");

      if(parts.length >= 2) {
        var divisionText = parts[0];
        var eventText = parts.sublist(1).join(" - ");
        loadingText = Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: Container()),
            Expanded(flex: 6, child: Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.subtitle2, textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text(divisionText, overflow: TextOverflow.ellipsis, softWrap: false, textAlign: TextAlign.center)),
            Expanded(flex: 6, child: Text(eventText, overflow: TextOverflow.ellipsis, softWrap: false, textAlign: TextAlign.center)),
            Expanded(child: Container())
          ],
        );
      }
      else {
        loadingText = Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: Container()),
            Expanded(flex: 3, child: Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.subtitle2, textAlign: TextAlign.center)),
            Expanded(flex: 3, child: Text(_loadingEventName!, overflow: TextOverflow.ellipsis, softWrap: false)),
            Expanded(flex: 3, child: Text(_loadingGroupName!, overflow: TextOverflow.ellipsis, softWrap: false)),
            Expanded(child: Container())
          ],
        );
      }
    }
    else {
      loadingText = Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.subtitle2);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Loading...", style: Theme.of(context).textTheme.subtitle1),
          loadingText,
          SizedBox(height: 10),
          if(_totalProgress > 0)
            LinearProgressIndicator(
              value: _currentProgress / _totalProgress,
            ),
          SizedBox(height: 20),
          Expanded(
            child: Scrollbar(
              controller: _loadingScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _loadingScrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...widget.project.matches.toList().reversed.map((match) {
                      return Text("${match.eventName}");
                    })
                  ],
                ),
              ),
            )
          )
        ],
      ),
    );
  }
}