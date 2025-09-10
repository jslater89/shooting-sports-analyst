/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

enum FantasyPointsMode {
  off,
  byDivision,
  currentFilters;

  String get uiLabel => switch(this) {
    off => "Off",
    byDivision => "By division",
    currentFilters => "Current filters",
  };
}
