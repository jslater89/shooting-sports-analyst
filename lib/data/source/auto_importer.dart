/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:shooting_sports_analyst/api/miff/impl/miff_importer.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/psc/matchdef/match_info_zip.dart';
import 'package:shooting_sports_analyst/data/source/psc/psc_options.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_registration_source.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:watcher/watcher.dart';

var _log = SSALogger("AutoImporter");

class AutoImporter {
  static AutoImporter? _instance;
  factory AutoImporter() {
    if(_instance == null) {
      _instance = AutoImporter._();
    }
    return _instance!;
  }

  AutoImporter._();

  bool _initialized = false;
  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _watcherSubscription;
  late SerializedConfig _config;
  bool get autoImportEnabled => _config.autoImportDirectory != null && Directory(_config.autoImportDirectory!).existsSync();

  Future<void> initialize() async {
    if(_initialized) {
      return;
    }
    _initialized = true;

    _config = FlutterOrNative.configProvider.currentConfig;
    FlutterOrNative.configProvider.addListener((config) {
      _config = config;
      if(!autoImportEnabled) {
        _log.i("Auto import directory not set, disabling auto import");
      }
      else {
        _log.i("Auto import directory set, enabling auto import at ${_config.autoImportDirectory}");
        _watcherSubscription?.cancel();
        _watcher = DirectoryWatcher(Directory(_config.autoImportDirectory!).path);
        _watcherSubscription = _watcher!.events.listen((event) {
          if(autoImportEnabled) {
            _onEvent(event);
          }
        });
      }
    });

    if(_config.autoImportDirectory == null) {
      _log.i("Auto import directory not set, disabling auto import");
      return;
    }
    if(!autoImportEnabled && _config.autoImportDirectory != null) {
      _log.i("Auto import directory not found, creating it: ${_config.autoImportDirectory}");
      Directory(_config.autoImportDirectory!).createSync(recursive: true);
    }
    else if(_config.autoImportDirectory != null) {
      _log.i("Auto import directory ${Directory(_config.autoImportDirectory!).path} found, enabling auto import");
    }

    _watcher = DirectoryWatcher(Directory(_config.autoImportDirectory!).path);
    _watcherSubscription = _watcher!.events.listen((event) {
      if(autoImportEnabled) {
        _onEvent(event);
      }
    });
  }

  Map<String, int> _pathsToSizes = {};
  Map<String, int> _pathsToCheckCounts = {};

  Future<void> _waitForConsistentSize(String path, Future<void> Function() callback) async {
    while(true) {
      var file = File(path);
      if(!file.existsSync()) {
        if((_pathsToCheckCounts[path] ?? 0) > 1) {
          _log.e("Path $path no longer exists but is being checked, giving up");
          _pathsToCheckCounts.remove(path);
          _pathsToSizes.remove(path);
          return;
        }
        _pathsToCheckCounts.increment(path);
        continue;
      }
      var previousSize = _pathsToSizes[path] ?? 0;
      var size = await file.length();
      if(previousSize == size && size > 0) {
        var finalCount = _pathsToCheckCounts.remove(path);
        var finalSize = _pathsToSizes.remove(path);
        _log.i("Path $path has consistent size $finalSize after $finalCount checks, importing");
        callback();
        return;
      }
      _pathsToSizes[path] = size;
      _pathsToCheckCounts.increment(path);
      if((_pathsToCheckCounts[path] ?? 0) >= 25) {
        _log.e("Path $path has not been consistent for 25 checks, giving up");
        _pathsToCheckCounts.remove(path);
        _pathsToSizes.remove(path);
        return;
      }
      await Future.delayed(Duration(seconds: 1));
    }
  }

  Future<void> _importMatch(String path) async {
    ShootingMatch? match;
    if(path.toLowerCase().endsWith(".miff.gz") || path.toLowerCase().endsWith(".miff")) {
      _log.i("Auto import file: $path");
      var file = File(path);
      var bytes = file.readAsBytesSync();
      var importer = MiffImporter();
      var importRes = importer.importMatch(bytes);
      if(importRes.isErr()) {
        _log.e("Error importing match: ${importRes.unwrapErr().message}");
        return;
      }
      match = importRes.unwrap();
    }
    else if(path.toLowerCase().endsWith(".zip") || path.toLowerCase().endsWith(".psc")) {
      _log.i("Auto import zip file: $path");
      var file = File(path);
      var bytes = file.readAsBytesSync();
      try {
        var matchInfoFilesRes = MatchInfoFiles.unzipMatchInfoZip(bytes, useUtf8: true);
        if(matchInfoFilesRes.isErr()) {
          var error = matchInfoFilesRes.unwrapErr();
          _log.e("Error unzipping match info zip: ${error.message} ${error.stackTrace}");
          return;
        }
        var matchInfoFiles = matchInfoFilesRes.unwrap();
        var options = PscMatchFetchOptions(fuzzyHitFactorDivisionMatching: _config.autoImportFuzzyHitFactorDivisionMatching);
        var matchRes = await PSv2MatchSource().getMatchFromInfoFiles(matchInfoFiles, options: options);
        if(matchRes.isErr()) {
          _log.e("Error getting match from info files: ${matchRes.unwrapErr().message}");
          return;
        }
        match = matchRes.unwrap();
      }
      catch(e, stackTrace) {
        _log.i("Zip file is not match info zip: $e", stackTrace: stackTrace);
        return;
      }
    }

    if(match != null) {
      _log.i("Found match in $path: ${match.name}");
      bool shouldSave = false;
      bool shouldDelete = false;
      if(_config.autoImportOverwrites) {
        shouldSave = true;
      }
      else {
        var hasMatch = await AnalystDatabase().hasMatchByAnySourceId(match.sourceIds);
        if(hasMatch) {
          _log.i("Match already exists, skipping import: ${match.name}");
          shouldSave = false;
          shouldDelete = _config.autoImportDeletesAfterSkippingOverwrite;
        }
        else {
          shouldSave = true;
          // delete after succesful save
        }
      }

      if(shouldSave) {
        var saveRes = await AnalystDatabase().saveMatch(match);
        if(saveRes.isErr()) {
          _log.e("Error saving match: ${saveRes.unwrapErr().message}");
          return;
        }
        shouldDelete = _config.autoImportDeletesAfterImport;
        _log.i("Saved match: ${match.name}");
      }

      if(shouldDelete) {
        var importedFile = File(path);
        importedFile.deleteSync();
        _log.i("Deleted detected file: $path");
      }
    }
  }

  Future<void> _handleFileImport(String path) async {
    if(path.endsWith(".miff.gz") || path.endsWith(".miff") || path.endsWith(".psc")) {
      // if the file is a .miff.gz, .miff, or .psc, import it as a match
      _importMatch(path);
    }
    else if(path.endsWith(".riff") || path.endsWith(".riff.gz") || path.endsWith("squadding.zip")) {
      // if the file is a .riff, .riff.gz, or squadding zip, import it as a registration
      _importRegistrations(path);
    }
    else if(path.endsWith(".zip")) {
      // A zip might be either a match info zip or a squadding zip, so peek inside to check
      var file = File(path);
      var bytes = file.readAsBytesSync();
      var zip = ZipDecoder().decodeBytes(bytes);
      bool foundSquadding = false;
      bool foundMatchInfo = false;
      for(var entry in zip) {
        if(entry.name == "squadding.html") {
          foundSquadding = true;
        }
        else if(entry.name == "match_def.json") {
          foundMatchInfo = true;
        }
      }
      if(foundMatchInfo) {
        _importMatch(path);
      }
      else if(foundSquadding) {
        _importRegistrations(path);
      }
      else {
        _log.i("Zip file does not match either squadding or match info: $path");
      }
    }
  }

  static Future<Result<(FutureMatch, List<MatchRegistration>), MatchSourceError>> getFutureMatchFromHtml(
    String registrationHtml, {
    Sport? sportOverride,
    DateTime? dateOverride,
  }) async {
    var metadata = extractRegistrationHtmlMetadata(registrationHtml);

    var matchId = metadata.matchId;
    if(matchId == null || matchId.isEmpty) {
      _log.e("Match ID is unknown, cannot import registrations");
      return Result.err(ParseError("Missing match ID"));
    }
    _log.d("Match ID: $matchId");

    Sport? sport = sportOverride;
    if(sport == null && metadata.sportName != null && metadata.sportName != "unknown") {
      sport = SportRegistry().lookup(metadata.sportName!, caseSensitive: false);
    }
    if(sport == null) {
      _log.e("Sport is unknown, cannot import registrations");
      return Result.err(MatchSourceError.unsupportedMatchType);
    }

    DateTime? date = dateOverride ?? metadata.date;
    if(date == null) {
      _log.e("Match date is unknown, cannot import registrations");
      return Result.err(ParseError("Missing match date"));
    }

    // Pass to parser to get old-style registrations
    // This will cache the HTML, which is sufficient for
    var registrationResult = await getRegistrationsFromHtml(
      registrationHtml: registrationHtml,
      sport: sport,
      matchId: matchId,
      divisions: sport.divisions.values.toList(),
      knownShooters: [],
    );
    if(registrationResult.isErr()) {
      _log.e("Error getting registrations from HTML: ${registrationResult.unwrapErr().message}");
      return Result.err(MatchSourceError.parseError);
    }
    var registrations = registrationResult.unwrap();

    var exportedRegistrations = registrations.exportMatchRegistrations();
    var futureMatch = registrations.exportFutureMatch();
    futureMatch.sportName = sport.name;
    futureMatch.date = date;

    return Result.ok((futureMatch, exportedRegistrations));
  }

  Future<void> _importRegistrations(String path) async {
    var file = File(path);
    var bytes = file.readAsBytesSync();
    var archive = await ZipDecoder().decodeBytes(bytes);
    ArchiveFile? archiveFile;
    for(var f in archive.files) {
      if(f.name == "squadding.html") {
        archiveFile = f;
      }
    }

    if(archiveFile == null) {
      _log.w("Zip file does not contain registration information");
      return;
    }

    var archiveBytes = archiveFile.readBytes();
    var registrationHtml = utf8.decode(archiveBytes ?? []);

    var result = await getFutureMatchFromHtml(registrationHtml);
    if(result.isErr()) {
      _log.e("Error getting future match from zip at $path: ${result.unwrapErr().message}");
      return;
    }
    var (futureMatch, exportedRegistrations) = result.unwrap();

    final previousFutureMatch = await AnalystDatabase().getFutureMatchByMatchId(futureMatch.matchId);
    if(previousFutureMatch != null) {
      await previousFutureMatch.registrations.load();

      Map<String, MatchRegistration> previousRegistrationsById = {};
      Map<String, MatchRegistration> newRegistrationsById = {};
      List<MatchRegistration> manualRegistrations = [];
      for(var registration in previousFutureMatch.registrations) {
        previousRegistrationsById[registration.entryId] = registration;
        if(registration.addedManually) {
          manualRegistrations.add(registration);
        }
      }

      for(var newRegistration in exportedRegistrations) {
        newRegistrationsById[newRegistration.entryId] = newRegistration;
        final previousRegistration = previousRegistrationsById[newRegistration.entryId];
        if(previousRegistration != null) {
          if(!newRegistration.hadMemberNumber && newRegistration.shooterMemberNumbers.isEmpty && previousRegistration.shooterMemberNumbers.isNotEmpty) {
            newRegistration.shooterMemberNumbers = previousRegistration.shooterMemberNumbers;
            newRegistration.resolvedAutomatically = previousRegistration.resolvedAutomatically;
            newRegistration.resolvedFromManualMapping = previousRegistration.resolvedFromManualMapping;
          }
        }
      }

      for(var manualRegistration in manualRegistrations) {
        final newRegistration = newRegistrationsById[manualRegistration.entryId];
        if(newRegistration == null) {
          exportedRegistrations.add(manualRegistration);
        }
        else {
          if(!newRegistration.hadMemberNumber && newRegistration.shooterMemberNumbers.isEmpty && manualRegistration.shooterMemberNumbers.isNotEmpty) {
            newRegistration.shooterMemberNumbers = manualRegistration.shooterMemberNumbers;
            newRegistration.resolvedAutomatically = manualRegistration.resolvedAutomatically;
            newRegistration.resolvedFromManualMapping = manualRegistration.resolvedFromManualMapping;
          }
        }
      }
    }

    // Exported registrations is now a merged copy of old registrations and new.
    var saveRes = await AnalystDatabase().saveFutureMatch(
      futureMatch,
      newRegistrations: exportedRegistrations,
    );
    if(saveRes.isErr()) {
      _log.e("Error saving future match from path $path: ${saveRes.unwrapErr().message}");
      return;
    }

    // TODO: figure out how to handle authorization/deduplication server-side before giving anyone else upload roles
    final serverSource = SSAServerFutureMatchSource();
    if(await serverSource.authenticatedCanUpload()) {
      final uploadRes = await serverSource.uploadMatch(futureMatch);
      if(uploadRes != null) {
        _log.e("Error uploading future match to server: ${uploadRes.message}");
        return;
      }
      _log.i("Uploaded future match to server: ${futureMatch.matchId}");
    }

    // We need to re-apply any saved mappings to the new registrations too.
    await futureMatch.updateRegistrationsFromMappings();

    if(_config.autoImportDeletesAfterImport) {
      // Always overwrites, so no need for complicated logic here
      file.deleteSync();
      _log.i("Deleted detected file: $path");
    }

    _log.i("Saved future match: ${futureMatch.matchId}");
    return;
  }

  Future<void> _onEvent(WatchEvent event) async {
    if(event.type == ChangeType.ADD) {
      var path = event.path;
      if(path.endsWith(".miff.gz") || path.endsWith(".miff") || path.endsWith(".zip") || path.endsWith(".psc")) {
        _waitForConsistentSize(path, () async {
          _handleFileImport(path);
        });
      }
    }
  }
}