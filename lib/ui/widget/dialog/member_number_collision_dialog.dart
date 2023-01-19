import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_error.dart';

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
        width: 600,
        child: Column(
          children: [
            _helpMessage,
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
      )
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
                // TODO: launch classification page/shooter stats dialog
              },
            )
          ),
          Text("Recent Matches", style: Theme.of(context).textTheme.subtitle1),
          for(var match in matches)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Text(match.name ?? "unnamed match"),
                onTap: () {
                  // TODO: launch match results
                },
              ),
            ),
          Text("Related Shooters"),
          for(var shooter in accomplices)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                child: Text("${shooter.getName(suffixes: false)} - ${shooter.originalMemberNumber}", style: Theme.of(context).textTheme.headline6),
                onTap: () {
                  // TODO: launch classification page/shooter stats dialog
                },
              )
            ),
        ],
      )
    );
  }

  Text get _helpMessage => const Text(
    "The automatic member number mapper thinks these two shooters are the same person, "
        "but either previously mapped them to other member numbers, or encountered them under "
        "different names previously and did not map them to one another. You must take action "
        "manually to establish the relationship between these member numbers, if any, before "
        "rating can continue.\n\n"
        ""
        "The 'blacklist' option will add a blacklisted mapping with these two numbers, which will "
        "prevent the automatic mapper from attempting to connect them. Use it if these two shooters "
        "share a name, but are not the same person.\n\n"
        ""
        "If the shooters are not the same person, the one the left has entered his member number incorrectly, "
        "and the information in this dialog is sufficient to determine his correct member number, use the "
        "'fix data' option, and enter the correct member number. This will tell the member number mapper to "
        "use that member number instead, when encountering a shooter who enters this name and member number.\n\n"
        ""
        "If the shooters appear to be the same person but were not mapped, use the 'create mapping' option."
  );
}
