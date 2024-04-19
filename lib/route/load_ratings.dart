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