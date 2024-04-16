import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';

/// LoadRatingsPage accepts a configured DbRatingProject from ConfigureRatingsPage,
/// then handles displaying progress while the rating project calculates ratings
/// (if a full update is called for), or forwarding to ViewRatingsPage, if we're
/// ready to go.

class LoadRatingsPage extends StatefulWidget {
  const LoadRatingsPage({super.key, required this.project, this.forceRecalculate = false});
  
  final bool forceRecalculate;
  final DbRatingProject project;

  @override
  State<LoadRatingsPage> createState() => _LoadRatingsPageState();
}

class _LoadRatingsPageState extends State<LoadRatingsPage> {
  LoadingState currentState = LoadingState.notStarted;

  late RatingProjectLoader loader;

  @override
  void initState() {
    super.initState();

    loader = RatingProjectLoader(widget.project, callback);
  }

  Future<void> calculateRatings() async {
    
    setState(() {
      currentState = LoadingState.readingMatches;
    });


  }

  void callback({
    required int progress,
    required int total,
    required LoadingState state
  }) {
    setState(() {
      currentState = state;
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

class RatingProjectLoader {
  final DbRatingProject project;
  final RatingProjectLoaderCallback callback;

  RatingProjectLoader(this.project, this.callback);

  // TODO: return errors
  // this needs to, at minimum, be able to say:
  //    * "match X is invalid"
  //    * "shooter dedup error with details for fixing it"
  Future<void> calculateRatings() async {
    callback(progress: -1, total: -1, state: LoadingState.readingMatches);
    var matchesLink = await project.matchesToUse();

    var matchesToAdd = await matchesLink.filter().sortByDateDesc().findAll();
    var lastUsed = await project.lastUsedMatches.filter().sortByDateDesc().findAll();
    bool canAppend = false;

    if(lastUsed.isNotEmpty) {
      var missingMatches = matchesToAdd.where((e) => !lastUsed.contains(e)).toList();
      var mostRecentMatch = lastUsed.first;
      canAppend = missingMatches.every((m) => m.date.isAfter(mostRecentMatch.date));
      if(canAppend) matchesToAdd = missingMatches;
    }

    if(!canAppend) {
      await project.resetRatings();
    }

    callback(progress: 0, total: matchesToAdd.length, state: LoadingState.readingMatches);
    List<ShootingMatch> hydratedMatches = [];
    for(var match in matchesToAdd) {

    }
  }
}

/// A callback for RatingProjectLoader. When progress and total are both 0, show no progress.
/// When progress and total are both negative, show indeterminate progress. When total is positive,
/// show determinate progress with progress as the counter.
typedef RatingProjectLoaderCallback = void Function({required int progress, required int total, required LoadingState state});

enum LoadingState {
  /// Processing has not yet begun
  notStarted,
  /// New matches are downloading from remote sources
  downloadingMatches,
  /// Matches are being read from the database
  readingMatches,
  /// Scores are being processed
  processingScores,
  /// Loading is complete
  done;

  String get label {
    switch(this) {
      case LoadingState.notStarted:
        return "not started";
      case LoadingState.downloadingMatches:
        return "downloading matches";
      case LoadingState.readingMatches:
        return "loading matches from database";
      case LoadingState.processingScores:
        return "processing scores";
      case LoadingState.done:
        return "finished";
    }
  }
}