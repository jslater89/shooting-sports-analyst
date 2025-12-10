/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/ui/elo_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/ui/glicko2_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/ui/marble_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/ui/openskill_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/ui/points_settings_ui.dart';

abstract class RatingSystemUi<S extends RaterSettings, C extends RaterSettingsController<S>> {
  /// Return a new instance of a [RaterSettingsController] subclass for
  /// the given rater type, which allows the UI to retrieve settings and
  /// restore defaults.
  RaterSettingsController<S> newSettingsController();

  /// Return a widget tree which can be inserted into a child of a Column
  /// wrapped in a SingleChildScrollView, which implements the settings for this
  /// rating system.
  RaterSettingsWidget<S, C> newSettingsWidget(C controller);

  static RatingSystemUi forAlgorithm(RatingSystem algorithm) {
    if(algorithm is MultiplayerPercentEloRater) {
      return EloSettingsUi();
    }
    else if(algorithm is MarbleRater) {
      return MarbleSettingsUi();
    }
    else if(algorithm is OpenskillRater) {
      return OpenskillSettingsUi();
    }
    else if(algorithm is PointsRater) {
      return PointsSettingsUi();
    }
    else if(algorithm is Glicko2Rater) {
      return Glicko2SettingsUi();
    }

    throw UnimplementedError("Rating system UI not implemented for ${algorithm.runtimeType}");
  }
}
