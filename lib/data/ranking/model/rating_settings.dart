import 'package:flutter/widgets.dart';

abstract class RaterSettings<T extends RaterSettings<T>> {
  loadFromJson(Map<String, dynamic> json);
  encodeToJson(Map<String, dynamic> json);
}

abstract class RaterSettingsController<T extends RaterSettings<T>> {
  T get currentSettings;
  set currentSettings(T settings);
  restoreDefaults();
}

abstract class RaterSettingsWidget<S extends RaterSettings<S>, T extends RaterSettingsController<S>> extends StatefulWidget {
  RaterSettingsWidget({Key? key, required T controller}) : super(key: key);
}