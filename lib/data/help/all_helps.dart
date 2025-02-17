/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/about_help.dart';
import 'package:shooting_sports_analyst/data/help/broadcast_help.dart';
import 'package:shooting_sports_analyst/data/help/configure_ratings_help.dart';
import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_help.dart';
import 'package:shooting_sports_analyst/data/help/openskill_help.dart';
import 'package:shooting_sports_analyst/data/help/points_help.dart';
import 'package:shooting_sports_analyst/data/help/rating_event.dart';
import 'package:shooting_sports_analyst/data/help/rating_reports_help.dart';
import 'package:shooting_sports_analyst/data/help/uspsa_deduplicator_help.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';

void registerHelpTopics() {
  var r = HelpTopicRegistry();
  r.register(helpAbout);
  r.register(helpUspsaDeduplicator);
  r.register(helpDeduplication);
  r.register(helpEloConfig);
  r.register(helpElo);
  r.register(helpOpenSkill);
  r.register(helpPoints);
  r.register(helpRatingEvent);
  r.register(helpConfigureRatings);
  r.register(helpBroadcastMode);
  r.register(helpRatingReports);
}