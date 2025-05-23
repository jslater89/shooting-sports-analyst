/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("StandardDeduplicator");

/// StandardDeduplicator handles the standard logic for deduplication across
/// all deduplicator variants: loading the necessary data, ensuring that any
/// conflicts detected in project settings are noted, and only delegating to
/// subclasses once it is clear that conflicts exist, and that sport-specific
/// logic will be required to resolve them.
///
/// Sport-specific logic goes in [detectConflicts].
abstract class StandardDeduplicator extends ShooterDeduplicator {

  @override
  Future<DeduplicationResult> deduplicateShooters({
    required DbRatingProject ratingProject,
    required RatingGroup group,
    required List<DbShooterRating> newRatings,
    DeduplicatorProgressCallback? progressCallback,
    bool checkDataEntryErrors = true,
    bool verbose = false}) async
  {
    var userMappings = ratingProject.settings.userMemberNumberMappings;
    var autoMappings = ratingProject.automaticNumberMappings;
    Map<String, List<String>> reverseMappings = {};

    await progressCallback?.call(0, 2, "Preparing data");

    // All known mappings, user and automatic. User-specified mappings will override
    // previously-detected automatic mappings.
    Map<String, String> allMappings = {};
    for(var mapping in autoMappings) {
      for(var sourceNumber in mapping.sourceNumbers) {
        allMappings[sourceNumber] = mapping.targetNumber;
        reverseMappings.addToListIfMissing(mapping.targetNumber, sourceNumber);
      }
    }
    for(var mapping in userMappings.entries) {
      allMappings[mapping.key] = mapping.value;
      reverseMappings.addToListIfMissing(mapping.value, mapping.key);
    }

    await progressCallback?.call(1, 2, "Preparing data");

    // The blacklist operates in subtly different ways for different
    // kinds of conflicts.
    // When checking if we can auto-map, we want to be as permissive as
    // possible—if the target of a blacklist is also the target of the
    // proposed automapping, prefer to remove the source of the blacklist
    // rather than the target.
    // We make a copy of this because it is modified in some cases below
    // to track the impact of proposed changes.
    Map<String, List<String>> blacklist = ratingProject.settings.memberNumberMappingBlacklist.deepCopy();

    Set<String> deduplicatorNames = {};

    Map<String, List<DbShooterRating>> ratingsByName = {};

    /// The overall list of conflicts.
    List<DeduplicationCollision> conflicts = [];

    // Retrieve deduplicator names from the new ratings.
    // The only names that can cause conflicts are those
    // that we just added, since we do this every time we
    // add ratings.
    for(var rating in newRatings) {
      deduplicatorNames.add(rating.deduplicatorName);
      ratingsByName[rating.deduplicatorName] ??= [];
      ratingsByName[rating.deduplicatorName]!.add(rating);
    }

    await progressCallback?.call(0, deduplicatorNames.length, "Detecting conflicts");
    int step = 0;

    // Detect conflicts for each name.
    for(var name in deduplicatorNames) {
      Map<String, String> detectedMappings = {};
      Map<String, String> detectedUserMappings = {};

      var ratingsRes = await ratingProject.getRatingsByDeduplicatorName(group, name);

      if(ratingsRes.isErr()) {
        _log.w("Failed to retrieve ratings for deduplicator name $name", error: ratingsRes.unwrapErr());
        continue;
      }

      step += 1;
      await progressCallback?.call(step, deduplicatorNames.length, "Detecting conflicts: $name");

      List<DbShooterRating> ratings = [];
      Map<int, bool> dbIdsSeen = {};
      for(var rating in ratingsByName[name]!) {
        if(dbIdsSeen[rating.id] != true) {
          ratings.add(rating);
        }
        if(rating.id != 0 && rating.id != Isar.autoIncrement) {
          dbIdsSeen[rating.id] = true;
        }
      }
      for(var rating in ratingsRes.unwrap()) {
        if(dbIdsSeen[rating.id] != true) {
          ratings.add(rating);
        }
        if(rating.id != 0 && rating.id != Isar.autoIncrement) {
          dbIdsSeen[rating.id] = true;
        }
      }

      // One rating doesn't need to be deduplicated.
      if(ratings.length <= 1) {
        continue;
      }

      // If all ratings are blacklisted to each other, we can skip the rest of the process.
      Map<DbShooterRating, List<DbShooterRating>> allowedTargets = {};
      for(var rating in ratings) {
        allowedTargets[rating] = [];
        for(var otherRating in ratings) {
          if(rating == otherRating) continue;
          var isAllowed = true;
          for(var number in rating.knownMemberNumbers) {
            for(var otherNumber in otherRating.knownMemberNumbers) {
              if(blacklist[number]?.contains(otherNumber) ?? false) {
                isAllowed = false;
                break;
              }
            }
            if(!isAllowed) break;
          }
          if(isAllowed) {
            allowedTargets[rating]!.add(otherRating);
          }
        }
      }

      bool ratingsAllBlacklisted = true;
      for(var rating in ratings) {
        if(allowedTargets[rating]!.isNotEmpty) {
          ratingsAllBlacklisted = false;
          break;
        }
      }

      if(ratingsAllBlacklisted) {
        continue;
      }

      // Classify the member numbers by type.
      Map<MemberNumberType, List<String>> numbers = {};
      Map<String, DbShooterRating> numbersToRatings = {};
      for(var rating in ratings) {
        // 2025-01-03: I think we can use the plain memberNumber property
        // (i.e., the most recent member number) in this scenario, even
        // though most of these will have multiple entries in allPossibleMemberNumbers.
        // 2025-01-05: during the thinking aloud segment below, I think we might actually
        // need to use knownMemberNumbers here, to handle the (relatively rare but not impossible)
        // case where we're adding an additional member number that ought to map to a
        // non-primary member number.
        for(var number in rating.knownMemberNumbers) {
          var type = classify(number);
          numbers.addToList(type, number);
          numbersToRatings[number] = rating;
        }
      }

      numbers = condenseMemberNumbers(numbers);

      var conflict = DeduplicationCollision(
        deduplicatorName: name,
        memberNumbers: numbers.deepCopy(),
        shooterRatings: numbersToRatings,
        matches: {},
        causes: [],
        proposedActions: [],
      );

      if(conflict.flattenedMemberNumbers.length == 1) {
        // If we condense numbers and end up with a single number, there's no conflict.
        continue;
      }

      // Try to sort the numbers into identities: sets of strings that refer to the same person,
      // according to mappings/reverse mappings.
      List<Set<String>> identities = [];
      for(var number in conflict.flattenedMemberNumbers) {
        bool foundIdentity = false;
        for(var identity in identities) {
          // A number belongs to an identity if it is either the source or target of a mapping
          // that belongs to the identity.
          if(identity.contains(number)) {
            // This shouldn't happen, but catch it anyway just in case.
            foundIdentity = true;
          }
          else if(identity.contains(allMappings[number])) {
            // If the identity contains the target of number's mapping, number belongs to the identity.
            identity.add(number);
            foundIdentity = true;
          }
          else {
          // If the identity contains the source of number's mapping, number belongs to the identity.
            var reverse = reverseMappings[number];
            if(reverse != null) {
              for(var reverseMapping in reverse) {
                if(identity.contains(reverseMapping)) {
                  identity.add(number);
                  foundIdentity = true;
                }
              }
            }
          }

          // If we found an identity, we can stop looking.
          if(foundIdentity) {
            break;
          }
        }

        if(!foundIdentity) {
          identities.add({number});
        }
      }

      // Add known mappings/reverse mappings to the identities.
      for(var identity in identities) {
        Set<String> mappedNumbers = {};
        for(var number in identity) {
          var mappingTarget = allMappings[number];
          if(mappingTarget != null) {
            mappedNumbers.add(mappingTarget);
          }

          var mappingSources = reverseMappings[number];
          if(mappingSources != null) {
            for(var mappingSource in mappingSources) {
              mappedNumbers.add(mappingSource);
            }
          }
        }
        identity.addAll(mappedNumbers);
      }

      // If we have more than one identity, and if at least one number in each identity is blacklisted
      // to at least one number in each other identity, all numbers in each identity are implicitly
      // blacklisted to all numbers in every other identity.
      //
      // We check for the existence of a rule break rather than satisfaction of the rule for all cases
      // for ease of logic.
      if(identities.length > 1) {
        bool implicitBlacklist = true;
        identityLoop: for(int i = 0; i < identities.length; i++) {
          var identity1 = identities[i];
          for(int j = i + 1; j < identities.length; j++) {
            var identity2 = identities[j];

            bool atLeastOneBlacklisted = false;
            numberLoop:for(var n1 in identity1) {
              for(var n2 in identity2) {
                if(blacklist.isBlacklisted(n1, n2, bidirectional: true)) {
                  atLeastOneBlacklisted = true;
                  break numberLoop;
                }
              }
            }
            if(!atLeastOneBlacklisted) {
              implicitBlacklist = false;
              break identityLoop;
            }
          }
        }

        // If we have an implicit blacklist, we can add it to the conflict and skip the rest of the process.
        if(implicitBlacklist) {
          // Add explicit blacklist entries for all implicitly blacklisted numbers.
          bool addedNewBlacklist = false;
          for(int i = 0; i < identities.length; i++) {
            var identity1 = identities[i];
            for(int j = i + 1; j < identities.length; j++) {
              var identity2 = identities[j];
              for(var n1 in identity1) {
                for(var n2 in identity2) {
                  if(!blacklist.isBlacklisted(n1, n2, bidirectional: true)) {
                    blacklist.addToListIfMissing(n1, n2);
                    blacklist.addToListIfMissing(n2, n1);
                    conflict.proposedActions.add(Blacklist(
                      sourceNumber: n1,
                      targetNumber: n2,
                      bidirectional: true,
                    ));
                    addedNewBlacklist = true;
                  }
                }
              }
            }
          }

          // If we didn't propose any actions, then all of the 'implicit' blacklists are
          // actually already explicit, so we shouldn't add the ImplicitBlacklist cause.
          if(addedNewBlacklist) {
            conflict.causes.add(ImplicitBlacklist(
              deduplicatorName: name,
              identities: identities,
            ));
            // We may be able to remove this later if it proves reliable.
            conflict.causes.add(ManualReviewRecommended());
            conflicts.add(conflict);
            continue;
          }
        }
      }


      // Check if any user mappings apply to the list of ratings, and if they haven't been
      // previously applied. This can happen if we're doing a full recalculation.
      // First, find all of the mappings that apply to this rating.
      List<PreexistingMapping> preexistingMappingActions = [];
      List<AmbiguousMapping> ambiguousMappings = [];
      Map<String, String> possibleMappings = {};
      Map<String, String> possibleUserMappings = {};
      for(var rating in ratings) {
        for(var number in rating.knownMemberNumbers) {
          var userTarget = userMappings[number];
          var autoTarget = allMappings[number];
          if(userTarget != null && !rating.knownMemberNumbers.contains(userTarget)) {
            possibleUserMappings[number] = userTarget;
            possibleMappings[number] = userTarget;
          }
          if(autoTarget != null && !rating.knownMemberNumbers.contains(autoTarget)) {
            // If there's already a user mapping for this number, don't override it.
            // TODO: mark this for deletion in some way.
            if(!possibleMappings.containsKey(number)) {
              possibleMappings[number] = autoTarget;
            }
          }
        }
      }

      // Possible mappings contains all of the mappings that apply to the given ratings
      // that are not already applied. We need to verify that they all point to the same
      // target, and if they do, we can add PreexistingMapping actions for the source
      // numbers.
      Set<String> possibleTargetNumbers = {};
      Set<String> possibleUserTargetNumbers = {};
      for(var target in possibleUserMappings.values) {
        possibleTargetNumbers.add(target);
        possibleUserTargetNumbers.add(target);
      }
      for(var target in possibleMappings.values) {
        possibleTargetNumbers.add(target);
      }

      // If all of the target numbers are the same, the mappings are consistent,
      // and we can add them to preexistingMappingActions.
      if(possibleTargetNumbers.length == 1) {
        for(var source in possibleUserMappings.keys) {
          preexistingMappingActions.add(PreexistingMapping(
            sourceNumber: source,
            targetNumber: possibleTargetNumbers.first,
            automatic: false,
          ));
          detectedUserMappings[source] = possibleTargetNumbers.first;
          detectedMappings[source] = possibleTargetNumbers.first;
        }
        for(var source in possibleMappings.keys) {
          if(!detectedMappings.containsKey(source)) {
            preexistingMappingActions.add(PreexistingMapping(
              sourceNumber: source,
              targetNumber: possibleTargetNumbers.first,
              automatic: true,
            ));
            detectedMappings[source] = possibleTargetNumbers.first;
          }
        }
      }
      else if(possibleTargetNumbers.length > 1){
        // If there are multiple target numbers, we have a cross mapping. We might
        // be able to resolve it automatically if there's a single best target number.
        // It's only a potential cross mapping because if we have A123456 -> L1234 and
        // L1234 -> B123, we can correct that by mapping everything to the best target.
        _log.w("Potential cross mapping for name $name\n    User mappings: $possibleUserMappings\n    All mappings: $possibleMappings");
        Map<MemberNumberType, List<String>> classifiedTargetNumbers = {};
        for(var target in possibleTargetNumbers) {
          var type = classify(target);
          classifiedTargetNumbers[type] ??= [];
          classifiedTargetNumbers[type]!.add(target);
        }
        var finalTargets = targetNumber(classifiedTargetNumbers);
        if(finalTargets.length == 1) {
          var finalTarget = finalTargets.first;
          for(var source in possibleUserMappings.keys) {
            preexistingMappingActions.add(PreexistingMapping(
              sourceNumber: source,
              targetNumber: finalTarget,
              automatic: false,
            ));
            detectedUserMappings[source] = finalTarget;
            detectedMappings[source] = finalTarget;
          }
          for(var source in possibleMappings.keys) {
            if(!detectedMappings.containsKey(source)) {
              preexistingMappingActions.add(PreexistingMapping(
                sourceNumber: source,
                targetNumber: finalTarget,
                automatic: true,
              ));
              detectedMappings[source] = finalTarget;
            }
          }

          conflict.causes.add(AmbiguousMapping(
            deduplicatorName: name,
            sourceNumbers: possibleMappings.keys.toList(),
            targetNumbers: possibleTargetNumbers.toList(),
            sourceConflicts: possibleMappings.length > 1,
            targetConflicts: possibleTargetNumbers.length > 1,
            conflictingTypes: classifiedTargetNumbers.keys.toList(),
            relevantBlacklistEntries: {},
            relevantMappings: possibleMappings,
            crossMapping: true,
          ));
        }
        else {
          _log.e("Unable to resolve cross mapping");
          var targetTypes = classifiedTargetNumbers.keys.toList();
          ambiguousMappings.add(AmbiguousMapping(
            deduplicatorName: name,
            sourceNumbers: possibleMappings.keys.toList(),
            targetNumbers: possibleTargetNumbers.toList(),
            sourceConflicts: possibleMappings.length > 1,
            targetConflicts: possibleTargetNumbers.length > 1,
            conflictingTypes: targetTypes,
            relevantBlacklistEntries: {},
            relevantMappings: possibleMappings,
            crossMapping: true,
          ));
        }
      }

      // If we have any entries in the ambiguousMappings list, this is a cross mapping, and
      // we need the user to tell us what to do.
      if(ambiguousMappings.isNotEmpty) {
        conflict.causes.addAll(ambiguousMappings);
        conflicts.add(conflict);
        continue;
      }

      // Otherwise, if we have preexisting mapping actions, add a 'conflict' so that the
      // resolution system knows to apply them to the DB objects.
      if(preexistingMappingActions.isNotEmpty) {
        conflict.proposedActions.addAll(preexistingMappingActions);

        // If the detected preexisting mappings covers all of the member numbers, or
        // if all uncovered numbers are blacklisted to one or more of the preexisting
        // mapping targets, this conflict was fully resolved in settings, and we can
        // skip the remaining checks.
        bool fullyResolved = conflict.coversNumbers(numbers.values.flattened);
        if(!fullyResolved) {
          var uncoveredNumbers = conflict.uncoveredNumbersList;
          if(uncoveredNumbers.isNotEmpty) {
            var targetNumbers = preexistingMappingActions.map((e) => e.targetNumber).toList();
            bool allBlacklisted = true;
            for(var number in uncoveredNumbers) {
              var numberBlacklist = blacklist[number] ?? [];
              // If no target numbers are contained in this unresolved number's blacklist,
              // then this unresolved number is not covered by blacklists, and settings
              // don't fully resolve the conflict.
              if(targetNumbers.none((e) => numberBlacklist.contains(e))) {
                allBlacklisted = false;
                break;
              }
            }
            if(allBlacklisted) {
              fullyResolved = true;
            }
          }
        }

        if(fullyResolved) {
          conflict.causes.add(FixedInSettings());
          conflicts.add(conflict);
          continue;
        }
      }

      // This wraps up all of our standard logic, that which holds across
      // all normal deduplicators, so now we delegate to the subclass for
      // sport-specific things.
      var sportSpecificConflict = detectConflicts(
        conflict: conflict,
        name: name,
        ratings: ratings,
        numbers: numbers,
        numbersToRatings: numbersToRatings,
        userMappings: userMappings,
        detectedUserMappings: detectedUserMappings,
        allMappings: allMappings,
        detectedMappings: detectedMappings,
        blacklist: blacklist,
      );
      if(sportSpecificConflict != null) {
        conflicts.add(sportSpecificConflict);
      }
    }

    return DeduplicationResult.ok(conflicts);
  }

  /// Detect conflicts for a given deduplicator name.
  ///
  /// This will be called for each deduplicator name in the project that has more
  /// than one rating, and whose conflict has not already been resolved on previous
  /// runs (but not yet applied, in the event of full recalculations).
  ///
  /// [conflict] is the base conflict object, which should be modified in place
  /// and returned if it should be added to the resulting conflict list. If there
  /// is no conflict, return null.
  ///
  /// [name] is the processed name of the competitor that caused the conflict.
  ///
  /// [ratings] is the list of ratings that have [name] as their name.
  ///
  /// [numbers] is a map of member number type to list of member numbers for the given
  /// deduplicator name.
  ///
  /// [userMappings] is a map of member number to target number for any user-specified
  /// mappings.
  ///
  /// [allMappings] is a map of member number to target number for all number mappings,
  /// both automatic and user-specified.
  ///
  /// [blacklist] is a map of member numbers to a list of member numbers. A key in this
  /// map should not be mapped to any of the values in its list.
  DeduplicationCollision? detectConflicts({
    required DeduplicationCollision conflict,
    required String name,
    required List<DbShooterRating> ratings,
    required Map<MemberNumberType, List<String>> numbers,
    required Map<String, DbShooterRating> numbersToRatings,
    required Map<String, String> userMappings,
    required Map<String, String> detectedUserMappings,
    required Map<String, String> allMappings,
    required Map<String, String> detectedMappings,
    required Map<String, List<String>> blacklist,
  });

  /// If applicable, condense member numbers in the given map.
  ///
  /// If the sport logic admits multiple equivalent numbers of one type, this condenses
  /// them into a single number. (The archetypal case is USPSA's A/TY/FY associate numbers.)
  ///
  /// [numbers] is a map of member number types to lists of member numbers. It is safe to
  /// modify in place.
  ///
  /// Return the condensed map (you can return [numbers] without copying). The default
  /// implementation returns the input map unchanged.
  Map<MemberNumberType, List<String>> condenseMemberNumbers(Map<MemberNumberType, List<String>> numbers) {
    return numbers;
  }

  /// Two member numbers are already mapped if source is already mapped to target, or
  /// if both source and target are mapped to the same third number.
  bool alreadyMapped(String source, String target, Map<String, String> mappings) {
    if(mappings.containsKey(source) && mappings[source] == target) {
      return true;
    }

    var sourceMapping = mappings[source];
    var targetMapping = mappings[target];
    if(sourceMapping != null && targetMapping != null && sourceMapping == targetMapping) {
      return true;
    }

    return false;
  }
}

extension BlacklistCheck on Map<String, List<String>> {
  /// Check if [number]'s blacklist contains [target]. If [bidirectional] is true,
  /// check if either number is blacklisted to the other.
  bool isBlacklisted(String number, String target, {bool bidirectional = false}) {
    var blacklist = this[number];

    if(bidirectional) {
      var reverseBlacklist = this[target];
      var blacklisted = blacklist?.contains(target) ?? false;
      var reverseBlacklisted = reverseBlacklist?.contains(number) ?? false;
      return blacklisted || reverseBlacklisted;
    }
    else {
      if(blacklist == null) return false;
      return blacklist.contains(target);
    }
  }
}
