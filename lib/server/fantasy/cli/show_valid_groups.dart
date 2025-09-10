/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

Future<void> showValidGroupsForFantasyProject(Console console, List<MenuArgumentValue> arguments) async {
  var db = AnalystDatabase();
  var config = ConfigLoader().config;
  var context = await db.getRatingProjectById(config.ratingsContextProjectId ?? -1);
  if(context == null) {
    console.print("No ratings context found for id ${arguments.first.value}");
    return;
  }
  printValidGroupsTable(console, context);
}

void printValidGroupsTable(Console console, DbRatingProject context) {
    var groups = context.groups;
  var table = Table();
  table.insertColumn(header: "UUID");
  table.insertColumn(header: "Name");
  for(var group in groups) {
    table.insertRow([group.uuid, group.name]);
  }
  console.print("Valid groups for ${context.name}:");
  console.print(table.render());
}
