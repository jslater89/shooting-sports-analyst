

sealed class DeduplicationAction {
  const DeduplicationAction();
}

/// Blacklist prevents mapping from a source number to a target
/// number, or in both directions if [bidirectional] is true.
class Blacklist extends DeduplicationAction {
  final String sourceNumber;
  final String targetNumber;
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
