import 'package:flutter/widgets.dart';

abstract class RaterSettings<T extends RaterSettings<T>> {
  loadFromJson(Map<String, dynamic> json);
  encodeToJson(Map<String, dynamic> json);
}

abstract class RaterSettingsController<T extends RaterSettings<T>> implements ChangeNotifier {
  T get currentSettings;
  set currentSettings(T settings);
  void restoreDefaults();
  void settingsChanged();

  /// Return null if validation is successful, or an error message suitable
  /// for on-screen display if validation fails.
  String? validate();
}

abstract class RaterSettingsWidget<S extends RaterSettings<S>, T extends RaterSettingsController<S>> extends StatefulWidget {
  RaterSettingsWidget({Key? key, required T controller}) : super(key: key);
}