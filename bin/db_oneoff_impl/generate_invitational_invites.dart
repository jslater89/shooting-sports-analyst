/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:io";

import "package:dart_console/src/console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_config.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_engine.dart";

import "base.dart";

class GenerateInvitationalInvitesCommand extends DbOneoffCommand {
  GenerateInvitationalInvitesCommand(super.db);

  @override
  final String key = "GI";
  @override
  final String title = "Generate Invitational Invites";

  @override
  List<MenuArgument> get arguments => [
        StringMenuArgument(
          label: "Config path",
          description: "Path to a TOML config file for invitations",
          required: true,
        ),
      ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue<dynamic>> arguments) async {
    final configPath = arguments[0].value as String;
    final configFile = File(configPath);
    if(!configFile.existsSync()) {
      console.print("Config file does not exist: ${configFile.path}");
      return;
    }

    final parsed = InvitationalInviteConfig.parseToml(configFile.readAsStringSync());
    if(parsed.isErr()) {
      console.print(parsed.unwrapErr().message);
      return;
    }
    final parseResult = parsed.unwrap();
    for(final warning in parseResult.warnings) {
      console.print(warning);
    }

    final config = parseResult.config;
    final String projectName = config.projectName ?? "L2s Main";
    final project = await db.getRatingProjectByName(projectName);
    if(project == null) {
      console.print("Project not found: $projectName");
      return;
    }

    final generated = await InvitationalInviteEngine().generate(
      db: db,
      project: project,
      config: config,
    );
    if(generated.isErr()) {
      console.print(generated.unwrapErr().message);
      return;
    }

    final result = generated.unwrap();
    for(final warning in result.warnings) {
      console.print(warning);
    }

    console.print("Slots by group: ${result.slotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    console.print("Maximum slots by group: ${result.maximumSlotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    console.print("Filled slots by group: ${result.filledSlotsByGroup.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}");
    console.print("Total invitations: ${result.invitations.length}");

    final csvFile = File("/tmp/invitations.csv");
    csvFile.writeAsStringSync(result.toCsv());
    final jsonFile = File("/tmp/invitations.json");
    jsonFile.writeAsStringSync(result.toJsonString());
    console.print("Invitations written to ${csvFile.path} and ${jsonFile.path}");
  }
}
