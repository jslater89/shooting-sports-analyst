import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const uspsaDeduplicatorHelpId = "uspsa-deduplicator";
const uspsaDeduplicatorHelpLink = "?uspsa-deduplicator";

final helpUspsaDeduplicator = HelpTopic(
  id: uspsaDeduplicatorHelpId,
  name: "USPSA deduplicator",
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
"## Member Number Links\n"
"\n"
"When viewing a deduplication conflict, competitor member numbers are hyperlinked to the competitor's "
"classification page at the USPSA website. Since classification pages always display the user's 'best' "
"member number, clicking the link for an associate member number in, for instance, a proposed mapping "
"from associate to lifetime will show whether the mapping is correct.\n"
"\n"
"## Manual Actions\n"
"\n"
"Sometimes the deduplicator needs your help to correctly identify matches. You can read about the basic cases and UI "
"in the [deduplication help topic]($deduplicationHelpLink). Specific to the USPSA deduplicator, this happens most commonly "
"in scenarios where a competitor's member number type changes category, or when distinct competitors with the same "
"name appear in the result set.\n"
"\n"
"## Member Number Types\n"
"\n"
"Member numbers are classified in order of precedence:\n"
"\n"
"1. Region Director (RD)\n"
"2. Benefactor (B)\n"
"3. Life Member (L)\n"
"4. Standard (A/TY/FY)\n"
"5. International or unknown\n"
"\n"
"When mapping member numbers, the deduplicator prefers to use the highest-precedence number as the primary "
"identifier for a competitor.\n"
"\n"
"Although there are additional member number types (charter, complimentary, and several others), they are "
"not currently supported.";