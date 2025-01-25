import 'package:flutter_test/flutter_test.dart';

class AlmostEquals extends Matcher {
  final double expected;
  final double tolerance;

  AlmostEquals({required this.expected, required this.tolerance});

  @override
  Description describe(Description description) => 
    description.add("is close to $expected");

  @override
  Description describeMismatch(Object? item, Description mismatchDescription, Map matchState, bool verbose) =>
    mismatchDescription.add("$item is not close to $expected${verbose ? " (within $tolerance)" : ""}");
  
  @override
  bool matches(Object? item, Map matchState) {
    if(!(item is num)) return false;

    return (item - expected).abs() <= tolerance;
  }
}

/// Matches if the value is close to the expected value within the given tolerance.
Matcher almostEquals(double expected, [double tolerance = 0.0000000001]) {
  return AlmostEquals(expected: expected, tolerance: tolerance);
}