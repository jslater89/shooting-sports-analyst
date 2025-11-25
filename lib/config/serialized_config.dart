/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:toml/toml.dart';

part 'serialized_config.g.dart';

var _log = SSALogger("Config");

/// ConfigLoader loads and saves the config.toml file, and notifies
/// listeners when the configuration is reloaded.
class ConfigLoader {
  static ConfigLoader? _instance;
  factory ConfigLoader() {
    _instance ??= ConfigLoader._();
    return _instance!;
  }

  /// Internal-only for subclasses. Use the default constructor.
  ConfigLoader.create() {
    _init();
  }

  late SerializedConfig config;
  bool get ready => _readyCompleter.isCompleted;
  Future<void> get readyFuture => _readyCompleter.future;
  Completer<void> _readyCompleter = Completer();

  ConfigLoader._() {
    _init();
  }

  Future<bool> _init() async {
    var result = await reload();
    _readyCompleter.complete();
    return result;
  }

  Future<bool> reload() async {
    File f = File("./config.toml");
    if(!f.existsSync()) {
      f.createSync();
    }
    try {
      var doc = await TomlDocument.load("./config.toml");
      var deserialized = SerializedConfig.fromToml(doc.toMap());
      config = deserialized;
      _log.i("Loaded config: $config");
      return true;
    }
    catch(e, st) {
      print("error loading config: $e $st");
      return false;
    }
  }

  Future<void> save() async {
    var doc = TomlDocument.fromMap(config.toToml());
    var str = await doc.toString();
    File f = File("./config.toml");
    f.writeAsStringSync(str);
    _log.d("Saved config: $config");
  }

  Future<void> setConfig(SerializedConfig config) async {
    this.config = config;
    await save();
  }
}


@JsonSerializable()
class SerializedConfig {
  @JsonKey(defaultValue: Level.debug)
  Level logLevel;

  @JsonKey(defaultValue: true)
  bool playDeduplicationAlert;

  @JsonKey(defaultValue: false)
  bool playRatingsCalculationCompleteAlert;

  @JsonKey(defaultValue: null, includeIfNull: false)
  int? ratingsContextProjectId;

  @JsonKey(defaultValue: "https://parabellum.shootingsportsanalyst.com", includeIfNull: false)
  String ssaServerBaseUrl;

  @JsonKey(defaultValue: "nt+FPpDMvdo9iwpyuNr5rZzs5CLNczhFY7Zcxf2TfD0=", includeIfNull: false)
  String ssaServerX25519PubBase64;

  @JsonKey(defaultValue: "QNr4wVng7Oa2yvMzJRQ2YDGFOsBQbEY3GfSWt2vt+EQ=", includeIfNull: false)
  String ssaServerEd25519PubBase64;

  @JsonKey(defaultValue: null, includeIfNull: false)
  String? autoImportDirectory;

  @JsonKey(defaultValue: false, includeIfNull: false)
  bool autoImportOverwrites;

  @JsonKey(defaultValue: true, includeIfNull: false)
  bool autoImportDeletesAfterImport;

  @JsonKey(defaultValue: true, includeIfNull: false)
  bool autoImportDeletesAfterSkippingOverwrite;

  factory SerializedConfig.fromToml(Map<String, dynamic> json) => _$SerializedConfigFromJson(json);
  Map<String, dynamic> toToml() => _$SerializedConfigToJson(this);

  SerializedConfig({
    required this.logLevel,
    required this.playDeduplicationAlert,
    required this.playRatingsCalculationCompleteAlert,
    required this.ratingsContextProjectId,
    required this.ssaServerBaseUrl,
    required this.ssaServerX25519PubBase64,
    required this.ssaServerEd25519PubBase64,
    required this.autoImportDirectory,
    required this.autoImportOverwrites,
    required this.autoImportDeletesAfterImport,
    required this.autoImportDeletesAfterSkippingOverwrite,
  });

  @override
  String toString() {
    var builder = StringBuffer();
    builder.writeln("Config:");
    builder.writeln("\tlogLevel = ${logLevel.name}");
    builder.writeln("\tplayDeduplicationAlert = $playDeduplicationAlert");
    builder.writeln("\tplayRatingsCalculationCompleteAlert = $playRatingsCalculationCompleteAlert");
    builder.writeln("\tratingsContextProjectId = $ratingsContextProjectId");
    builder.writeln("\tssaServerBaseUrl = $ssaServerBaseUrl");
    builder.writeln("\tssaServerX25519PubBase64 = $ssaServerX25519PubBase64");
    builder.writeln("\tssaServerEd25519PubBase64 = $ssaServerEd25519PubBase64");
    builder.writeln("\tautoImportDirectory = $autoImportDirectory");
    builder.writeln("\tautoImportOverwrites = $autoImportOverwrites");
    builder.writeln("\tautoImportDeletesAfterImport = $autoImportDeletesAfterImport");
    builder.writeln("\tautoImportDeletesAfterSkippingOverwrite = $autoImportDeletesAfterSkippingOverwrite");
    return builder.toString();
  }

  SerializedConfig copy() {
    return SerializedConfig(
      logLevel: logLevel,
      playDeduplicationAlert: playDeduplicationAlert,
      playRatingsCalculationCompleteAlert: playRatingsCalculationCompleteAlert,
      ratingsContextProjectId: ratingsContextProjectId,
      ssaServerBaseUrl: ssaServerBaseUrl,
      ssaServerX25519PubBase64: ssaServerX25519PubBase64,
      ssaServerEd25519PubBase64: ssaServerEd25519PubBase64,
      autoImportDirectory: autoImportDirectory,
      autoImportOverwrites: autoImportOverwrites,
      autoImportDeletesAfterImport: autoImportDeletesAfterImport,
      autoImportDeletesAfterSkippingOverwrite: autoImportDeletesAfterSkippingOverwrite,
    );
  }
}
