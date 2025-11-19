/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/pcsl.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class SportRegistry {
  static SportRegistry? _instance;
  factory SportRegistry() {
    _instance ??= SportRegistry._([
      uspsaSport,
      ipscSport,
      pcslSport,
      idpaSport,
      icoreSport,
    ]);
    return _instance!;
  }

  late Map<String, Sport> _sportsByName;

  SportRegistry._(List<Sport> sports) {
    _sportsByName = {};
    for(var s in sports) {
      if(_sportsByName.containsKey(s.name)) {
        throw ArgumentError("cannot add multiple sports with the same name");
      }
      _sportsByName[s.name] = s;
    }
  }

  Sport? lookup(String name, {bool caseSensitive = true}) {
    if(caseSensitive) {
      return _sportsByName[name];
    }
    else {
      return _sportsByName.values.firstWhereOrNull((s) => s.name.toLowerCase() == name.toLowerCase());
    }
  }

  List<Sport> get availableSports => _sportsByName.values.toList(growable: false);
}
