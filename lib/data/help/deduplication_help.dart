/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/icore_deduplicator_help.dart";
import "package:shooting_sports_analyst/data/help/uspsa_deduplicator_help.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const deduplicationHelpId = "deduplication";
const deduplicationHelpLink = "?deduplication";
final helpDeduplication = HelpTopic(
  id: deduplicationHelpId,
  name: "Deduplication",
  content: _content,
);

const _content = """# Deduplication

Deduplication is the process of combining match results for competitors who appear under different member numbers. When loading match
results, the application automatically detects potential duplicates and presents them for review.

The top-line summary of this article is that _if you do not take manual action, your ratings will be inaccurate_. Even conflicts for
which the deduplicator makes a confident suggestion should be reviewed to ensure that the suggested actions are correct.

## The Deduplication Dialog

The deduplication dialog shows a list of potential duplicates on the left side. Each entry shows:

* The competitor's name
* The member numbers involved
* The type of action proposed (mapping, data fix, etc.)
* A status icon:
    * Green check: likely ready to apply, but review is recommended
    * Yellow question mark: actions proposed, but review and approval are required
    * Red warning: actions may be proposed, but action edits are almost certainly required

In the main panel, you will find more detail on the conflict (including its causes, and member numbers involved in each cause), a list
of known member numbers sorted by their detected categories, and a list of actions the automated deduplicator has proposed (if any). At
the bottom right are buttons to approve the proposed resolution, to restore the original resolution, or to ignore the conflict.

A conflict can only be approved if proposed actions cover every member number involved in the conflict. The IGNORE button may be used on
yellow conflicts to ignore the conflict for now. It _will_ submit any proposed actions attached to the conflict.

## Action Types

### User Mappings
User mappings connect multiple valid member numbers that belong to the same competitor. For example, if a competitor has both a standard
number (A12345) and a life member number (L789), you can create a mapping to combine their match history.

### Data Entry Fixes
Data entry fixes correct typos or other errors in member numbers. When a competitor enters an incorrect number, the fix will
automatically convert it to the correct number. For example, if John Doe accidentally enters 'A12354' instead of 'A12345', a data entry
fix will correct this automatically in future imports.

### Blacklist Entries
Blacklist entries prevent automatic association between member numbers that belong to different competitors who happen to share the same
name. For example, if there are two competitors named John Smith with different member numbers, a blacklist entry prevents their results
from being combined.

More broadly, blacklist entries indicate to the rating engine that two member numbers should not be associated with one another.

## Automatic Detection and Manual Review

The application attempts to automatically detect duplicates using several methods:

* Domain knowledge (e.g., knowing that A12345 and TY12345 represent the same competitor in [USPSA]($uspsaDeduplicatorHelpLink))
* Name matching when member number categories change if relevant for the sport (e.g., knowing that if the name John Jaroszewski
appears alongside the member numbers A123456 and L1234, they likely refer to the same person)
* String similarity measures applied to entered member numbers (e.g., knowing that if John Jaroszewski appears alongside A123456
and A123465, the numbers probably refer to one person, but John Jaroszewski A123456 and John Jaroszewski A88471 are probably
distinct individuals)

Some conflicts require manual review, most commonly in scenarios where the system cannot make a confident guess as to the correct
solution. Imagine that, for competitor name John Doe, there are four USPSA member numbers: A123456, A654321, L1234, and L4321. The most
likely scenario is that there are two distinct John Does, each with one associate and one lifetime number, but the deduplicator has no
way of determining which is which. In this case, the deduplicator will mark the conflict with a red warning symbol and require manual
review.

When reviewing duplicates:

1. Check the competitor's name and member numbers
2. Review any proposed automatic actions
3. Add or modify actions as needed
4. Click APPROVE when satisfied with the resolution

You must review all red-marked duplicates before proceeding. Yellow-marked duplicates should be reviewed but can be approved without
changes if the automatic detection appears correct.

## Tips

* Read help topics for specific deduplicators to learn more about their behavior
    * [USPSA]($uspsaDeduplicatorHelpLink)
    * [ICORE]($icoreDeduplicatorHelpLink)
* Member numbers in green have been addressed by one or more actions
* Click member numbers to view the competitor's classification page (USPSA only)
    * Classification pages will always display a user's highest-priority member number by [USPSA rules]($uspsaDeduplicatorHelpLink),
      and also shows join dates and club information in the classifier scores section,
      which helps to distinguish between one person committing typos and two people with the
      same name.
* Use the edit button in proposed actions to modify the deduplicator's proposed actions
* Use the swap button (↔) when editing proposed actions to quickly switch source and target numbers
* The RESTORE ORIGINAL ACTIONS button will undo any changes to the current duplicate
* Use the BLACKLIST REMAINING button if you have specified all the necessary actions but there are still uncovered numbers
    * It adds blacklist entries for all remaining uncovered numbers to all other numbers, indicating
      to the rating engine that the blacklisted numbers are all distinct competitors
* Use IGNORE sparingly; it should be used primarily to work around deduplicator bugs""";
