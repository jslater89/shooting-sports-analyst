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
import 'package:shooting_sports_analyst/data/string_similarity.dart';
import 'package:shooting_sports_analyst/ui_util.dart';

class FindRatingDialog extends StatefulWidget {
  FindRatingDialog({
    super.key,
    required this.project,
    required this.group,
    required this.ratingsInUse,
    this.initialSearch,
    this.initialEndsWith = true,
    this.registration,
    this.sortMode = FindRatingSortMode.similarity,
  });
  final Set<ShooterRating> ratingsInUse;
  final DbRatingProject project;
  final RatingGroup group;
  final String? initialSearch;
  final bool initialEndsWith;
  final MatchRegistration? registration;
  final FindRatingSortMode sortMode;

  @override
  State<FindRatingDialog> createState() => _FindRatingDialogState();

  static Future<ShooterRating?> show(BuildContext context, {
    required DbRatingProject project,
    required RatingGroup group,
    required Set<ShooterRating> ratingsInUse,
    bool getRootTheme = false,
    String? initialSearch,
    bool initialEndsWith = true,
    MatchRegistration? registration,
    bool useRootNavigator = false,
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
      initialEndsWith: initialEndsWith,
      registration: registration,
    );
    if(rootContext != null) {
      return showDialog<ShooterRating>(context: context, useRootNavigator: useRootNavigator, builder: (context) =>
        Theme(
          data: Theme.of(rootContext!),
          child: dialog,
        )
      );
    }
    else {
      return showDialog<ShooterRating>(context: context, useRootNavigator: useRootNavigator, builder: (context) =>
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

  late bool suffixSearch;

  @override
  void initState() {
    super.initState();
    suffixSearch = widget.initialEndsWith;
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
      limit: 100,
      searchMode: suffixSearch ? FindShooterSearchMode.endsWith : FindShooterSearchMode.contains,
    );
    results = dbResults.map((e) => widget.project.wrapDbRatingSync(e)).toList();
    var referenceName = value.toLowerCase();
    if(widget.registration != null && widget.registration!.shooterName != null) {
      referenceName = widget.registration!.shooterName!;
    }
    results.sort((a, b) {
      var aSimilarity = calculateSimilarity(referenceName, a.name);
      var bSimilarity = calculateSimilarity(referenceName, b.name);
      return bSimilarity.compareTo(aSimilarity);
    });
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
      if(widget.registration?.shooterMemberNumbers.isNotEmpty ?? false) {
        registrationInfo += "\nMember numbers: ${widget.registration?.shooterMemberNumbers.join(", ")}";
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
            Text("Enter a name or part of a name to find a rating. Up to 100 results are shown. For very common "
            "names, you may need to use a more specific query. Ratings are sorted by "
            "${widget.sortMode == FindRatingSortMode.similarity ? "similarity to the registration name" : "rating"}."),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search term",
                      suffix: searching ?
                        CircularProgressIndicator() :
                        IconButton(icon: Icon(Icons.search), onPressed: () => _search(searchController.text)),
                    ),
                    onFieldSubmitted: (value) => !searching ? _search(value) : null,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4 * uiScaleFactor,
                  children: [
                    Checkbox(value: suffixSearch, onChanged: (value) {
                      setState(() {
                        suffixSearch = value ?? true;
                      });
                    }),
                    GestureDetector(child: Text("Ends with?"), onTap: () {
                      setState(() {
                        suffixSearch = !suffixSearch;
                      });
                    }),
                  ],
                )
              ],
            ),
            Expanded(child: ListView.builder(
              itemBuilder: (context, index) {
                var rating = results[index];
                var nameText = rating.name;
                final location = rating.regionSubdivision ?? rating.region ?? null;
                var inUse = widget.ratingsInUse.any((r) => r.equalsShooter(rating));
                if(inUse) {
                  nameText = "${nameText} (already in use)";
                }
                if(location != null) {
                  nameText = "$nameText ($location)";
                }
                return ListTile(
                  enabled: !inUse,
                  title: Text(nameText),
                  subtitle: Text("${rating.lastClassification?.shortDisplayName ?? "(n/a)"} - ${rating.formattedRating} - ${rating.memberNumber}"),
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

enum FindRatingSortMode {
  similarity,
  rating;

  String get uiLabel {
    switch(this) {
      case FindRatingSortMode.similarity:
        return "Similarity";
      case FindRatingSortMode.rating:
        return "Rating";
    }
  }
}