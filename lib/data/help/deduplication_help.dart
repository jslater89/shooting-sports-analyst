/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/uspsa_deduplicator_help.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const deduplicationHelpId = "deduplication";
const deduplicationHelpLink = "?deduplication";
final helpDeduplication = HelpTopic(
  id: deduplicationHelpId,
  name: "Deduplication",
  content: _content,
);

const _content =
"# Deduplication\n"
"\n"
"Deduplication is the process of combining match results for competitors who appear under different member numbers. "
"When loading match results, the application automatically detects potential duplicates and presents them for review.\n"
"\n"
"## The Deduplication Dialog\n"
"\n"
"The deduplication dialog shows a list of potential duplicates on the left side. Each entry shows:\n"
"\n"
"* The competitor's name\n"
"* The member numbers involved\n"
"* The type of action proposed (mapping, data fix, etc.)\n"
"* A status icon:\n"
"    * Green check: likely ready to apply, but review is recommended\n"
"    * Yellow question mark: actions proposed, but review and approval are required\n"
"    * Red warning: actions may be proposed, but action edits are almost certainly required\n"
"\n"
"In the main panel, you will find more detail on the conflict (including its causes, and member numbers "
"involved in each cause), a list of known member numbers sorted by their detected categories, and a list "
"of actions the automated deduplicator has proposed (if any). At the bottom right are buttons to approve "
"the proposed resolution, to restore the original resolution, or to ignore the conflict.\n"
"\n"
"A conflict can only be approved if proposed actions cover every member number involved in the conflict. "
"The IGNORE button may be used on yellow conflicts to ignore the conflict for now. It _will_ submit any proposed "
"actions attached to the conflict.\n"
"\n"
"## Action Types\n"
"\n"
"### User Mappings\n"
"User mappings connect multiple valid member numbers that belong to the same competitor. For example, if a competitor "
"has both a standard number (A12345) and a life member number (L789), you can create a mapping to combine their match "
"history.\n"
"\n"
"### Data Entry Fixes\n"
"Data entry fixes correct typos or other errors in member numbers. When a competitor enters an incorrect number, the "
"fix will automatically convert it to the correct number. For example, if John Doe accidentally enters 'A12354' instead "
"of 'A12345', a data entry fix will correct this automatically in future imports.\n"
"\n"
"### Blacklist Entries\n"
"Blacklist entries prevent automatic association between member numbers that belong to different competitors who happen "
"to share the same name. For example, if there are two competitors named John Smith with different member numbers, "
"a blacklist entry prevents their results from being combined.\n"
"\n"
"## Automatic Detection and Manual Review\n"
"\n"
"The application attempts to automatically detect duplicates using several methods:\n"
"\n"
"* Using domain knowledge (e.g., knowing that A12345 and TY12345 represent the same competitor in [USPSA]($uspsaDeduplicatorHelpLink))\n"
"* Single member numbers of each type for a competitor\n"
"* Previously approved mappings from project settings\n"
"\n"
"Some conflicts require manual review, most commonly in scenarios where the system cannot make "
"a confident guess as to the correct solution. Imagine that, for competitor name John Doe, there are "
"four USPSA member numbers: A123456, A654321, L1234, and L4321. The most likely scenario is that there "
"are two distinct John Does, each with one associate and one lifetime number, but the deduplicator has "
"no way of determining which is which. In this case, the deduplicator will mark the conflict with a red "
"warning symbol and require manual review.\n"
"\n"
"When reviewing duplicates:\n"
"\n"
"1. Check the competitor's name and member numbers\n"
"2. Review any proposed automatic actions\n"
"3. Add or modify actions as needed\n"
"4. Click APPROVE when satisfied with the resolution\n"
"\n"
"You must review all red-marked duplicates before proceeding. Yellow-marked duplicates should be reviewed but can "
"be approved without changes if the automatic detection appears correct.\n"
"\n"
"## Tips\n"
"\n"
"* Member numbers in green have been addressed by one or more actions\n"
"* Click member numbers to view the competitor's classification page (USPSA only)\n"
"* Use the edit button in proposed actions to modify the deduplicator's proposed actions\n"
"* Use the swap button (↔️) in proposed actions to quickly switch source and target numbers\n"
"* The RESTORE ORIGINAL ACTIONS button will undo any changes to the current duplicate\n"
"* Use IGNORE sparingly; it should be used primarily to work around deduplicator bugs\n";
