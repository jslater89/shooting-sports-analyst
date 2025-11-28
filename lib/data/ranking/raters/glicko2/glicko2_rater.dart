/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';

///
class Glicko2Rater extends RatingSystem<Glicko2Rating, Glicko2Settings> {
  Glicko2Rater({required this.settings});

  final Glicko2Settings settings;
}
