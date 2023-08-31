import 'package:flutter/foundation.dart';

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
  void increment(T key) {
    var value = this[key] ?? 0;
    value += 1;
    this[key] = value;
  }
}