/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar/isar.dart';

extension LinkUtilities<T> on IsarLinks<T> {
  void empty({bool ensureLoaded = false}) {
    if(ensureLoaded && !isLoaded) {
      load();
    }
    var temp = [...this];
    for(var item in temp) {
      remove(item);
    }
  }

  void setContentsTo(Iterable<T> newContents, {bool ensureLoaded = false}) {
    if(ensureLoaded && !isLoaded) {
      load();
    }
    for(var item in newContents) {
      if(!contains(item)) {
        add(item);
      }
    }
    var toRemove = <T>[]; 
    for(var item in this) {
      if(!newContents.contains(item)) {
        toRemove.add(item);
      }
    }
    for(var item in toRemove) {
      remove(item);
    }
  }
}
