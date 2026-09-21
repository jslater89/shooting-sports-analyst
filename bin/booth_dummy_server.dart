/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:io";

import "../test/booth/dummy_ssa_server.dart";

/// Local SSA stand-in for exercising the booth competitor editor with the
/// public auth stub. Does not speak to parabellum.
///
///   dart run bin/booth_dummy_server.dart
///   dart run bin/booth_dummy_server.dart --port 8765
Future<void> main(List<String> args) async {
  var port = 8765;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == "--port" && i + 1 < args.length) {
      port = int.parse(args[i + 1]);
    }
  }

  final server = BoothDummyServer();
  final url = await server.start(port: port, live: true);
  stdout.writeln("Booth dummy SSA listening on $url");
  stdout.writeln("API key: ${BoothDummyServer.apiKey}");
  stdout.writeln("Match: ${BoothDummyServer.matchName} (${BoothDummyServer.matchId})");
  stdout.writeln("Pat Subminor is Subminor on every download. Ada Leader's score moves every 2 seconds.");
  stdout.writeln("");
  stdout.writeln("Point a separate copy of Analyst at it. Do not edit the config next to the Patreon install.");
  stdout.writeln("In that copy's working directory, config.toml needs:");
  stdout.writeln("");
  stdout.writeln('ssaServerBaseUrl = "$url"');
  stdout.writeln('ssaServerStubApiKey = "${BoothDummyServer.apiKey}"');
  stdout.writeln("");
  stdout.writeln('Search SSA Server for "booth", open the match, and start a broadcast.');
  stdout.writeln("Set the ticker interval to a few seconds, or press refresh.");
  stdout.writeln("Long-press Pat Subminor, set power factor to Minor, and refresh again.");
  stdout.writeln("He should keep scoring as Minor while Ada's hits keep changing.");
}
