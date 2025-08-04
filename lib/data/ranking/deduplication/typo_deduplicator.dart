/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/standard_deduplicator.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

/// TypoDeduplicator is a generic deduplicator that attempts to detect and resolve only
/// the simplest conflicts: typos and distinct members sharing the same name.
///
/// It has no domain knowledge, and operates solely on the basis of string similarity
/// between member numbers, proposing
class TypoDeduplicator extends StandardDeduplicator {
  String sportName;
  Sport get sport => SportRegistry().lookup(sportName)!;

  RegExp? validNumberRegex;

  TypoDeduplicator({required this.sportName, this.validNumberRegex});

  @override
  List<String> alternateForms(String number, {bool includeInternationalVariants = false}) {
    return [number];
  }

  @override
  MemberNumberType classify(String number) {
    if(validNumberRegex != null && !validNumberRegex!.hasMatch(number)) {
      return MemberNumberType.invalid;
    }
    return MemberNumberType.standard;
  }

  static const similarityThreshold = 65;

  @override
  DeduplicationCollision? detectConflicts({required DeduplicationCollision conflict, required String name, required List<DbShooterRating> ratings, required Map<MemberNumberType, List<String>> numbers, required Map<String, DbShooterRating> numbersToRatings, required Map<String, String> userMappings, required Map<String, String> detectedUserMappings, required Map<String, String> allMappings, required Map<String, String> detectedMappings, required Map<String, List<String>> blacklist}) {
    // We can only handle one case without sport-specific knowledge: either these are two distinct members
    // sharing the same name, or this is one member who has typoed his member number.

    var ongoingNumbers = numbers.deepCopy();

    // We don't strictly need this outer loop, since all of our numbers should be 'standard' type, given that
    // our [classify] doesn't return anything else.
    var flatNumbers = numbers.values.flattened.toList();
    var invalidNumbers = numbers[MemberNumberType.invalid] ?? [];

    if(flatNumbers.length > 1) {
      conflict.causes.add(
        MultipleNumbersOfType(
          deduplicatorName: name,
          memberNumberType: MemberNumberType.standard,
          memberNumbers: flatNumbers,
          probablyInvalidNumbers: invalidNumbers,
        )
      );
    }

    // Compare numbers pairwise, add either fixes or blacklists as appropriate (if not
    // already blacklisted).
    for(var i = 0; i < flatNumbers.length; i++) {
      for(var j = i + 1; j < flatNumbers.length; j++) {
        var number1 = flatNumbers[i];
        var number2 = flatNumbers[j];
        bool number1Valid = validNumberRegex?.hasMatch(number1) ?? true;
        bool number2Valid = validNumberRegex?.hasMatch(number2) ?? true;

        bool onlyOneValid = number1Valid != number2Valid;

        var similarity = fuzzywuzzy.weightedRatio(number1, number2);

        // If the numbers are highly similar, propose a data entry fix from the second
        // number appearing to the first. Otherwise, add a blacklist entry.
        if(similarity > similarityThreshold) {
          var probableTarget = number1;
          var probableSource = number2;

          if(invalidNumbers.contains(probableTarget) && !invalidNumbers.contains(probableSource)) {
            probableTarget = number2;
            probableSource = number1;
          }

          conflict.proposedActions.add(DataEntryFix(
            deduplicatorName: name,
            sourceNumber: probableSource,
            targetNumber: probableTarget,
          ));

          // Remove the data fix source number from the list.
          ongoingNumbers[MemberNumberType.standard]?.remove(probableSource);
          ongoingNumbers[MemberNumberType.invalid]?.remove(probableSource);
        }
        else if(onlyOneValid) {
          // If only one of the numbers is valid, we can propose a data entry fix from the
          // invalid number to the valid one.
          if(number1Valid) {
            conflict.proposedActions.add(DataEntryFix(
              deduplicatorName: name,
              sourceNumber: number2,
              targetNumber: number1,
            ));

            // Remove the data fix source number from the list.
            ongoingNumbers[MemberNumberType.standard]?.remove(number2);
            ongoingNumbers[MemberNumberType.invalid]?.remove(number2);
          }
          else {
            conflict.proposedActions.add(DataEntryFix(
              deduplicatorName: name,
              sourceNumber: number1,
              targetNumber: number2,
            ));

            // Remove the data fix source number from the list.
            ongoingNumbers[MemberNumberType.standard]?.remove(number1);
            ongoingNumbers[MemberNumberType.invalid]?.remove(number1);
          }
        }
        else if(!blacklist.isBlacklisted(number1, number2, bidirectional: true)) {
          conflict.proposedActions.add(Blacklist(
            sourceNumber: number1,
            targetNumber: number2,
            bidirectional: true,
          ));
        }

        // Suggest manual review for any close ones.
        if((similarity - similarityThreshold).abs() < 10) {
          conflict.causes.addIfMissing(ManualReviewRecommended());
        }
      }
    }


    // Suggest manual review for any cases where (for some reason) we don't resolve all
    // conflicts.
    if(!conflict.proposedActionsResolveConflict()) {
      conflict.causes.addIfMissing(ManualReviewRecommended());
    }

    return conflict;
  }

  @override
  List<String>? maybeTargetNumber(Map<MemberNumberType, List<String>> numbers) {
    for(var number in numbers.values.flattened) {
      return [number];
    }
    return null;
  }

  @override
  List<String> targetNumber(Map<MemberNumberType, List<String>> numbers) {
    for(var number in numbers.values.flattened) {
      return [number];
    }
    return [];
  }

  @override
  InlineSpan linksForMemberNumbers({required BuildContext context, required String text, required List<String> memberNumbers, TextStyle? runningStyle, TextStyle? linkStyle}) {
    if(sport == idpaSport) {
      return MemberNumberLinker("https://www.idpa.com/members/{{number}}/").linksForMemberNumbers(context: context, text: text, memberNumbers: memberNumbers, runningStyle: runningStyle, linkStyle: linkStyle);
    }
    else {
      return super.linksForMemberNumbers(context: context, text: text, memberNumbers: memberNumbers, runningStyle: runningStyle, linkStyle: linkStyle);
    }
  }
}
