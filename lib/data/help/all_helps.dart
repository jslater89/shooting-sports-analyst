import 'package:shooting_sports_analyst/data/help/about.dart';
import 'package:shooting_sports_analyst/data/help/configure_ratings_help.dart';
import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_help.dart';
import 'package:shooting_sports_analyst/data/help/openskill_help.dart';
import 'package:shooting_sports_analyst/data/help/points_help.dart';
import 'package:shooting_sports_analyst/data/help/rating_event.dart';
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
}