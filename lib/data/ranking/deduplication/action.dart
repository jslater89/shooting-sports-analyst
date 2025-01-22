

import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';

sealed class DeduplicationAction {
  const DeduplicationAction();

  Iterable<String> get coveredNumbers;
  DeduplicationAction copy();
  String get descriptiveString;
}

/// PreexistingMapping is a mapping that has been detected
/// in the project's settings, but not yet applied to the
/// ratings.
class PreexistingMapping extends DeduplicationAction {
  final String sourceNumber;
  final String targetNumber;

  /// Whether this mapping was originally automatically
  /// detected. If true, it goes into the automaticNumberMappings
  /// list on the project object; otherwise it goes into
  /// userMemberNumberMappings in the project settings.
  final bool automatic;

  @override
  Iterable<String> get coveredNumbers => [sourceNumber, targetNumber];

  const PreexistingMapping({
    required this.sourceNumber,
    required this.targetNumber,
    required this.automatic,
  });

  @override
  PreexistingMapping copy() => PreexistingMapping(
    sourceNumber: sourceNumber,
    targetNumber: targetNumber,
    automatic: automatic,
  );

  @override
  String get descriptiveString => "Preexisting mapping: $sourceNumber -> $targetNumber";
}

/// AutoMapping is a member number mapping that has been automatically
/// detected, most commonly because there is only one member number of
/// each type.
class AutoMapping extends Mapping {
  final List<String> sourceNumbers;
  final String targetNumber;

  const AutoMapping({
    required this.sourceNumbers,
    required this.targetNumber,
  });

  @override
  AutoMapping copy() => AutoMapping(
    sourceNumbers: [...sourceNumbers],
    targetNumber: targetNumber,
  );

  @override
  String get descriptiveString {
    if(sourceNumbers.length == 1) {
      return "Automatic mapping: ${sourceNumbers.first} → $targetNumber";
    }
    else {
      return "Automatic mapping: (${sourceNumbers.join(", ")}) → $targetNumber";
    }
  }
}

/// Blacklist prevents mapping from a source number to a target
/// number, or in both directions if [bidirectional] is true.
class Blacklist extends DeduplicationAction {
  String sourceNumber;
  String targetNumber;

  @override
  Iterable<String> get coveredNumbers => [sourceNumber, targetNumber];

  /// If [bidirectional] is true, then the rating project should add
  /// entries in both directions: blacklist[A123] = B456 and
  /// blacklist[B456] = A123.
  bool bidirectional;

  Blacklist({
    required this.sourceNumber,
    required this.targetNumber,
    required this.bidirectional,
  });

  @override
  Blacklist copy() => Blacklist(
    sourceNumber: sourceNumber,
    targetNumber: targetNumber,
    bidirectional: bidirectional,
  );

  @override
  String get descriptiveString {
    if(bidirectional) {
      return "Blacklist: $sourceNumber ↔ $targetNumber";
    }
    else {
      return "Blacklist: $sourceNumber → $targetNumber";
    }
  }
}

abstract class Mapping extends DeduplicationAction {
  List<String> get sourceNumbers;
  String get targetNumber;

  @override
  Iterable<String> get coveredNumbers => [...sourceNumbers, targetNumber];

  const Mapping();
}

/// UserMapping manually maps a list of source numbers
/// to a target number.
class UserMapping extends Mapping {
  List<String> sourceNumbers;
  String targetNumber;

  UserMapping({
    required this.sourceNumbers,
    required this.targetNumber,
  });

  @override
  UserMapping copy() => UserMapping(
    sourceNumbers: [...sourceNumbers],
    targetNumber: targetNumber,
  );

  @override
  String get descriptiveString {
    if(sourceNumbers.length == 1) {
      return "User mapping: ${sourceNumbers.first} → $targetNumber";
    }
    else {
      return "User mapping: (${sourceNumbers.join(", ")}) → $targetNumber";
    }
  }
}

/// DataEntryFix corrects a typo in member number data
/// entry, treating [sourceNumber] as [targetNumber] when
/// it is entered by a competitor matching [deduplicatorName].
class DataEntryFix extends DeduplicationAction {
  String sourceNumber;
  String targetNumber;
  final String deduplicatorName;

  @override
  Iterable<String> get coveredNumbers => [sourceNumber, targetNumber];

  DataEntryFix({
    required this.sourceNumber,
    required this.targetNumber,
    required this.deduplicatorName,
  });

  @override
  bool operator ==(Object other) => 
    other is DataEntryFix 
    && sourceNumber == other.sourceNumber 
    && targetNumber == other.targetNumber 
    && deduplicatorName == other.deduplicatorName;

  @override
  int get hashCode => Object.hash(sourceNumber, targetNumber, deduplicatorName);

  @override
  DataEntryFix copy() => DataEntryFix(
    sourceNumber: sourceNumber,
    targetNumber: targetNumber,
    deduplicatorName: deduplicatorName,
  );

  @override
  String get descriptiveString => "Data entry fix: $sourceNumber → $targetNumber for $deduplicatorName";

  MemberNumberCorrection intoCorrection() => MemberNumberCorrection(
    name: deduplicatorName,
    invalidNumber: sourceNumber,
    correctedNumber: targetNumber,
  );
}
