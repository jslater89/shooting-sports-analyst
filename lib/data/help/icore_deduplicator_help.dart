/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const icoreDeduplicatorHelpId = "icore-deduplicator";
const icoreDeduplicatorHelpLink = "?icore-deduplicator";

final helpIcoreDeduplicator = HelpTopic(
  id: icoreDeduplicatorHelpId,
  name: "ICORE deduplicator",
  content: _content,
);

const _content = """# ICORE Deduplicator

The ICORE deduplicator helps detect and resolve cases when multiple member numbers are
associated with the same name in ICORE and ICORE-like sports. For information on the
general deduplication process, see the [deduplication help topic]($deduplicationHelpLink).

## Member Number Types

ICORE member numbers have three components:

* An optional 'L' prefix, which indicates a lifetime membership
* A geographic prefix, either a two-letter US state code or a three-letter country code
* A unique identifier, which is either a sequentially increasing number or a user-selected
  string (in the case of vanity life member numbers)

The ICORE deduplicator treats members as one of three types:

* Standard numbers, which are non-lifetime numbers
* Normal lifetime numbers, which are lifetime numbers with a numeric identifier
* Vanity lifetime numbers, which are lifetime numbers with a user-selected string identifier

## Reviewing Official Data
ICORE classification data is not available to non-members, but ICORE members can [log in](https://icore.org/login) and
use the [active members list](https://icore.org/members-list-active.php) or the
[expired members list](https://icore.org/members-list-expired.php) to look up competitor names by
member numbers, or member numbers by competitor surnames.
""";
