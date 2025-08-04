

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';

abstract class RaterSettingsController<T extends RaterSettings> implements ChangeNotifier {
  T get currentSettings;
  set currentSettings(covariant T settings);
  void restoreDefaults();
  void settingsChanged();

  /// Return null if validation is successful, or an error message suitable
  /// for on-screen display if validation fails.
  String? validate();
}

abstract class RaterSettingsWidget<S extends RaterSettings, T extends RaterSettingsController<S>> extends StatefulWidget {
  /// Unless [key] is provided, it will change whenever [controller] changes.
  RaterSettingsWidget({Key? key, required T controller}) : super(key: key ?? Key(controller.hashCode.toString()));
}
