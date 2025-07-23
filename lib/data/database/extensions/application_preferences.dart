/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/preferences.dart';

/// An extension on [AnalystDatabase] to get the application preferences.
///
/// Note that many app settings are stored in a config file (see [ConfigLoader]).
/// This extension is used for settings not stored in the config file, such as
/// whether welcome dialogs have been shown, or certain initial state for some
/// UI elements that should be persisted across app restarts, but isn't
extension ApplicationPreferenceStorage on AnalystDatabase {
  ApplicationPreferences getPreferences() => isar.applicationPreferences.getSync(1) ?? ApplicationPreferences();

  void savePreferences(ApplicationPreferences preferences) {
    isar.writeTxnSync(() {
      isar.applicationPreferences.putSync(preferences);
    });
  }
}
