/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system_ui.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_settings.dart';

class Glicko2SettingsUi extends RatingSystemUi<Glicko2Settings, Glicko2SettingsController> {
  @override
  Glicko2SettingsController newSettingsController() {
    return Glicko2SettingsController();
  }

  @override
  Glicko2SettingsWidget newSettingsWidget(Glicko2SettingsController controller) {
    return Glicko2SettingsWidget(controller: controller);
  }
}

class Glicko2SettingsController extends RaterSettingsController<Glicko2Settings> with ChangeNotifier {
  Glicko2Settings _currentSettings = Glicko2Settings();

  String? lastError;

  bool _shouldValidate = false;
  bool _restoreDefaults = false;

  @override
  Glicko2Settings get currentSettings => _currentSettings;
  set currentSettings(Glicko2Settings s) {
    _currentSettings = s;
    notifyListeners();
  }

  @override
  void restoreDefaults() {
    // TODO: implement restoreDefaults
  }

  @override
  void settingsChanged() {
    // TODO: implement settingsChanged
  }

  @override
  String? validate() {
    // TODO: implement validate
    return lastError;
  }
}

class Glicko2SettingsWidget extends RaterSettingsWidget<Glicko2Settings, Glicko2SettingsController> {
  Glicko2SettingsWidget({Key? key, required this.controller}) :
    super(key: key, controller: controller);

  final Glicko2SettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _Glicko2SettingsWidgetState();
  }
}

class _Glicko2SettingsWidgetState extends State<Glicko2SettingsWidget> {
  late Glicko2Settings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.controller._currentSettings;
  }

  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Glicko2 Settings (not yet implemented)"),
      ],
    );
  }
}