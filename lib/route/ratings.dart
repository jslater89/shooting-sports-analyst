import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/route/configure_ratings.dart';
import 'package:uspsa_result_viewer/route/view_ratings.dart';

class RatingsContainerPage extends StatefulWidget {
  const RatingsContainerPage({Key? key}) : super(key: key);

  @override
  State<RatingsContainerPage> createState() => _RatingsContainerPageState();
}

class _RatingsContainerPageState extends State<RatingsContainerPage> {
  RatingHistorySettings? settings;
  List<String>? matchUrls;

  bool get configured => settings != null && matchUrls != null;

  @override
  Widget build(BuildContext context) {
    if(!configured) {
      return ConfigureRatingsPage(
        onSettingsReady: (RatingHistorySettings settings, List<String> matchUrls) async {
          setState(() {
            this.settings = settings;
            this.matchUrls = matchUrls;
          });
        }
      );
    }
    else {
      return RatingsViewPage(
        settings: settings!,
        matchUrls: matchUrls!,
      );
    }
  }
}
