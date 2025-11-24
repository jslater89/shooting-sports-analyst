import 'package:shooting_sports_analyst/config/serialized_config.dart';

/// This class provides access to a variety of interfaces that are different
/// between Flutter code and Dart-only code. By implementing and filling
class FlutterOrNative {
  static DebugModeProvider? _debugModeProvider;
  static ConfigProvider? _configProvider;
  static MachineFingerprintProvider? _machineFingerprintProvider;

  static DebugModeProvider get debugModeProvider => _debugModeProvider!;
  static set debugModeProvider(DebugModeProvider provider) {
    _debugModeProvider = provider;
  }

  static ConfigProvider get configProvider => _configProvider!;
  static set configProvider(ConfigProvider provider) {
    _configProvider = provider;
  }
  static MachineFingerprintProvider get machineFingerprintProvider => _machineFingerprintProvider!;
  static set machineFingerprintProvider(MachineFingerprintProvider provider) {
    _machineFingerprintProvider = provider;
  }

  static bool check() {
    return _debugModeProvider != null && _configProvider != null && _machineFingerprintProvider != null;
  }
}

abstract interface class DebugModeProvider {
  bool get kDebugMode;
  bool get kReleaseMode;
}

abstract interface class ConfigProvider {
  void addListener(void Function(SerializedConfig config));
  SerializedConfig get currentConfig;
}

abstract interface class MachineFingerprintProvider {
  Future<String> getMachineFingerprint();
}