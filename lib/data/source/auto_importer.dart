import 'dart:io';

import 'package:shooting_sports_analyst/api/miff/impl/miff_importer.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/matchdef/match_info_zip.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';
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
  late DirectoryWatcher _watcher;
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
        _log.i("Auto import directory set, enabling auto import");
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
    _watcher.events.listen((event) {
      if(autoImportEnabled) {
        _onEvent(event);
      }
    });

  }

  Future<void> _onEvent(WatchEvent event) async {
    if(event.type == ChangeType.ADD) {
      var path = event.path;
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
          var matchInfoFilesRes = MatchInfoFiles.unzipMatchInfoZip(bytes);
          if(matchInfoFilesRes.isErr()) {
            var error = matchInfoFilesRes.unwrapErr();
            _log.e("Error unzipping match info zip: ${error.message} ${error.stackTrace}");
            return;
          }
          var matchInfoFiles = matchInfoFilesRes.unwrap();
          var matchRes = await PSv2MatchSource().getMatchFromInfoFiles(matchInfoFiles);
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
          _log.i("Deleted imported file: $path");
        }
      }
    }
  }
}