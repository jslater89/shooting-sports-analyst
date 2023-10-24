/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_error.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_stats_dialog.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';

class MemberNumberCollisionDialog extends StatefulWidget {
  const MemberNumberCollisionDialog({Key? key, required this.data}) : super(key: key);

  final ShooterMappingError data;

  @override
  State<MemberNumberCollisionDialog> createState() => _MemberNumberCollisionDialogState();
}

class _MemberNumberCollisionDialogState extends State<MemberNumberCollisionDialog> {
  @override
  Widget build(BuildContext context) {
    var culprit1 = widget.data.culprits[0];
    var culprit2 = widget.data.culprits[1];
    return AlertDialog(
      title: Text("Member number collision"),
      scrollable: true,
      content: SizedBox(
        width: 700,
        child: Column(
          children: [
            widget.data.dataEntry ? _dataEntryHelp : _helpMessage,
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _shooterCard(culprit1, widget.data.accomplices[culprit1] ?? []),
                ),
                Expanded(
                  child: _shooterCard(culprit2, widget.data.accomplices[culprit2] ?? []),
                )
              ],
            )
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Tooltip(
              message: "Cancel calculation and return to main menu.",
              child: TextButton(
                child: Text("ABORT"),
                onPressed: () {
                  Navigator.of(context).pop(CollisionFix(
                      action: CollisionFixAction.abort,
                      memberNumber1: "",
                      memberNumber2: ""
                  ));
                },
              ),
            ),
            if(widget.data.dataEntry) Tooltip(
              message: "Skip remaining data entry errors on this run.",
              child: TextButton(
                child: Text("SKIP REMAINING"),
                onPressed: () {
                  Navigator.of(context).pop(CollisionFix(
                    action: CollisionFixAction.skipRemainingDataErrors,
                    memberNumber1: "",
                    memberNumber2: ""
                  ));
                },
              ),
            ),
            if(!widget.data.dataEntry) TextButton(
              child: Text("MORE HELP"),
              onPressed: () {
                showDialog(context: (context), builder: (context) => AlertDialog(
                  title: Text("Collision fixes"),
                  content: SizedBox(width: 600, child: _extraHelp),
                  actions: [
                    TextButton(
                      child: Text("OK"),
                      onPressed: Navigator.of(context).pop,
                    )
                  ],
                ));
              },
            ),
            Expanded(child: Container()),
            TextButton(
              child: Text("BLACKLIST"),
              onPressed: () {
                var fix = CollisionFix(
                  action: CollisionFixAction.blacklist,
                  memberNumber1: culprit1.memberNumber,
                  memberNumber2: culprit2.memberNumber,
                );

                print(fix.toString());
                Navigator.of(context).pop(fix);
              },
            ),
            if(!widget.data.dataEntry) TextButton(
              child: Text("CREATE MAPPING"),
              onPressed: () {
                var fix = CollisionFix(
                  action: CollisionFixAction.mapping,
                  memberNumber1: culprit1.firstSeen.isBefore(culprit2.firstSeen) ? culprit1.memberNumber : culprit2.memberNumber,
                  memberNumber2: culprit1.firstSeen.isBefore(culprit2.firstSeen) ? culprit2.memberNumber : culprit1.memberNumber,
                );

                print(fix.toString());
                Navigator.of(context).pop(fix);
              },
            ),
            TextButton(
              child: Text("FIX DATA"),
              onPressed: () async {
                var fix = await showDialog<CollisionFix>(context: context, builder: (context) => _DataFixDialog(
                    culprit1: culprit1, culprit2: culprit2
                ));

                print(fix.toString());
                if(fix != null) {
                  Navigator.of(context).pop(fix);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _shooterCard(ShooterRating culprit, List<ShooterRating> accomplices) {
    var matchSet = <PracticalMatch>{};
    for(var event in culprit.ratingEvents) {
      matchSet.add(event.match);
    }
    var matches = matchSet.toList();
    matches.sort(PracticalMatch.dateComparator);
    if(matches.length > 5) {
      matches = matches.sublist(0, 5);
    }

    return Card(
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              child: Text("${culprit.getName(suffixes: false)} - ${culprit.originalMemberNumber}", style: Theme.of(context).textTheme.headline6),
              onTap: () {
                if(culprit.length > 0) {
                  showDialog(context: context, builder: (context) => ShooterStatsDialog(rating: culprit, match: culprit.ratingEvents.last.match));
                }
                else {
                  launch("https://uspsa.org/classification/${culprit.originalMemberNumber}");
                }
              },
            )
          ),
          Divider(),
          Text("Recent Matches", style: Theme.of(context).textTheme.subtitle1),
          for(var match in matches)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Text(match.name ?? "unnamed match"),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                    return ResultPage(
                      canonicalMatch: match,
                      allowWhatIf: false,
                    );
                  }));
                },
              ),
            ),
          Divider(),
          if(culprit.alternateMemberNumbers.isNotEmpty)
            Text("Alternate Member Numbers", style: Theme.of(context).textTheme.subtitle1),
          if(culprit.alternateMemberNumbers.isNotEmpty)
            for(var number in culprit.alternateMemberNumbers)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  child: Text(number),
                  onTap: () {
                    launch("https://uspsa.org/classification/$number");
                  },
                ),
              ),
          if(culprit.alternateMemberNumbers.isNotEmpty)
            Divider(),
          Text("Related Shooters", style: Theme.of(context).textTheme.subtitle1),
          for(var shooter in accomplices)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Text("${shooter.getName(suffixes: false)} - ${shooter.originalMemberNumber}"),
                onTap: () {
                  if(shooter.length > 0) {
                    showDialog(context: context, builder: (context) => ShooterStatsDialog(rating: shooter, match: shooter.ratingEvents.last.match));
                  }
                  else {
                    launchUrl(Uri.parse("https://uspsa.org/classification/${shooter.originalMemberNumber}"));
                  }
                },
              )
            ),
          // end for
        ],
      )
    );
  }

  Text get _helpMessage => const Text(
    "The automatic member number mapper thinks these two shooters are the same person, "
        "but either previously mapped them to other member numbers, or encountered them under "
        "different names and did not map them to one another. You must take action "
        "manually to establish the relationship between these member numbers, if any, before "
        "rating can continue."
  );

  Text get _dataEntryHelp => const Text(
      "The automatic member number mapper thinks this may be a typoed member number. If these two shooters "
          "appear to be the same person, use the 'fix data' option to create a data correction. If these two "
          "shooters share a name, but are not the same person, use the 'blacklist' option to suppress this message."
  );

  Text get _extraHelp => const Text(
        "If these two shooters share a name, but are not the same person, use the 'blacklist' option to prevent "
            "the member number mapper from connecting them to one another.\n\n"
        ""
        "If the shooters appear to be the same person but were not mapped, use the 'create mapping' option. (This "
            "typically happens if the shooter enters his name differently at a match where his member number also "
            "changes.)\n\n"
        ""
        "If this appears to be a data entry error, for instance if one shooter has typoed his member number or entered "
            "an incorrect one,  use the 'fix data' option to create a data correction."
  );
}

enum CollisionFixAction {
  mapping,
  blacklist,
  dataFix,
  abort,
  skipRemainingDataErrors,
}

class CollisionFix {
  final CollisionFixAction action;
  final String? name1;
  /// The source for a manual mapping.
  final String memberNumber1;
  /// The target for a manual mapping.
  final String memberNumber2;

  CollisionFix({
    required this.action,
    this.name1,
    required this.memberNumber1,
    required this.memberNumber2,
  });

  @override
  String toString() {
    if(action == CollisionFixAction.dataFix) {
      return "${action.name}: when $name1 uses $memberNumber1, treat it as $memberNumber2";
    }

    return "${action.name}: $memberNumber1 => $memberNumber2";
  }
}

class _DataFixDialog extends StatefulWidget {
  const _DataFixDialog({Key? key, required this.culprit1, required this.culprit2}) : super(key: key);

  final ShooterRating culprit1;
  final ShooterRating culprit2;

  @override
  State<_DataFixDialog> createState() => _DataFixDialogState();
}

class _DataFixDialogState extends State<_DataFixDialog> {
  late ShooterRating badRating;
  late ShooterRating goodRating;

  String? errorText;

  TextEditingController nameController = TextEditingController();
  TextEditingController wrongNumberController = TextEditingController();
  TextEditingController rightNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();

    badRating = widget.culprit1;
    goodRating = widget.culprit2;

    updateText();
  }

  void switchRatings() {
    if(badRating == widget.culprit1) {
      badRating = widget.culprit2;
      goodRating = widget.culprit1;
    }
    else {
      badRating = widget.culprit1;
      goodRating = widget.culprit2;
    }

    updateText();
  }

  void updateText() {
    nameController.text = badRating.getName(suffixes: false);
    wrongNumberController.text = badRating.memberNumber;
    rightNumberController.text = goodRating.memberNumber;
  }

  CollisionFix? createFix() {
    var name = nameController.text;
    var wrongNum = wrongNumberController.text;
    var rightNum = rightNumberController.text;

    name = name.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "").toLowerCase();

    if(name.isEmpty) {
      setState(() {
        errorText = "Missing name.";
      });
    }
    else if(wrongNum.isEmpty) {
      setState(() {
        errorText = "Missing incorrect number.";
      });
    }
    else if(rightNum.isEmpty) {
      setState(() {
        errorText = "Missing correct number.";
      });
    }
    else {
      return CollisionFix(
        action: CollisionFixAction.dataFix,
        name1: name,
        memberNumber1: wrongNum,
        memberNumber2: rightNum,
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Correct data error"),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text("When "),
                const SizedBox(width: 5),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      label: Text("Name"),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(" enters member number "),
                const SizedBox(width: 5),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: wrongNumberController,
                    decoration: InputDecoration(
                      label: Text("Incorrect #")
                    ),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[atyfblrdATYFBLRD0-9]"))],
                  ),
                ),
                const SizedBox(width: 5),
                Text(" treat it as "),
                const SizedBox(width: 5),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: rightNumberController,
                    decoration: InputDecoration(
                      label: Text("Correct #")
                    ),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[atyfblrdATYFBLRD0-9]"))],
                  ),
                ),
              ],
            ),
            if(errorText != null) Text(errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: Navigator.of(context).pop,
        ),
        TextButton(
          child: Text("SWITCH SHOOTERS"),
          onPressed: () {
            setState(() {
              switchRatings();
            });
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            var fix = createFix();
            if(fix != null) {
              Navigator.of(context).pop(fix);
            }
          },
        ),
      ],
    );
  }
}
