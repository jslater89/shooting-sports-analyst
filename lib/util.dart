/// FNV-1a 64bit hash algorithm optimized for Dart Strings.
///
/// With regards to the authors of isar.dev.
int fastStringHash(String string) {
  var hash = 0xcbf29ce484222325;

  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }

  return hash;
}

abstract class Error {
  String get message;
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