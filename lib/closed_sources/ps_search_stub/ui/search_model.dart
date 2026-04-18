/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class SearchModel extends ChangeNotifier {
  SearchModel({String? initialSearch}) {
    _search = initialSearch ?? "";
  }

  String _search = "";
  String get search => _search;
  set search(String search) {
    _search = search;
    notifyListeners();
  }

  Sport? _requestedSport;
  Sport? get requestedSport => _requestedSport;
  set requestedSport(Sport? sport) {
    _requestedSport = sport;
    notifyListeners();
  }

  bool _ignoreUnknownDivisions = false;
  bool get ignoreUnknownDivisions => _ignoreUnknownDivisions;
  set ignoreUnknownDivisions(bool value) {
    _ignoreUnknownDivisions = value;
    notifyListeners();
  }
}
