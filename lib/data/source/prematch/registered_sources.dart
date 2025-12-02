/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/source/ssa_source/ssa_server_registration_source.dart';

class FutureMatchSourceRegistry {
  static FutureMatchSourceRegistry? _instance;
  factory FutureMatchSourceRegistry() {
    if(_instance == null) {
      _instance = FutureMatchSourceRegistry._();
      for(var source in _instance!._sources) {
        if(source is SSAServerFutureMatchSource) {
          source.initialize();
        }
      }
    }
    return _instance!;
  }

  FutureMatchSourceRegistry._();

  List<FutureMatchSource> _sources = [
    SSAServerFutureMatchSource(),
  ];
  List<FutureMatchSource> get sources => _sources.where((e) => e.isImplemented).toList(growable: false);
}

