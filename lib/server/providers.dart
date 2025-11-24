


import 'dart:io';

import 'package:shooting_sports_analyst/config/secure_config.dart';
import 'package:shooting_sports_analyst/config/serialized_config.dart';
import 'package:shooting_sports_analyst/flutter_native_providers.dart';
import 'package:shooting_sports_analyst/logger.dart';

class ServerDebugProvider implements DebugModeProvider {
  @override
  bool get kDebugMode => true;

  @override
  bool get kReleaseMode => false;
}

class ServerConfigProvider implements ConfigProvider {
  ServerConfigProvider(this._config);

  SerializedConfig _config;

  @override
  SerializedConfig get currentConfig => _config;

  @override
  void addListener(void Function(SerializedConfig config) Function) {
    // server configs are read-only
  }
}

/// A read-only secure storage provider that reads from environment variables.
class ServerSecureStorageProvider implements SecureStorageProvider {
  @override
  Future<void> write(String key, String value) async {
    // read-only
  }

  @override
  Future<String?> read(String key) async {
    var envKey = "SSA_${key.toUpperCase()}";
    return Platform.environment[envKey];
  }

  @override
  Future<void> delete(String key) async {
    // read-only
  }
}