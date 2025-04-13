import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/project_rollback.dart';
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("RollbackRatingsPage");

/// RollbackRatingsPage accepts a configured DbRatingProject from ConfigureRatingsPage,
/// then handles displaying progress while the rating project rolls back to the provided
/// date.
class RollbackRatingsPage extends StatefulWidget {
  const RollbackRatingsPage({super.key, required this.project, required this.rollbackDate, required this.onRatingsComplete, required this.onError});

  final DbRatingProject project;
  final VoidCallback onRatingsComplete;
  final DateTime rollbackDate;
  final void Function(RatingProjectRollbackError error) onError;

  @override
  State<StatefulWidget> createState() {
    return _RollbackRatingsPageState();
  }
}

class _RollbackRatingsPageState extends State<RollbackRatingsPage> {
  late RatingProjectRollback rollback;

  RollbackState currentState = RollbackState.notStarted;
  int _currentProgress = 0;
  int _totalProgress = 0;
  int? _subProgress;
  int? _subTotal;
  String? _eventName;

  @override
  void initState() {
    super.initState();
    rollback = RatingProjectRollback(project: widget.project, callback: progressCallback);

    rollbackRatings();
  }

  Future<void> rollbackRatings() async {
    try {
      await rollback.rollback(widget.rollbackDate);
      widget.onRatingsComplete();
    }
    catch(e, st) {
      _log.e("Error rolling back ratings", error: e, stackTrace: st);
      if(e is Exception) {
        widget.onError(UncaughtRollbackException(e));
      }
      else {
        widget.onError(StringRollbackError(e.toString()));
      }
    }
  }

  Future<void> progressCallback({
    required int progress,
    required int total,
    required RollbackState state,
    String? eventName,
    int? subProgress,
    int? subTotal,
  }) async {
    await Future.delayed(const Duration(microseconds: 1));
    setState(() {
      _currentProgress = progress;
      _totalProgress = total;
      currentState = state;
      _eventName = eventName;
      _subProgress = subProgress;
      _subTotal = subTotal;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Loading..."),
      ),
      body: Center(
        child: _matchLoadingIndicator(),
      ),
    );
  }

  Widget _matchLoadingIndicator() {
    Widget loadingText;

    if(_eventName != null) {
      loadingText = Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(child: Container()),
          Expanded(flex: 6, child: Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.right)),
          Expanded(child: Container()),
          Expanded(flex: 6, child: Text(_eventName!, overflow: TextOverflow.ellipsis, softWrap: false)),
          Expanded(child: Container())
        ],
      );
    }
    else {
      List<Widget> elements = [
        Expanded(flex: 3, child: Text("Now: ${currentState.label}", style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center)),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
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
      ],
    );
  }
}
