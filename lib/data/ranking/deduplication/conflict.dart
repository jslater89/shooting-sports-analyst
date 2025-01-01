
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';

import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;

/// A conflict is a potential discrepancy in competitor information that
/// may require manual action to resolve.
///
/// Conflicts can be caused by:
/// - Two competitors (i.e., two member numbers) who have different names,
///   which will lead to a list of 
class Conflict {
  /// The deduplicator name is the processed (alphabetic only, no punctuation or spaces, all lowercase)
  /// name that has multiple member numbers/shooter ratings.
  String deduplicatorName;
  /// The member numbers that have been identified as conflicting in some way.
  List<String> memberNumbers;
  /// The shooter ratings corresponding to the member numbers.
  Map<String, DbShooterRating> shooterRatings;
  /// Up to the last five matches where each member number appears.
  Map<String, List<DbShootingMatch>> matches;

  /// The causes of the conflict.
  List<ConflictType> causes;
  /// Proposed actions to resolve the conflict.
  List<DeduplicationAction> proposedActions;

  Conflict({
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

  /// If there are exactly two member numbers, the string difference between
  /// them (0 for totally dissimilar, 100 for identical).
  int get stringDifference {
    if(memberNumbers.length == 2) {
      return fuzzywuzzy.weightedRatio(memberNumbers[0], memberNumbers[1]);
    }
    return 0;
  }
  bool get probableTypo => stringDifference > 65;

  @override
  bool get canResolveAutomatically => probableTypo;

  const MultipleNumbersOfType({
    required this.deduplicatorName,
    required this.memberNumberType,
    required this.memberNumbers,
  });
}

/// In ambiguous mappings, member numbers of a lower-priority type
/// cannot be mapped to member numbers of a higher-priority type,
/// because there are at least two member numbers of at least one
/// of the types.
/// 
/// [sourceConflicts] and [targetConflicts] indicate whether the
/// source numbers or target numbers caused the conflict. [conflictingType]
/// indicates the type of the conflicting member numbers.
///
/// The list of conflicting member numbers guarantees that all its
/// member numbers are of the same type. The non-conflicting numbers
/// may be of different types.
/// 
/// e.g.
/// 
/// Source:    Target:
///  A12345     L1234
///  A67890
/// 
/// deduplicatorName: "johndoe"
/// sourceConflicts: true, targetConflicts: false
/// conflictingType: associate
class AmbiguousMapping extends ConflictType {
  final String deduplicatorName;
  final List<String> sourceNumbers;
  final List<String> targetNumbers;

  final bool sourceConflicts;
  bool get targetConflicts => !sourceConflicts;

  final MemberNumberType conflictingType;

  const AmbiguousMapping({
    required this.deduplicatorName,
    required this.sourceNumbers,
    required this.targetNumbers,
    required this.sourceConflicts,
    required this.conflictingType,
  });
}
