// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:audioplayers/audioplayers.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/project_loader.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/deduplication_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("LoadRatingsPage");

/// LoadRatingsPage accepts a configured DbRatingProject from ConfigureRatingsPage,
/// then handles displaying progress while the rating project calculates ratings
/// (if a full update is called for), or forwarding to ViewRatingsPage, if we're
/// ready to go.

class LoadRatingsPage extends StatefulWidget {
  const LoadRatingsPage({super.key, required this.project, this.forceRecalculate = false, required this.onRatingsComplete, required this.onError});

  final bool forceRecalculate;
  final DbRatingProject project;
  final VoidCallback onRatingsComplete;
  final void Function(RatingProjectLoadError error) onError;

  @override
  State<LoadRatingsPage> createState() => _LoadRatingsPageState();
}

class _LoadRatingsPageState extends State<LoadRatingsPage> {
  LoadingState currentState = LoadingState.notStarted;

  late RatingProjectLoader loader;
  late RatingProjectLoaderHost host;

  int _currentProgress = 0;
  int _totalProgress = 0;
  int? _subProgress;
  int? _subTotal;
  String? _loadingEventName;
  String? _loadingGroupName;
  var _loadingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    RatingProjectLoaderHost host = RatingProjectLoaderHost(
      progressCallback: progressCallback,
      deduplicationCallback: deduplicationCallback,
      unableToAppendCallback: unableToAppendCallback,
      fullRecalculationRequiredCallback: fullRecalculationRequiredCallback,
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
      var error = result.unwrapErr();
      _log.e(error.message);
      widget.onError(error);
    }
    else {
      var config = ConfigLoader().config;
      if(config.playRatingsCalculationCompleteAlert) {
        var complete = result.unwrap();
        if(complete.matchesAddedCount > 0) {
          var player = AudioPlayer();
          player.play(AssetSource("audio/update-bell.mp3"));
        }
      }
    }
  }

  Future<bool> fullRecalculationRequiredCallback() async {
    var shouldRecalculate = await ConfirmDialog.show(
      context,
      title: "Full recalculation required",
      content: Text("The project must be recalculated in full. Do you want to proceed?"),
      negativeButtonLabel: "CANCEL",
      positiveButtonLabel: "RECALCULATE",
      barrierDismissible: false,
    ) ?? false;

    return shouldRecalculate;
  }

  Future<bool> unableToAppendCallback(List<MatchPointer> lastUsedMatches, List<MatchPointer> newMatches) async {
    var shouldRecalculate = await ConfirmDialog.show(
      context,
      title: "Unable to append",
      content: Text("The selected matches cannot be appended to the existing project. Do you want to start a full recalculation instead?"),
      negativeButtonLabel: "ADVANCE WITHOUT CALCULATING",
      positiveButtonLabel: "RECALCULATE",
      barrierDismissible: false,
    ) ?? false;

    return shouldRecalculate;
  }

  Future<Result<List<DeduplicationAction>, DeduplicationError>> deduplicationCallback(RatingGroup group,List<DeduplicationCollision> deduplicationResult) async {
    var userApproves = await DeduplicationDialog.show(context, sport: widget.project.sport, collisions: deduplicationResult, group: group);
    if(userApproves ?? false) {
      return Result.ok(deduplicationResult.map((e) => e.proposedActions).flattened.toList());
    }
    else {
      return Result.err(DeduplicationError("User requested cancelation."));
    }
  }

  Future<void> progressCallback({
    required int progress,
    required int total,
    required LoadingState state,
    String? eventName,
    String? groupName,
    int? subProgress,
    int? subTotal,
  }) async {
    if(state != currentState) {
      _log.i("Rating calculation state changed: $state");
    }
    else {
      // _log.vv("$progress/$total");
    }
    setStateIfMounted(() {
      currentState = state;
      _loadingEventName = eventName;
      _loadingGroupName = groupName;
      _currentProgress = progress;
      _totalProgress = total;
      _subProgress = subProgress;
      _subTotal = subTotal;
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
      body: PopScope(
        canPop: false,
        onPopInvoked: (_didPop) async {
          var confirm = await ConfirmDialog.show(
            context,
            title: "Cancel loading?",
            width: 500,
            content: Text("Are you sure you want to cancel loading? If you cancel during rating calculation, it "
            "may result in an inconsistent database state, and require a full recalculation."),
            negativeButtonLabel: "CONTINUE LOADING",
            positiveButtonLabel: "CANCEL LOADING",
            barrierDismissible: false,
          );

          if(confirm ?? false) {
            // The loader will cancel itself at the next opportunity
            // and return an error.
            loader.cancel();
          }
        },
        child: _matchLoadingIndicator()
      ),
    );
  }

  Widget _matchLoadingIndicator() {
    Widget loadingText;

    if(_loadingEventName != null) {
      loadingText = Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(child: Container()),
          Expanded(flex: 6, child: Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(_loadingGroupName ?? "(no group)", overflow: TextOverflow.ellipsis, softWrap: false, textAlign: TextAlign.center)),
          Expanded(flex: 6, child: Text(_loadingEventName!, overflow: TextOverflow.ellipsis, softWrap: false)),
          Expanded(child: Container())
        ],
      );
    }
    else {
      List<Widget> elements = [
        Expanded(flex: 3, child: Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center)),
        if(_loadingGroupName != null)
          Expanded(flex: 3, child: Text(_loadingGroupName!, overflow: TextOverflow.ellipsis, softWrap: false, textAlign: TextAlign.center)),
      ];
      loadingText = Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: Container()),
            ...elements,
            Expanded(child: Container())
          ],
        );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Loading...", style: Theme.of(context).textTheme.titleMedium),
          loadingText,
          SizedBox(height: 10),
          if(_totalProgress > 0)
            LinearProgressIndicator(
              minHeight: 5,
              value: _currentProgress / _totalProgress,
            ),
          if(_subTotal != null && _subProgress != null && _subTotal! > 0)
            LinearProgressIndicator(
              minHeight: 5,
              value: _subProgress! / _subTotal!,
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
                    ...widget.project.matchPointers.toList().reversed.map((match) {
                      return Text("${match.name}");
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
