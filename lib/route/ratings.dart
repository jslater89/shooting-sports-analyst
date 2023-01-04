import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/route/configure_ratings.dart';
import 'package:uspsa_result_viewer/route/view_ratings.dart';

class RatingsContainerPage extends StatefulWidget {
  const RatingsContainerPage({Key? key}) : super(key: key);

  @override
  State<RatingsContainerPage> createState() => _RatingsContainerPageState();
}

class _RatingsContainerPageState extends State<RatingsContainerPage> {
  RatingProject? project;

  bool get configured => project != null;

  @override
  Widget build(BuildContext context) {
    if(!configured) {
      return ConfigureRatingsPage(
        onSettingsReady: (RatingProject project) async {
          setState(() {
            this.project = project;
          });
        }
      );
    }
    else {
      return WillPopScope(
        onWillPop: () async {
          return await showDialog<bool>(context: context, builder: (context) => AlertDialog(
            title: Text("Return to menu?"),
            content: Text("If you leave this page, you will need to recalculate ratings to view it again."),
            actions: [
              TextButton(
                child: Text("STAY HERE"),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text("MAIN MENU"),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              )
            ],
          )) ?? false;
        },
        child: RatingsViewPage(
          project: this.project!,
        ),
      );
    }
  }
}
