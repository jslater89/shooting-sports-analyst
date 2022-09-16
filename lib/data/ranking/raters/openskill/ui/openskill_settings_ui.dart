import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_settings.dart';

class OpenskillSettingsController extends RaterSettingsController<OpenskillSettings> with ChangeNotifier {
  OpenskillSettings _currentSettings;

  OpenskillSettings get currentSettings => _currentSettings;
  set currentSettings(OpenskillSettings s) {
    _currentSettings = s;
    // notifyListeners();
  }

  OpenskillSettingsController({OpenskillSettings? initialSettings}) :
        _currentSettings = initialSettings != null ? initialSettings : OpenskillSettings();

  @override
  void restoreDefaults() {
    currentSettings.restoreDefaults();
    // notifyListeners();
  }

  @override
  void settingsChanged() {

  }

  @override
  String? validate() {
    return _currentSettings.validate();
  }
}

class OpenskillSettingsWidget extends RaterSettingsWidget<OpenskillSettings, OpenskillSettingsController> {
  OpenskillSettingsWidget({Key? key, required this.controller}) :
        super(key: key, controller: controller);

  final OpenskillSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _OpenskillSettingsWidgetState();
  }
}

class _OpenskillSettingsWidgetState extends State<OpenskillSettingsWidget> {
  @override
  Widget build(BuildContext context) {
    return Text("Not yet implemented");
  }
}