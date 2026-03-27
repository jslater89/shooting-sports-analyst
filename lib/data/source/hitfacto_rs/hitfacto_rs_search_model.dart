/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";

/// Search + options state for [HitfactoRsMatchSource] download UI.
class HitfactoRsSearchModel extends ChangeNotifier {
  HitfactoRsSearchModel({String? initialSearch}) {
    _search = initialSearch ?? "";
  }

  String _search = "";
  String get search => _search;
  set search(String value) {
    _search = value;
    notifyListeners();
  }

  bool _ignoreUnknownDivisions = false;
  bool get ignoreUnknownDivisions => _ignoreUnknownDivisions;
  set ignoreUnknownDivisions(bool value) {
    _ignoreUnknownDivisions = value;
    notifyListeners();
  }
}
