/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/help/entries/about_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/app_settings_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/broadcast_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/configure_ratings_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/elo_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/elo_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/glicko2_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/glicko2_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/invitational_invites_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/latent_log_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/latent_log_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/icore_deduplicator_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/marbles_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/marbles_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_database_manager_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_file_import_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_heat_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_source_chooser_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_divisions_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_predictions_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_rating_links_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_preps/match_prep_squadding_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/match_preps/match_preps_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/openskill_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/points_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_manager_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_players_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_settlement_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_game_wagers_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/prediction_games/prediction_games_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/rating_event_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/rating_reports_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/rating_set_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/ratings/ratings_view_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/recalculation_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/results_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/scalers_and_distributions_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/uspsa_deduplicator_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/welcome_100_help.dart';
import 'package:shooting_sports_analyst/data/help/entries/welcome_80_help.dart';
import 'package:shooting_sports_analyst/data/help/help_directory.dart';
import 'package:shooting_sports_analyst/data/help/help_registry.dart';

void registerHelpTopics() {
  var root = HelpDirectory(
    id: "root",
    name: ""
  );
  HelpTopicRegistry.create(root);
  root.addChild(helpAbout);
  root.addChild(helpBroadcastMode);
  root.addChild(helpWelcome80);
  root.addChild(helpWelcome100);
  root.addChild(helpMatchDatabaseManager);
  root.addChild(helpMatchFileImport);
  root.addChild(helpMatchSourceChooser);
  root.addChild(helpResults);
  root.addChild(helpAppSettings);

  var matchPrepsDir = HelpDirectory(
    id: "matchPrepsDir",
    name: "Match preps",
    defaultTopicId: helpMatchPreps.id,
  );
  matchPrepsDir.addChild(helpMatchPreps);
  matchPrepsDir.addChild(helpMatchPrepRatingLinks);
  matchPrepsDir.addChild(helpMatchPrepSquadding);
  matchPrepsDir.addChild(helpMatchPrepDivisions);
  matchPrepsDir.addChild(helpMatchPrepPredictions);
  root.addChild(matchPrepsDir);

  var predictionGames = HelpDirectory(
    id: "predictionGamesDir",
    name: "Prediction games",
    defaultTopicId: predictionGamesHelpId,
  );
  predictionGames.addChild(helpPredictionGames);
  predictionGames.addChild(helpPredictionGameManager);
  predictionGames.addChild(helpPredictionGamePlayers);
  predictionGames.addChild(helpPredictionGameWagers);
  predictionGames.addChild(helpPredictionGameSettlement);
  root.addChild(predictionGames);

  var deduplication = HelpDirectory(
    id: "deduplicationDir",
    name: "Deduplication",
  );
  deduplication.addChild(helpUspsaDeduplicator);
  deduplication.addChild(helpDeduplication);
  deduplication.addChild(helpIcoreDeduplicator);
  root.addChild(deduplication);

  var ratings = HelpDirectory(
    id: "ratingsDir",
    name: "Ratings",
    defaultTopicId: helpElo.id,
  );
  ratings.addChild(helpConfigureRatings);
  ratings.addChild(helpRatingsView);
  ratings.addChild(helpElo);
  ratings.addChild(helpEloConfig);
  ratings.addChild(helpOpenSkill);
  ratings.addChild(helpPoints);
  ratings.addChild(helpRatingEvent);
  ratings.addChild(helpRatingReports);
  ratings.addChild(helpScalersAndDistributions);
  ratings.addChild(helpMarbles);
  ratings.addChild(helpMarblesConfiguration);
  ratings.addChild(helpRecalculation);
  ratings.addChild(helpRatingSets);
  ratings.addChild(helpGlicko2);
  ratings.addChild(helpGlicko2Config);
  ratings.addChild(helpLatentLog);
  ratings.addChild(helpLatentLogConfig);
  ratings.addChild(helpInvitationalInvites);
  ratings.addChild(helpMatchHeat);

  root.addChild(ratings);
}
