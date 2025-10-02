/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const ratingSetsHelpId = "rating_sets";
const ratingSetsHelpLink = "?rating_sets";
final helpRatingSets = HelpTopic(
  id: ratingSetsHelpId,
  name: "Rating sets",
  content: _content,
);

const _content = """# Rating sets

Rating sets are collections of competitors that can be used to filter the ratings display
to a group of interest. Multiple rating sets can be applied at once. Displayed ratings will
include all ratings that match any of the rating sets.
""";
