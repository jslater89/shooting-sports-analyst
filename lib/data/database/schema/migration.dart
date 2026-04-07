/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'migration.g.dart';

@collection
class MigrationRecord {
  Id get id => name.stableHash64;

  @Index()
  String name;

  DateTime applied;

  MigrationRecord({
    required this.name,
    required this.applied,
  });
}