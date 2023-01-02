
class UniqueMap<K, V> implements Map<K, V> {
  Map<K, V> _normal = {};
  Map<V, K> _inverse = {};

  UniqueMap._from(this._normal, this._inverse);

  @override
  V? operator [](Object? key) {
    return _normal[key];
  }

  @override
  void operator []=(K key, V value) {
    _normal[key] = value;

    if(_inverse.containsKey(value)) {
      throw ArgumentError("map already contains value $value");
    }
    _inverse[value] = key;
  }

  @override
  void addAll(Map<K, V> other) {
    for(var e in other.entries) {
      _normal[e.key] = e.value;
      if(_inverse.containsKey(e.value)) {
        throw ArgumentError("map already contains value ${e.value}");
      }
      _inverse[e.value] = e.key;
    }
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) {
    for(var e in newEntries) {
      _normal[e.key] = e.value;
      if(_inverse.containsKey(e.value)) {
        throw ArgumentError("map already contains value ${e.value}");
      }
      _inverse[e.value] = e.key;
    }
  }

  @override
  Map<RK, RV> cast<RK, RV>() {
    var n = _normal.cast<RK, RV>();
    var i = _inverse.cast<RV, RK>();

    return UniqueMap<RK, RV>._from(n, i);
  }

  @override
  void clear() {
    _normal.clear();
    _inverse.clear();
  }

  @override
  bool containsKey(Object? key) {
    return _normal.containsKey(key);
  }

  @override
  bool containsValue(Object? value) {
    return _inverse.containsKey(value);
  }

  @override
  Iterable<MapEntry<K, V>> get entries => _normal.entries;

  @override
  void forEach(void Function(K key, V value) action) {
    _normal.forEach(action);
  }

  @override
  bool get isEmpty => _normal.isEmpty;

  @override
  bool get isNotEmpty => _normal.isNotEmpty;

  @override
  Iterable<K> get keys => _normal.keys;

  @override
  int get length => _normal.length;

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(K key, V value) convert) {
    return _normal.map(convert);
  }

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    if(_normal.containsKey(key)) return _normal[key]!;

    var value = ifAbsent();
    _normal[key] = value;
    _inverse[value] = key;

    return value;
  }

  @override
  V? remove(Object? key) {
    var value = _normal.remove(key);
    if(value != null) _inverse.remove(value);

    return value;
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    // TODO: implement removeWhere
    throw UnimplementedError();
  }

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    // TODO: implement updateAll
    throw UnimplementedError();
  }

  @override
  Iterable<V> get values => _normal.values;
}