
abstract class Error {
  String get message;
  const Error();
}

class StringError extends Error {
  final String message;

  const StringError(this.message);
}

// My Rust is showing
class Result<T, E extends Error> {
  final T? _result;
  final E? _error;

  bool isOk() {
    return _result != null;
  }

  bool isErr() {
    return _error != null;
  }

  T unwrap() {
    return _result!;
  }

  E unwrapErr() {
    return _error!;
  }

  Result.ok(T result) : this._result = result, this._error = null;
  Result.err(E error) : this._error = error, this._result = null;
}

List<int> mode(List<int> data) {
  var freq = <int, int>{};
  var maxFreq = 0;

  for(var n in data) {
    freq[n] ??= 0;
    freq[n] = freq[n]! + 1;
    if(freq[n]! > maxFreq) {
      maxFreq = freq[n]!;
    }
  }

  return freq.entries.where((e) => e.value == maxFreq).map((e) => e.key).toList();
}

extension IncrementHistogram<T> on Map<T, int> {
  /// Increase the value of this[key] by 1.
  void increment(T key) {
    addTo(key, 1);
  }

  /// Increase the value of this[key] by [amount].
  void addTo(T key, int amount) {
    var value = this[key] ?? 0;
    value += amount;
    this[key] = value;
  }
}

/// FNV-1a 64bit hash algorithm optimized for Dart Strings
extension StableStringHash on String {
  int get stableHash {
    var hash = 0xcbf29ce484222325;

    var i = 0;
    while (i < length) {
      final codeUnit = codeUnitAt(i++);
      hash ^= codeUnit >> 8;
      hash *= 0x100000001b3;
      hash ^= codeUnit & 0xFF;
      hash *= 0x100000001b3;
    }

    return hash;
  }
}

extension StableIntHash on int {
  int get stableHash {
    var x = ((this >> 16) ^ this) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return x;
  }
}