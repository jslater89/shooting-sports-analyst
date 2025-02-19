/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/widgets.dart';

abstract class RaterSettings {
  void loadFromJson(Map<String, dynamic> json);
  void encodeToJson(Map<String, dynamic> json);
}

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