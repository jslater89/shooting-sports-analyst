

sealed class DeduplicationAction {
  const DeduplicationAction();
}

/// PreexistingMapping is a mapping that has been detected
/// in the project's settings, but not yet applied to the
/// ratings.
class PreexistingMapping extends DeduplicationAction {
  final String sourceNumber;
  final String targetNumber;

  const PreexistingMapping({
    required this.sourceNumber,
    required this.targetNumber,
  });
}

/// AutoMapping is a member number mapping that has been automatically
/// detected, most commonly because there is only one member number of
/// each type.
class AutoMapping extends DeduplicationAction {
  final List<String> sourceNumbers;
  final String targetNumber;

  const AutoMapping({
    required this.sourceNumbers,
    required this.targetNumber,
  });
}

/// Blacklist prevents mapping from a source number to a target
/// number, or in both directions if [bidirectional] is true.
class Blacklist extends DeduplicationAction {
  final String sourceNumber;
  final String targetNumber;

  /// If [bidirectional] is true, then the rating project should add
  /// entries in both directions: blacklist[A123] = B456 and
  /// blacklist[B456] = A123.
  final bool bidirectional;

  const Blacklist({
    required this.sourceNumber,
    required this.targetNumber,
    required this.bidirectional,
  });
}

/// UserMapping manually maps a list of source numbers
/// to a target number.
class UserMapping extends DeduplicationAction {
  final List<String> sourceNumbers;
  final String targetNumber;

  const UserMapping({
    required this.sourceNumbers,
    required this.targetNumber,
  });
}

/// DataEntryFix corrects a typo in member number data
/// entry, treating [sourceNumber] as [targetNumber] when
/// it is entered by a competitor matching [deduplicatorName].
class DataEntryFix extends DeduplicationAction {
  final String sourceNumber;
  final String targetNumber;
  final String deduplicatorName;

  const DataEntryFix({
    required this.sourceNumber,
    required this.targetNumber,
    required this.deduplicatorName,
  });
}
