import 'package:flutter/material.dart';

/// LoadRatingsPage accepts a configured DbRatingProject from ConfigureRatingsPage,
/// then handles displaying progress while the rating project calculates ratings
/// (if a full update is called for), or forwarding to ViewRatingsPage, if we're
/// ready to go.

class LoadRatingsPage extends StatefulWidget {
  const LoadRatingsPage({super.key});

  @override
  State<LoadRatingsPage> createState() => _LoadRatingsPageState();
}

class _LoadRatingsPageState extends State<LoadRatingsPage> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
