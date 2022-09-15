import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';

class EloSettingsController extends RaterSettingsController<EloSettings> with ChangeNotifier {
  EloSettings _currentSettings;

  EloSettings get currentSettings => _currentSettings;
  set currentSettings(EloSettings s) {
    _currentSettings = s;
    notifyListeners();
  }

  EloSettingsController({EloSettings? initialSettings}) :
      _currentSettings = initialSettings != null ? initialSettings : EloSettings();

  @override
  restoreDefaults() {
    currentSettings.restoreDefaults();
    notifyListeners();
  }
}

class EloSettingsWidget extends RaterSettingsWidget<EloSettings, EloSettingsController> {
  EloSettingsWidget({Key? key, required this.controller}) :
        super(key: key, controller: controller);

  final EloSettingsController controller;

  @override
  State<StatefulWidget> createState() {
    return _EloSettingsWidgetState();
  }
}

class _EloSettingsWidgetState extends State<EloSettingsWidget> {
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}