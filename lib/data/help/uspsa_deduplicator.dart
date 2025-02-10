import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const uspsaDeduplicatorHelpId = "uspsa-deduplicator";
const uspsaDeduplicatorHelpLink = "?uspsa-deduplicator";

final helpUspsaDeduplicator = HelpTopic(
  id: uspsaDeduplicatorHelpId,
  name: "USPSA Deduplicator",
  content: _content,
);

const _content =
"# USPSA Deduplicator\n"
"\n"
"The USPSA deduplicator helps manage multiple member numbers that belong to the same competitor. "
"USPSA competitors may have several different types of member numbers:\n"
"\n"
"* Standard numbers (A/TY/FY prefix)\n"
"* Life member numbers (L prefix)\n"
"* Benefactor numbers (B prefix)\n"
"* Region Director numbers (RD prefix)\n"
"\n"
"When importing match results, the deduplicator automatically detects when the same competitor appears with "
"different member numbers and combines their match history. For example, if a competitor appears as both "
"\"A123456\" and \"TY123456\", their results will be merged.\n"
"\n"
"## Manual Actions\n"
"Sometimes the deduplicator needs your help to correctly identify matches. This can happen when:\n"
"\n"
"* A competitor's member number changes entirely (e.g., from an A-number to an L-number)\n"
"* A competitor enters an international number without a prefix\n"
"* There are data entry errors in the match results\n"
"\n"
"Read more about the deduplication UI in the [deduplication help topic](?deduplication).\n"
"\n"
"## Member Number Types\n"
"Member numbers are classified in order of precedence:\n"
"\n"
"1. Region Director (RD)\n"
"2. Benefactor (B)\n"
"3. Life Member (L)\n"
"4. Standard (A/TY/FY)\n"
"5. International\n"
"\n"
"When mapping member numbers, the deduplicator prefers to use the highest-precedence number as the primary "
"identifier for a competitor.\n"
"\n"
"Although there are additional member number types (charter, complimentary, and several others), they are "
"not currently supported.";