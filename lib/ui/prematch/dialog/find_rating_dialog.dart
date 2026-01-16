import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

class FindRatingDialog extends StatefulWidget {
  FindRatingDialog({super.key, required this.project, required this.group, required this.ratingsInUse});
  final Set<ShooterRating> ratingsInUse;
  final DbRatingProject project;
  final RatingGroup group;

  @override
  State<FindRatingDialog> createState() => _FindRatingDialogState();

  static Future<ShooterRating?> show(BuildContext context, {required DbRatingProject project, required RatingGroup group, required Set<ShooterRating> ratingsInUse, bool getRootTheme = false}) async {
    BuildContext? rootContext;
    if(getRootTheme) {
      rootContext = Navigator.of(context, rootNavigator: true).context;
    }
    if(rootContext != null) {
      return showDialog<ShooterRating>(context: context, builder: (context) =>
        Theme(
          data: Theme.of(rootContext!),
          child: FindRatingDialog(project: project, group: group, ratingsInUse: ratingsInUse)
        )
      );
    }
    else {
      return showDialog<ShooterRating>(context: context, builder: (context) =>
        FindRatingDialog(project: project, group: group, ratingsInUse: ratingsInUse)
      );
    }
  }
}

class _FindRatingDialogState extends State<FindRatingDialog> {
  final db = AnalystDatabase();
  final searchController = TextEditingController();
  List<ShooterRating> results = [];
  bool searching = false;

  Future<void> _search(String value) async {
    setState(() {
      searching = true;
    });
    var dbResults = await db.findShooterRatings(
      project: widget.project,
      group: widget.group,
      name: value,
      limit: 50,
    );
    results = dbResults.map((e) => widget.project.wrapDbRatingSync(e)).toList();
    results.sort((a, b) => b.rating.compareTo(a.rating));
    setStateIfMounted(() {
      searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return AlertDialog(
      title: Text("Find rating"),
      content: SizedBox(
        width: 500 * uiScaleFactor,
        height: 600 * uiScaleFactor,
        child: Column(
          children: [
            Text("Enter a name or part of a name to find a rating. Up to 50 results are shown. For very common "
            "names, you may need to use a more specific query."),
            TextFormField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search term",
                suffix: searching ?
                  CircularProgressIndicator() :
                  IconButton(icon: Icon(Icons.search), onPressed: () => _search(searchController.text)),
              ),
              onFieldSubmitted: (value) => !searching ? _search(value) : null,
            ),
            Expanded(child: ListView.builder(
              itemBuilder: (context, index) {
                var rating = results[index];
                var nameText = rating.name;
                var inUse = widget.ratingsInUse.any((r) => r.equalsShooter(rating));
                if(inUse) {
                  nameText = "${nameText} (already in use)";
                }
                return ListTile(
                  enabled: !inUse,
                  title: Text(nameText),
                  subtitle: Text("${rating.lastClassification?.shortDisplayName ?? "(n/a)"} - ${rating.formattedRating()} - ${rating.memberNumber}"),
                  onTap: () => Navigator.of(context).pop(rating),
                );
              },
              itemCount: results.length,
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text("CANCEL")),
      ],
    );
  }
}