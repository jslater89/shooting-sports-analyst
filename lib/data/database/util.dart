
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
