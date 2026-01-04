/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/server/user.dart';

part 'prediction_user.g.dart';

@collection
class PredictionGameUser {
  Id id = Isar.autoIncrement;

  @Backlink(to: 'predictionGameUser')
  final serverUser = IsarLink<User>();
}