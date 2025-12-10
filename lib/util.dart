/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

final DateFormat programmerYmdFormat = DateFormat("yyyy-MM-dd");
final DateFormat programmerYmdHmFormat = DateFormat("yyyy-MM-dd HH:mm");

/// A zero date for practical shooting matches, used to indicate that a date is not
/// known.
///
/// It is the date of the Columbia Conference, which established IPSC as a sport.
final practicalShootingZeroDate = DateTime(1976, 5, 24);

typedef VoidResult = Result<void, ResultErr>;

abstract class ResultErr {
  String get message;
  const ResultErr();
}

class NativeError extends ResultErr {
  String get message => "$e";
  Error e;
  NativeError(this.e);

  static Result<T, NativeError> result<T>(Error e) {
    return Result.err(NativeError(e));
  }

  @override
  String toString() {
    return "NativeError: $e";
  }
}

class NativeException extends ResultErr {
  String get message => "$e";
  Exception e;
  NativeException(this.e);

  static Result<T, NativeException> result<T>(Exception e) {
    return Result.err(NativeException(e));
  }
}

class StringError extends ResultErr {
  final String message;

  const StringError(this.message);

  static Result<T, StringError> result<T>(String message) {
    return Result.err(StringError(message));
  }

  @override
  String toString() {
    return "$message";
  }
}

typedef Nullable<T> = T?;

// My Rust is showing
class Result<T, E extends ResultErr> {
  bool _ok;
  final T? _result;
  final E? _error;

  bool isOk() {
    return _ok;
  }

  bool isErr() {
    return !_ok;
  }

  T unwrap() {
    if(T == Nullable<T>) {
      return _result as T;
    }
    return _result!;
  }

  E unwrapErr() {
    return _error!;
  }

  Result.ok(T result) : this._result = result, this._error = null, this._ok = true;
  Result.err(E error) : this._error = error, this._result = null, this._ok = false;
  Result.errFrom(Result<Object?, E> other) : this._error = other.unwrapErr(), this._result = null, this._ok = false;

  @override
  String toString() {
    if(isOk()) {
      return "Ok(${unwrap().toString()})";
    }
    return "Err(${unwrapErr().toString()})";
  }
}

extension AsyncResult<T, E extends ResultErr> on Future<Result<T, E>> {
  /// Await this Future<Result> and check if it is ok.
  Future<bool> isOk() async {
    var res = await this;
    return res.isOk();
  }

  /// Await this Future<Result> and check if it is an error.
  Future<bool> isErr() async {
    var res = await this;
    return res.isErr();
  }

  /// Await this Future<Result> and unwrap the result.
  Future<T> unwrap() async {
    var res = await this;
    return res.unwrap();
  }

  /// Await this Future<Result> and unwrap the error.
  Future<E> unwrapErr() async {
    var res = await this;
    return res.unwrapErr();
  }
}

extension AddIfMissing<T> on List<T> {
  void addIfMissing(T value) {
    if(!this.contains(value)) {
      this.add(value);
    }
  }

  List<T> removeDuplicates() {
    return this.toSet().toList();
  }

  void addAllIfMissing(Iterable<T> values) {
    for(var value in values) {
      addIfMissing(value);
    }
  }
}

extension ListStatistics<T extends Comparable> on List<T> {
  T get median {
    if(this.isEmpty) throw ArgumentError("empty list");

    late List<T> sorted;
    if(this.isSorted((a, b) => a.compareTo(b))) {
      sorted = this;
    }
    else {
      sorted = this.sorted((a, b) => a.compareTo(b));
    }

    return sorted[sorted.length ~/ 2];
  }
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
  /// Increase the value of [key] in this map by 1, adding the key
  /// to the map first if needed.
  void increment(T key) {
    incrementBy(key, 1);
  }

  /// Increase the value of [key] in this map by [amount], adding the key
  /// to the map first if needed.
  void incrementBy(T key, int amount) {
    var value = this[key] ?? 0;
    value += amount;
    this[key] = value;
  }
}

extension IncrementDoubleMap<T> on Map<T, double> {
  /// Increase the value of [key] in this map by [amount], adding the key
  /// to the map first if needed.
  void incrementBy(T key, double amount) {
    var value = this[key] ?? 0;
    value += amount;
    this[key] = value;
  }
}

extension ListMap<K, V> on Map<K, List<V>> {
  /// Add [value] to the list at [key], creating the list if it doesn't exist.
  void addToList(K key, V value) {
    this[key] ??= [];
    var list = this[key]!;
    list.add(value);
  }

  /// Add [value] to the list at [key], but only if it is not already in the list,
  /// creating the list if the list does not exist.
  ///
  /// Returns true if the value was added, or false if it was already in the list.
  bool addToListIfMissing(K key, V value) {
    if(this[key]?.contains(value) ?? false) {
      return false;
    }
    addToList(key, value);
    return true;
  }

  bool removeFromList(K key, V value) {
    var list = this[key];
    if(list == null) {
      return false;
    }
    return list.remove(value);
  }
}

extension SetMap<K, V> on Map<K, Set<V>> {
  /// Add [value] to the set at [key], creating the set if it doesn't exist.
  void addToSet(K key, V value) {
    this[key] ??= {};
    var set = this[key]!;
    set.add(value);
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

/// Combine two hashes into a new hash, in a way that
/// will not change over app runs or Flutter releases
/// and can therefore be used in the database as a key.
int combineHashes(int hash, int value) {
  hash = 0x1fffffff & (hash + value);
  hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
  return hash ^ (hash >> 6);
}

/// Combine a list of hashes into a new hash, in a way that
/// will not change over app runs or Flutter releases
/// and can therefore be used in the database as a key.
///
/// This is a non-commutative operation, so the order of the hashes matters.
int combineHashList(List<int> hashes) {
  return hashes.fold(0, combineHashes);
}

extension AsPercentage on double {
  /// Show the double as a percentage with [decimals] decimal places.
  /// If [decimals] is 0, the percentage is shown without a decimal point.
  /// If [includePercent] is true, the percentage is shown with a percent sign.
  String asPercentage({int decimals = 2, bool includePercent = false}) {
    if(decimals == 0) {
      return "${(this * 100).round()}${includePercent ? "%" : ""}";
    }
    return "${(this * 100).toStringAsFixed(decimals)}${includePercent ? "%" : ""}";
  }
}

/// A callback used by long-running synchronous processes to allow UI updates
/// and progress display. If UI updates are desired, ProgressCallback should
/// await Future.delayed (or some other async task) to allow the task queue
/// to cycle.
typedef ProgressCallback = Future<void> Function(int progress, int total);

extension SanitizeFilename on String {
  String safeFilename({String replacement = ''}) {
    final result = this.toLowerCase()
        .replaceAll(RegExp(r'\s'), "-"
    )
    // illegalRe
        .replaceAll(
      RegExp(r'[/?<>\\:*|"]'),
      replacement,
    )
        .replaceAll(r"'",
        replacement
    )
    // controlRe
        .replaceAll(
      RegExp(
        r'[\x00-\x1f\x80-\x9f]',
      ),
      replacement,
    )
    // reservedRe
        .replaceFirst(
      RegExp(r'^\.+$'),
      replacement,
    )
    // windowsReservedRe
        .replaceFirst(
      RegExp(
        r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
        caseSensitive: false,
      ),
      replacement,
    )
    // windowsTrailingRe
        .replaceFirst(RegExp(r'[. ]+$'), replacement);

    return result.length > 255 ? result.substring(0, 255) : result;
  }
}

String yMdHm(DateTime date) {
  return DateFormat.yMd().format(date) + " " + DateFormat.Hm().format(date);
}

extension ListOverlap<T> on Iterable<T> {
  Iterable<T> intersection(Iterable<T> other) {
    return this.where((e) => other.contains(e));
  }

  bool intersects(Iterable<T> other) {
    return this.any((e) => other.contains(e));
  }

  bool containsAll(Iterable<T> other) {
    return other.every((e) => this.contains(e));
  }

  bool containsOnly(Iterable<T> other) {
    var intersectionLength = this.intersection(other).length;
    return intersectionLength == this.length && intersectionLength == other.length;
  }

  Iterable<T> union(Iterable<T> other) {
    return {...this, ...other};
  }
}

extension Interleave<T> on List<T> {
  List<T> interleave(List<T> other) {
    if(other.length != length && other.length != length - 1) {
      throw ArgumentError("other must have the same length as this, or one less");
    }

    var result = <T>[];
    for(var i = 0; i < length; i++) {
      result.add(this[i]);
      if(i < other.length) {
        result.add(other[i]);
      }
    }

    return result;
  }
}

extension WindowedList<T> on List<T> {
  /// Get a windowed view into the list, optionally offset by [offset],
  /// starting at the head of the list.
  List<T> getWindow(int window, {int offset = 0}) {
    if(offset + window > length) return this;
    return sublist(offset, offset + window);
  }

  /// Get a windowed view into the list, starting at the tail of the list,
  /// optionally offset by [offset].
  List<T> getTailWindow(int window, {int offset = 0}) {
    if(offset + window > length) return this;
    return sublist(length - window - offset, length - offset);
  }
}

/// Linearly interpolate between [minOut], [centerOut], and [maxOut], based on
/// [value] relative to [center], using [centerMinFactor] and [centerMaxFactor]
/// to determine the range. If [rangeMin] and [rangeMax] are provided, the
/// interpolation is done between [rangeMin] and [rangeMax] instead of
/// [centerMinFactor] * [center] and [centerMaxFactor] * [center]. The [center]
/// and factors approach is preferred, but cannot be used when [center] is zero.
///
/// When [value] <= [centerMinFactor] * [center], the result is [minOut].
///
/// Between [centerMinFactor] * [center] and [center], the result is linearly
/// interpolated between [minOut] and [centerOut].
///
/// When [value] equals [center], the result is [centerOut].
///
/// When [value] is between [center] and [centerMaxFactor] * [center], the result
/// is linearly interpolated between [centerOut] and [maxOut].
///
/// When [value] >= [centerMaxFactor] * [center], the result is [maxOut].
double lerpAroundCenter({
  required double value,
  required double center,
  double? rangeMin,
  double? rangeMax,
  double centerMinFactor = 0.5,
  double centerMaxFactor = 2.0,
  double minOut = 0.5,
  double centerOut = 1.0,
  double maxOut = 2.0,
}) {
  var bottom = center * centerMinFactor;
  var top = center * centerMaxFactor;
  if(center == 0) {
    if(rangeMin == null || rangeMax == null) {
      throw ArgumentError("center cannot be zero if rangeMin or rangeMax is not provided");
    }
    bottom = rangeMin;
    top = rangeMax;
  }
  else if(rangeMin != null && rangeMax != null) {
    bottom = rangeMin;
    top = rangeMax;
  }

  if(value <= bottom) return minOut;
  if(value >= top) return maxOut;

  // if value is greater than or equal to center, scale up from centerOut to maxOut
  if(value >= center) {
    var range = maxOut - centerOut;
    var scale = (value - center) / (top - center);
    return centerOut + range * scale;
  }
  // if value is less than center, scale down from centerOut to minOut
  else {
    var range = centerOut - minOut;
    var scale = (center - value) / (center - bottom);
    return centerOut - range * scale;
  }
}

extension Clamp on num {
  num clamp(num min, num max) {
    if(this < min) return min;
    if(this > max) return max;
    return this;
  }
}

extension FloatEqual on num {
  bool floatEqual(num other, {num epsilon = 1e-10}) {
    return (this - other).abs() < epsilon;
  }
}

extension SignificantDigits on double {
  /// Return a string representation of this number with approximately [digits] significant
  /// digits.
  ///
  /// Internally, this returns a value with x digits in front of the decimal point and y
  /// digits after it, where x + y = [digits], or where y = 0 and x >= [digits].
  String toStringWithSignificantDigits(int digits) {
    var wholeNumberLength = this.floor().toString().length;
    var decimalPlaces = digits - wholeNumberLength;
    if(decimalPlaces <= 0) {
      return this.round().toString();
    }
    return this.toStringAsFixed(decimalPlaces);
  }
}

extension TitleCase on String {
  String toTitleCase() {
    return this.split(" ").map((e) => e.substring(0, 1).toUpperCase() + e.substring(1)).join(" ");
  }
}


/// Extension to add Gaussian random number generation
extension RandomGaussian on Random {
  /// Generate a random number from a standard normal distribution.
  double nextGaussian() {
    // Box-Muller transform
    var u1 = nextDouble();
    var u2 = nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// Generate a random number from a Gaussian distribution with specified parameters.
  double nextGaussianWithParams({double mu = 0.0, double sigma = 1.0}) {
    return mu + sigma * nextGaussian();
  }

  List<double> generateGaussianWithParams(int n, {double mu = 0.0, double sigma = 1.0}) {
    return List.generate(n, (index) => nextGaussianWithParams(mu: mu, sigma: sigma));
  }
}

extension RandomMesa on Random {
  /// Generate a random number from a "mesa" distribution (mixture of two normals)
  /// Creates a flatter peak than normal distribution while keeping similar tails
  double nextMesa({double weight = 0.7, double narrowStd = 0.5, double wideStd = 1.5}) {
    if (nextDouble() < weight) {
      // Narrow normal (70% of the time)
      return nextGaussianWithParams(mu: 0.0, sigma: narrowStd);
    } else {
      // Wide normal (30% of the time)
      return nextGaussianWithParams(mu: 0.0, sigma: wideStd);
    }
  }
}

/// Extension to add Laplace random number generation
  extension RandomLaplace on Random {
  /// Generate a random number from a standard Laplace distribution (mu=0, b=1).
  double nextLaplace() {
    var u = nextDouble();
    // Use the inverse transform method more carefully
    if (u < 0.5) {
      return log(2 * u);
    } else {
      return -log(2 * (1 - u));
    }
  }

  /// Generate a random number from a Laplace distribution with specified parameters.
  double nextLaplaceWithParams({double mu = 0.0, double b = 1.0}) {
    return mu + b * nextLaplace();
  }
}

/// Extension to add shifted normal distribution generation
extension RandomShiftedNormal on Random {
  /// Generate a random number from a normal distribution with mode shifted based on ciOffset.
  ///
  /// - ciOffset < 0: Mode shifted left (peak below 0)
  /// - ciOffset > 0: Mode shifted right (peak above 0)
  /// - ciOffset = 0: Standard normal (peak at 0)
  double nextShiftedNormal({double ciOffset = 0.0, double sigma = 1.0}) {
    // Generate standard normal sample
    var sample = nextGaussian();

    // Shift the mode based on ciOffset
    // Map ciOffset (-1 to 1) to a shift amount (-0.5 to 0.5)
    // This keeps the distribution centered around 0 but shifts the peak
    var modeShift = ciOffset * 0.5;
    sample = sample + modeShift;

    // Scale by sigma to match the original Gaussian behavior
    return sigma * sample;
  }
}


extension PlaceSuffix on int {
  String get ordinalPlace {
    var string = this.toString();
    if(string.endsWith("11") || string.endsWith("12") || string.endsWith("13")) {
      return "${string}th";
    }
    var lastCodeUnit = string.codeUnits.last;
    var character = String.fromCharCode(lastCodeUnit);
    switch(character) {
      case "1": return "${string}st";
      case "2": return "${string}nd";
      case "3": return "${string}rd";
    }
    return "${string}th";
  }
}

extension AsExtension on Object? {
  /// Cast this object to [X].
  X as<X>() => this as X;

  /// Cast this object to [X], or return null if it is not of type [X].
  X? asOrNull<X>() {
    var self = this;
    return self is X ? self : null;
  }
}

extension AsSubtypeExtension<X> on X {
  /// Cast this object to [Y], which is a subtype of [X].
  Y asSubtype<Y extends X>() => this as Y;
}

extension AsNotNullExtension<X> on X? {
  /// Cast this object to [X], or throw an error if it is null.
  X asNotNull() => this as X;
}

extension ListWeightedAverage on List<num> {
  double weightedAverage(List<double> weights) {
    if(length != weights.length) {
      throw ArgumentError("length of list and weights must be the same");
    }
    var sum = 0.0;
    var weightSum = 0.0;
    for(var i = 0; i < length; i++) {
      sum += this[i] * weights[i];
      weightSum += weights[i];
    }
    return sum / weightSum;
  }
}

extension IterableWeightedAverage on Iterable<num> {
  double weightedAverage(List<double> weights) {
    var thisList = this.toList();
    return thisList.weightedAverage(weights);
  }
}

extension NextBytes on Random {
  List<int> nextBytes(int length) {
    return List.generate(length, (index) => nextInt(256));
  }
}

extension SecondTimestampUtils on int {
  DateTime toDateTime() {
    return DateTime.fromMillisecondsSinceEpoch(this * 1000);
  }

  bool isSameDay(DateTime date) {
    final thisDate = this.toDateTime();
    return thisDate.year == date.year && thisDate.month == date.month && thisDate.day == date.day;
  }
}