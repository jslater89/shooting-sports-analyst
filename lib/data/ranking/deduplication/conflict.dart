/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';

import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;

/// A conflict is a potential discrepancy in competitor information that
/// may require manual action to resolve.
class DeduplicationCollision {
  /// The deduplicator name is the processed (alphabetic only, no punctuation or spaces, all lowercase)
  /// name that has multiple member numbers/shooter ratings.
  String deduplicatorName;
  /// The member numbers that have been identified as conflicting in some way.
  Map<MemberNumberType, List<String>> memberNumbers;
  List<String> get flattenedMemberNumbers => memberNumbers.values.flattened.toList();
  /// The shooter ratings corresponding to the member numbers.
  Map<String, DbShooterRating> shooterRatings;
  /// Up to the last five matches where each member number appears.
  // TODO: maybe we load this in the UI when people are reviewing, for speed reasons?
  Map<String, List<DbShootingMatch>> matches;

  /// The causes of the conflict. In the case where we can automap (at most one member number
  /// of each type), this will be empty.
  List<ConflictType> causes;
  /// Proposed actions to resolve the conflict.
  List<DeduplicationAction> proposedActions;

  /// True if the proposed fixes involve all of the given numbers.
  bool coversNumbers(Iterable<String> numbers) {
    return numbers.every((n) => coversNumber(n));
  }

  /// True if the proposed fixes cover the given number.
  bool coversNumber(String number) {
    return proposedActions.any((a) => a.coveredNumbers.contains(number));
  }

  bool proposedActionsResolveConflict() {
    return coversNumbers(memberNumbers.values.flattened);
  }

  Iterable<String> get coveredNumbers => proposedActions.expand((a) => a.coveredNumbers);
  List<String> get coveredNumbersList => coveredNumbers.toList();
  Iterable<String> get uncoveredNumbers {
    var coveredList = coveredNumbersList;
    return memberNumbers.values.flattened.where((n) => !coveredList.contains(n));
  }
  List<String> get uncoveredNumbersList => uncoveredNumbers.toList();

  DeduplicationCollision({
    required this.deduplicatorName,
    required this.memberNumbers,
    required this.shooterRatings,
    required this.causes,
    required this.matches,
    List<DeduplicationAction>? proposedActions,
  }) : proposedActions = proposedActions ?? [];
}

/// Conflicts are member number collisions that can be detected, but not
/// resolved with high confidence.
sealed class ConflictType {
  const ConflictType();

  bool get canResolveAutomatically => false;
}

/// A conflict or conflict(s) that has already been resolved in the project settings
/// by user mappings or previous runs of a deduplicator (i.e., during a full recalculation
/// but after at least one full calculation has been run). All actions in a [Conflict] with
/// one [ConflictType] of this type should be applied automatically before presenting the
/// conflict to the user.
class FixedInSettings extends ConflictType {
  bool get canResolveAutomatically => true;

  const FixedInSettings();
}

/// An automatic mapping or data entry fix has been proposed, but the user should review
/// the proposed actions before applying them, because heuristic detection may be
/// unreliable.
/// 
/// A conflict with this type should always be presented to the user in a 'review this'
/// fashion.
class ManualReviewRecommended extends ConflictType {
  bool get canResolveAutomatically => false;

  const ManualReviewRecommended();
}

/// In multiple-numbers-of-type conflicts, one deduplicator name has
/// multiple member numbers of the same type ([memberNumberType]).
/// 
/// The [memberNumbers] list contains all the member numbers of the
/// given type. [stringDifference] is the string difference between
/// the two member numbers, if there are exactly two. [probableTypo]
/// is true if there are exactly two member numbers and they are
/// fairly similar (by a fuzzy string comparison).
class MultipleNumbersOfType extends ConflictType {
  final String deduplicatorName;
  final MemberNumberType memberNumberType;
  final List<String> memberNumbers;
  final List<String> probablyInvalidNumbers;


  /// If there are exactly two member numbers, the string difference between
  /// them (0 for totally dissimilar, 100 for identical).
  int get stringDifference {
    if(memberNumbers.length == 2) {
      return fuzzywuzzy.weightedRatio(memberNumbers[0], memberNumbers[1]);
    }
    return 0;
  }
  bool get probableTypo => stringDifference > 50;

  /// It's much easier to be confident in blacklists than in typos:
  /// blacklists are bidirectional, and we can more readily assume that
  /// John Doe [A52362, TY131849] refer to different people, rather than
  /// trying to figure out which number between A52362 and A53262 is the
  /// one John Doe meant.
  ///
  /// Assume we can resolve automatically if it's an obvious blacklist,
  /// or if we have N-1 probably-invalid numbers out of N total.
  @override
  bool get canResolveAutomatically => !probableTypo || (probablyInvalidNumbers.length == memberNumbers.length - 1);

  const MultipleNumbersOfType({
    required this.deduplicatorName,
    required this.memberNumberType,
    required this.memberNumbers,
    required this.probablyInvalidNumbers,
  });
}

/// In ambiguous mappings, member numbers of a lower-priority type
/// cannot be mapped to member numbers of a higher-priority type,
/// because there are at least two member numbers of at least one
/// of the types.
/// 
/// [sourceConflicts] and [targetConflicts] indicate whether the
/// source numbers or target numbers caused the conflict. [conflictingTypes]
/// indicates the type of the conflicting member numbers.
///
/// The list of target member numbers guarantees that all its
/// member numbers are of the same type. The source member numbers
/// may be of different types.
/// 
/// [relevantBlacklistEntries] is a filtered view of the project's blacklist
/// that includes only entries relevant to this conflict: any blacklist targets
/// for blacklist entries for the conflict sources that match the conflict targets
/// or sources.
/// 
/// e.g.
/// 
/// Source:    Target:
///  A12345     L1234
///  A67890
/// 
/// deduplicatorName: "johndoe"
/// sourceConflicts: true, targetConflicts: false
/// conflictingTypes: [associate]
/// 
/// Source:    Target:
///  A12345     L1234
///  A67890     L5678
/// 
/// deduplicatorName: "johndoe"
/// sourceConflicts: true, targetConflicts: true
/// conflictingTypes: [associate, lifetime]
/// 
/// Source:    Target:
///  A12345     B123
///  A67890     B456
///  L1234
/// 
/// deduplicatorName: "johndoe"
/// sourceConflicts: true, targetConflicts: true
/// conflictingTypes: [associate, benefactor]
class AmbiguousMapping extends ConflictType {
  final String deduplicatorName;
  final List<String> sourceNumbers;
  final List<String> targetNumbers;

  final bool sourceConflicts;
  final bool targetConflicts;
  final bool crossMapping;
  final Map<String, List<String>> relevantBlacklistEntries;
  final Map<String, String> relevantMappings;

  final List<MemberNumberType> conflictingTypes;

  const AmbiguousMapping({
    required this.deduplicatorName,
    required this.sourceNumbers,
    required this.targetNumbers,
    required this.sourceConflicts,
    required this.targetConflicts,
    required this.conflictingTypes,
    required this.relevantBlacklistEntries,
    required this.relevantMappings,
    this.crossMapping = false,
  });
}
