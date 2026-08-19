/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/schema/preferences.dart';

enum WelcomeDialogEntry {
  welcome80,
  welcome80Beta,
  welcome100;

  String get helpId => switch(this) {
    WelcomeDialogEntry.welcome80 => "welcome80",
    WelcomeDialogEntry.welcome80Beta => "welcome80Beta",
    WelcomeDialogEntry.welcome100 => "welcome100",
  };

  String get humanVersion => switch(this) {
    WelcomeDialogEntry.welcome80 => "8.0-alpha",
    WelcomeDialogEntry.welcome80Beta => "8.0-beta",
    WelcomeDialogEntry.welcome100 => "10.0",
  };

  static WelcomeDialogEntry? resolve({
    required bool welcome80,
    required bool welcome80Beta,
    required bool welcome100,
  }) {
    // We're in the 10.0 release cycle, so ignore any 8.x dialogs
    if(!welcome100) return WelcomeDialogEntry.welcome100;

    return null;
  }

  static void markShown(ApplicationPreferences prefs, WelcomeDialogEntry entry) {
    switch(entry) {
      case WelcomeDialogEntry.welcome80: prefs.welcome80Shown = true;
      case WelcomeDialogEntry.welcome80Beta: prefs.welcome80BetaShown = true;
      case WelcomeDialogEntry.welcome100: prefs.welcome100Shown = true;
    };
  }
}