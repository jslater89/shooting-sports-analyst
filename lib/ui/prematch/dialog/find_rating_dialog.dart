/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

class FindRatingDialog extends StatefulWidget {
  FindRatingDialog({super.key, required this.project, required this.group, required this.ratingsInUse, this.initialSearch, this.registration});
  final Set<ShooterRating> ratingsInUse;
  final DbRatingProject project;
  final RatingGroup group;
  final String? initialSearch;
  final MatchRegistration? registration;

  @override
  State<FindRatingDialog> createState() => _FindRatingDialogState();

  static Future<ShooterRating?> show(BuildContext context, {
    required DbRatingProject project,
    required RatingGroup group,
    required Set<ShooterRating> ratingsInUse,
    bool getRootTheme = false,
    String? initialSearch,
    MatchRegistration? registration,
  }) async {
    BuildContext? rootContext;
    if(getRootTheme) {
      rootContext = Navigator.of(context, rootNavigator: true).context;
    }
    final dialog = FindRatingDialog(
      project: project,
      group: group,
      ratingsInUse: ratingsInUse,
      initialSearch: initialSearch,
      registration: registration,
    );
    if(rootContext != null) {
      return showDialog<ShooterRating>(context: context, builder: (context) =>
        Theme(
          data: Theme.of(rootContext!),
          child: dialog,
        )
      );
    }
    else {
      return showDialog<ShooterRating>(context: context, builder: (context) =>
        dialog,
      );
    }
  }
}

class _FindRatingDialogState extends State<FindRatingDialog> {
  final db = AnalystDatabase();
  final searchController = TextEditingController();
  List<ShooterRating> results = [];
  bool searching = false;

  @override
  void initState() {
    super.initState();
    if(widget.initialSearch != null) {
      searchController.text = widget.initialSearch!;
      _search(widget.initialSearch!);
    }
  }

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

    String? registrationInfo;
    if(widget.registration != null) {
      registrationInfo = "Searching for rating for ${widget.registration?.shooterName}";
      if(widget.registration?.shooterClassificationName != null) {
        registrationInfo += " - ${widget.registration?.shooterClassificationName}";
      }
    }
    return AlertDialog(
      title: Text("Find rating"),
      content: SizedBox(
        width: 500 * uiScaleFactor,
        height: 600 * uiScaleFactor,
        child: Column(
          spacing: 8 * uiScaleFactor,
          children: [
            if(registrationInfo != null) Text(registrationInfo),
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