// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:url_launcher/url_launcher.dart';

var _log = SSALogger("USPSADeduplicator");

/// USPSAMemberNumber is a wrapper around USPSA member number strings that
/// provides USPSA-specific equality rules (i.e., A/TY/FY/TYF/FYF numbers
/// with the same numeric component are considered equal).
class USPSAMemberNumber {
  final MemberNumberType type;

  /// The normalized number, rendered in all-caps alphanumeric characters.
  final String normalizedNumber;

  /// The internal number, rendered in all-caps alphanumeric characters,
  /// with leading associate number components stripped.
  final String internalNumber;

  /// The numeric component of the member number, stripped of
  /// any alphabetic characters.
  final String numericComponent;

  /// Construct a USPSA member number from a raw member number string.
  USPSAMemberNumber(String memberNumber) :
    type = USPSADeduplicator().classify(memberNumber),
    normalizedNumber = USPSADeduplicator().processNumber(memberNumber),
    internalNumber = USPSADeduplicator()._stripATYFY(memberNumber),
    numericComponent = memberNumber.replaceAll(RegExp(r'[^0-9]'), "");

  /// Construct a USPSA member number, providing all of the values directly.
  USPSAMemberNumber.unsafe({required this.type, required this.normalizedNumber, required this.internalNumber, required this.numericComponent});

  @override
  operator ==(Object other) {
    if(other is USPSAMemberNumber) {
      if(type != other.type) return false;
      if(type == MemberNumberType.standard && other.type == MemberNumberType.standard) {
        // Handle cases where people put extra letters in the numeric component
        // How are people so bad at typing a two-letter prefix and a six-digit number?
        return numericComponent == other.numericComponent;
      }
      return internalNumber == other.internalNumber;
    }
    else if(other is String) {
      if(type == MemberNumberType.standard) {
        var otherNumeric = other.replaceAll(RegExp(r'[^0-9]'), "");
        return numericComponent == otherNumeric;
      }
      else {
        var otherInternal = USPSADeduplicator()._stripATYFY(other);
        return internalNumber == otherInternal;
      }
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(type, internalNumber);

  @override
  String toString() {
    if(type != MemberNumberType.standard) {
      return normalizedNumber;
    }
    else return "$internalNumber ($normalizedNumber)";
  }
}

class USPSADeduplicator extends ShooterDeduplicator {
  static USPSADeduplicator? _instance;

  USPSADeduplicator._();
  factory USPSADeduplicator() {
    if(_instance == null) {
      _instance = USPSADeduplicator._();
    }
    return _instance!;
  }

  @override
  Future<DeduplicationResult> deduplicateShooters({
    required DbRatingProject ratingProject,
    required RatingGroup group,
    required List<DbShooterRating> newRatings,
    bool checkDataEntryErrors = true,
    bool verbose = false
  }) async {
    var userMappings = ratingProject.settings.userMemberNumberMappings;
    var autoMappings = ratingProject.automaticNumberMappings;

    // All known mappings, user and automatic. User-specified mappings will override
    // previously-detected automatic mappings.
    Map<String, String> allMappings = {};
    for(var mapping in autoMappings) {
      for(var sourceNumber in mapping.sourceNumbers) {
        allMappings[sourceNumber] = mapping.targetNumber;
      }
    }
    for(var mapping in userMappings.entries) {
      allMappings[mapping.key] = mapping.value;
    }

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

    // Detect conflicts for each name.
    for(var name in deduplicatorNames) {
      Map<String, String> detectedMappings = {};
      Map<String, String> detectedUserMappings = {};

      var ratingsRes = await ratingProject.getRatingsByDeduplicatorName(group, name);

      if(ratingsRes.isErr()) {
        _log.w("Failed to retrieve ratings for deduplicator name $name", error: ratingsRes.unwrapErr());
        continue;
      }

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

      // For each set of equivalent associate numbers, we only want to keep the best one.
      Set<String> finalAssociateNumbers = {};
      Map<USPSAMemberNumber, List<String>> associateNumbersByIdentity = {};
      for(var number in numbers[MemberNumberType.standard] ?? []) {
        var identity = USPSAMemberNumber(number);
        associateNumbersByIdentity.addToList(identity, number);
      }

      for(var identity in associateNumbersByIdentity.keys) {
        var bestNumber = _bestAssociateNumber(associateNumbersByIdentity[identity]!);
        finalAssociateNumbers.add(bestNumber);
      }

      if(finalAssociateNumbers.isNotEmpty) {
        numbers[MemberNumberType.standard] = finalAssociateNumbers.toList();
      }

      var conflict = DeduplicationCollision(
        deduplicatorName: name,
        memberNumbers: numbers.deepCopy(),
        shooterRatings: numbersToRatings,
        matches: {},
        causes: [],
        proposedActions: [],
      );

      if(name.startsWith("marcosrod")) {
        print("break");
      }

      if(conflict.flattenedMemberNumbers.length == 1) {
        // If, after condensing equivalent associate numbers, we only have one number, we also
        // don't have a conflict.
        
        Map<DbShooterRating, bool> distinctRatings = {};
        for(var r in numbersToRatings.values) {
          distinctRatings[r] = true;
        }
        if(distinctRatings.length != 1) {
          // This log message is expected during tests.
          // TODO: this shows up outside of tests too, for reasons I'm not totally sure about.
          // Come back to it with the debugger at some point.
          _log.w("${distinctRatings.length} rating objects for $name, but only one member number: ${conflict.flattenedMemberNumbers.first}");
        }
        continue;
      }

      // Special case: sometimes competitors (especially at locals) enter an A/TY/FY
      // number without a prefix. Those will get classified to International. In the
      // case where we have one International number whose numeric part is the same as
      // the numeric part of a standard number, propose a DataEntryFix.
      if(numbers[MemberNumberType.international]?.length == 1) { // null != 1
        var internationalNumber = numbers[MemberNumberType.international]!.first;
        if(internationalNumber.length >= 5 && internationalNumber.length <= 6) {
          var international = USPSAMemberNumber(internationalNumber);
          for(var standardNumber in numbers[MemberNumberType.standard] ?? []) {
            var standard = USPSAMemberNumber(standardNumber);
            var added = false;
            if(international.internalNumber == standard.internalNumber) {
              conflict.proposedActions.add(DataEntryFix(
                deduplicatorName: name,
                sourceNumber: internationalNumber,
                targetNumber: standardNumber,
              ));
              added = true;
            }
            if(added) {
              // If we added a DataEntryFix, remove the international number from the
              // list for the remaining checks.
              numbers[MemberNumberType.international]!.remove(internationalNumber);
              break;
            }
          }
        }
      }

      if(numbers.values.flattened.length == 1 && conflict.proposedActions.isNotEmpty) {
        // If we have a single member number and we've added proposed actions,
        // we handled a 1-1 'international'/no-prefix number in the block above, and
        // can move on to the next conflict.
        conflicts.add(conflict);
        continue;
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

        // If the detected preexisting mappings cover all of the member numbers,
        // we can skip the rest of the checks.
        if(conflict.coversNumbers(numbers.values.flattened)) {
          conflict.causes.add(FixedInSettings());
          conflicts.add(conflict);
          continue;
        }
      }

      // Simplest (remaining) case: there is only one member number of each type
      // appearing, so we assume that the multiple entries are for
      // the same person.
      bool canAutoMap = true;
      for(var type in numbers.keys) {
        if(numbers[type]!.length != 1) {
          canAutoMap = false;
          break;
        }
      }

      // TODO: see below (automapping with user mappings)
      // A better automapping is possible, but only if the target number type is better
      // than the mapping's target. We should probably present that to the user as a
      // proposed UserMapping rather than an AutoMapping, so we don't have to do anything
      // funky with the UserMapping overrides AutoMapping priority. (If we send a UserMapping
      // with all of the member numbers, it'll overwrite the old mappings in the project settings,
      // so we don't need to worry about that on the next recalc.)

      if(canAutoMap) {
        // If canAutoMap is true, then all of our member number lists have
        // length 1, so we can assume that 'first' is a valid operation at
        // this point.
        var autoMapNumbers = numbers;
        var autoMapFlatNumbers = autoMapNumbers.values.flattened.toList();
        var target = maybeTargetNumber(autoMapNumbers)?.first;
        var blacklisted = false;

        // Check for blacklisted mappings.
        // If N1 -> N2 is blacklisted and N2 is the target, then
        // remove N1 from the list of sources. Otherwise, remove
        // N2 from the numbers map. In both cases, recalculate
        // the target after doing so.
        for(var n1 in autoMapFlatNumbers) {
          for(var n2 in autoMapFlatNumbers) {
            if(blacklist[n1]?.contains(n2) ?? false) {
              if(n2 == target) {
                autoMapNumbers.values.forEach((e) => e.remove(n1));
                var maybeTarget = maybeTargetNumber(autoMapNumbers)?.firstOrNull;
                if(maybeTarget != null) {
                  target = maybeTarget;
                }
                else {
                  blacklisted = true;
                }
              }
              else {
                autoMapNumbers.values.forEach((e) => e.remove(n2));
                var maybeTarget = maybeTargetNumber(autoMapNumbers)?.firstOrNull;
                if(maybeTarget != null) {
                  target = maybeTarget;
                }
                else {
                  blacklisted = true;
                }
              }
            }
          }
        }

        // If, at the end of blacklist checking, we have no target or no sources,
        // then there's nothing to do, and we can fall through to the next check.
        autoMapFlatNumbers = autoMapNumbers.values.flattened.toList();
        var sources = autoMapFlatNumbers.where((e) => e != target).toList();

        if(target == null || sources.isEmpty) {
          blacklisted = true;
        }

        if(!blacklisted) {
          // If we don't have any implicated user mappings, we can add an AutoMapping.
          // If we do have implicated user mappings, we should present it as a UserMapping
          // for priority reasons.
          bool canAddMapping = true;
          bool shouldAddUserMapping = false;

          Map<String, String> implicatedMappings = {};
          for(var source in sources) {
            var target = detectedMappings[source];
            if(target != null) {
              implicatedMappings[source] = target;
            }
          }

          // If we have a detected mapping, we can only continue if
          // the newly detected auto mapping target is better than all of
          // the implicated mapping targets, and in that scenario,
          // we should make sure that all of the detected mapping sources
          // are included in the new mapping.
          if(implicatedMappings.isNotEmpty) {
            // 2025-01-06: I think this should be length 1, because
            // a set of mappings that maps to different things is a cross
            // mapping and we bail to resolve that manually.

            bool isUserMapping = false;
            bool shouldUpdateMapping = true;
            for(var mapping in implicatedMappings.entries) {
              var mappingTarget = mapping.value;
              var mappingType = classify(mappingTarget);
              var detectedType = classify(target!);
              if(detectedType.betterThan(mappingType)) {
                shouldUpdateMapping = true;

                if(detectedUserMappings[mapping.key] == mappingTarget) {
                  isUserMapping = true;
                }
              }
              else {
                canAddMapping = false;
              }
            }

            if(shouldUpdateMapping) {
              for(var source in implicatedMappings.keys) {
                if(!sources.contains(source)) {
                  sources.add(source);
                }
              }

              if(isUserMapping) {
                shouldAddUserMapping = true;
              }
            }
          }

          if(canAddMapping) {
            // If we have a single international and a single standard number,
            // we can add a DataEntryFix to fix the international number rather
            // than a mapping, since no-prefix international numbers might overlap
            // with American standard numbers.
            var autoMapTypes = {...autoMapFlatNumbers.map((e) => classify(e))};
            bool shouldAddInternationalDataEntryFix = false;
            if(autoMapTypes.contains(MemberNumberType.international) && autoMapTypes.contains(MemberNumberType.standard)) {
              if(autoMapNumbers[MemberNumberType.international]!.length == 1 && autoMapNumbers[MemberNumberType.standard]!.length == 1) {
                shouldAddInternationalDataEntryFix = true;
              }
            }

            DeduplicationAction proposedAction;
            if(shouldAddInternationalDataEntryFix) {
              var source = sources.where((e) => classify(e) == MemberNumberType.international).first;
              proposedAction = DataEntryFix(
                deduplicatorName: name,
                sourceNumber: source,
                targetNumber: target!,
              );
            }
            else if(shouldAddUserMapping) {
              proposedAction = UserMapping(
                sourceNumbers: sources,
                targetNumber: target!,
              );
            }
            else {
              proposedAction = AutoMapping(
                sourceNumbers: sources,
                targetNumber: target!,
              );
            }
            // The action we want to add contains all of the member numbers for this
            // conflict, so we can clear all of the previous proposed actions.
            conflict.proposedActions.clear();

            conflict.proposedActions.add(proposedAction);
            conflicts.add(conflict);
            continue;
          }
        }
      }


      // More complicated cases follow.

      // Assumptions at this point:
      // 1. At least one member number type has more than one member number.
      // (there are more, but I need to finish the code, write some tests, and
      // see how it works before I go to the trouble of documenting them)

      // MultipleNumbersOfType conflicts are a simpler case of AmbiguousMapping
      // conflicts. We can report MultipleNumbersOfType conflicts on their own
      // only if there are member numbers of only one type, or in a special case
      // around user mappings: two member numbers of the same type, one of
      // which is mapped to a different type. (A123456 -> L1234, A123457 e.g., or
      // A123456 -> L1234, L1235)

      // We can handle the special case by trying multiple times, copying the numbers
      // map, and removing one half of the user mappings at a time. If any of the
      // numbers maps so generated meets the criteria for a MultipleNumbersOfType
      // conflict, we can run the detection algorithm on it.

      // e.g. A123456 -> L1234, A123457:
      // 1. No-removal list: [A123456, A123457, L1234]: can't multiple-numbers-of-type it.
      // 2. Removal of A123456: [A123457, L1234]: can't multiple-numbers-of-type it.
      // 3. Removal of L1234: [A123456, A123457]: can multiple-numbers-of-type it.


      // For each mapping, create one copy of the numbers map with the source removed,
      // and one copy with the target removed.
      var multipleCheckNumbers = numbers.deepCopy();
      List<Map<MemberNumberType, List<String>>> multipleCheckNumbersList = [];
      multipleCheckNumbersList.add(multipleCheckNumbers);
      for(var mapping in detectedMappings.entries) {
        var sourceType = classify(mapping.key);
        var targetType = classify(mapping.value);

        multipleCheckNumbers = numbers.deepCopy();
        multipleCheckNumbers[sourceType]?.remove(mapping.key);
        multipleCheckNumbersList.add(multipleCheckNumbers);

        multipleCheckNumbers = numbers.deepCopy();
        multipleCheckNumbers[targetType]?.remove(mapping.value);
        multipleCheckNumbersList.add(multipleCheckNumbers);
      }


      for(var numbers in multipleCheckNumbersList) {
        List<MemberNumberType> typesWithMultipleNumbers = [];
        for(var type in numbers.keys) {
          if(numbers[type]!.length > 1) {
            typesWithMultipleNumbers.add(type);
          }
        }

        if(typesWithMultipleNumbers.length == 1 && numbers[typesWithMultipleNumbers.first]!.length > 1) {
          var type = typesWithMultipleNumbers.first;
          List<DeduplicationAction> proposedActions = [];
          var numbersOfType = numbers[type]!;
          // Since callers of this function will probably pass in member numbers in order of appearance,
          // for member numbers that are likely typos, the first item in the list is probably the
          // correct one. Do fuzzy string comparison to determine if we propose a blacklist for a given
          // number, or a user mapping.
          var probableTarget = numbersOfType.first;

          List<String> probablyInvalidNumbers = [];

          for(var number in numbersOfType) {
            if(_badDataEntryFixTarget(number)) {
              probablyInvalidNumbers.add(number);
            }
          }

          // There are some cases where that first number might not be the correct one, though, which we
          // can detect with some heuristics.
          if(probablyInvalidNumbers.contains(probableTarget)) {
            // Try to find a target that doesn't have heuristic problems.
            for(var otherTarget in numbersOfType.sublist(1)) {
              if(!probablyInvalidNumbers.contains(otherTarget)) {
                // The first one we find is probably the correct one, by the same reasoning
                // as above.
                probableTarget = otherTarget;
                break;
              }
            }
          }

          // If there are any detected mappings whose target is better than or equal to our current target,
          // we should use that as the target instead—consider a case where we have a mapping A123456 -> L1235,
          // but an L1234 typo appears before L1235. We want to take the mapping into account.
          for(var number in detectedMappings.values) {
            if(classify(number).betterThanOrEqual(type)) {
              probableTarget = number;
              break;
            }
          }
          List<String> sourceNumbers = [];
          for(var number in numbers[type]!.where((e) => e != probableTarget)) {
            int strdiff = 0;
            // Ignore prefixes for standard numbers.
            if(type == MemberNumberType.standard) {
              var uspsaNumber = USPSAMemberNumber(number);
              var uspsaTarget = USPSAMemberNumber(probableTarget);
              strdiff = fuzzywuzzy.weightedRatio(uspsaNumber.numericComponent, uspsaTarget.numericComponent);
            }
            else {
              strdiff = fuzzywuzzy.weightedRatio(probableTarget, number);
            }
            if(strdiff > 65 || probablyInvalidNumbers.contains(number)) {
              // Generally, if we encountered a facially invalid target, we want to
              // recommend a DataEntryFix with it as source, on the theory that A1234 -> A123456
              // is probably a typo fix rather than two separate numbers (since A1234 isn't valid
              // at all.)
              sourceNumbers.add(number);
            }
            // TODO: else if number is associate and too short or too long, preferentially make it a source
            else if(!(blacklist[number]?.contains(probableTarget) ?? false)) {
              proposedActions.add(Blacklist(
                sourceNumber: number,
                targetNumber: probableTarget,
                bidirectional: true,
              ));
              // We don't want to consider this number as a potential mapping in the autoresolvable
              // AmbiguousMapping case, so add it to the local blacklist even if the user chooses
              // not to blacklist it later on.
              blacklist.addToList(number, probableTarget);
            }
          }

          if(sourceNumbers.isNotEmpty) {
            for(var blacklistSource in blacklist.keys) {
              var blacklistTarget = blacklist[blacklistSource]!;
              if(blacklistTarget.contains(probableTarget)) {
                sourceNumbers.remove(blacklistSource);
              }
            }

            if(sourceNumbers.isNotEmpty) {
              for(var source in sourceNumbers) {
                var action = DataEntryFix(
                  deduplicatorName: name,
                  sourceNumber: source,
                  targetNumber: probableTarget,
                );
                if(conflict.proposedActions.none((e) => e == action)) {
                  proposedActions.add(action);
                }
              }
            }
          }

          if(proposedActions.isNotEmpty) {
            conflict.causes.add(MultipleNumbersOfType(
              deduplicatorName: name,
              memberNumberType: typesWithMultipleNumbers.first,
              memberNumbers: numbers[typesWithMultipleNumbers.first]!,
              probablyInvalidNumbers: probablyInvalidNumbers,
            ));
            conflict.proposedActions.addAll(proposedActions);
          }
        }
      }

      // Assumptions at this point:
      // 1. At least one member number type has more than one member number.
      // 2. At least two member number types have more than zero member numbers.
      // This is an ambiguous mapping, and we can't really guess about it.

      // AmbiguousMapping conflicts are not possible with any of the source or target numbers
      // in detected mappings by definition; they're already mapped. Copy the numbers map and
      // remove them before checking for conflicting types.

      Map<MemberNumberType, List<String>> ambiguousCheckNumbers = numbers.deepCopy();
      for(var mapping in detectedMappings.entries) {
        for(var type in ambiguousCheckNumbers.keys) {
          ambiguousCheckNumbers[type]!.remove(mapping.key);
          ambiguousCheckNumbers[type]!.remove(mapping.value);
        }
      }

      // MultipleNumbersOfType conflicts can remove numbers from consideration. For DataEntryFix
      // proposed actions, we can remove the source number because it counts as the target number
      // going forward. For Blacklist proposed actions, we can't remove anything, because either
      // the source or target could be mapped to the number of another type.
      for(var cause in conflict.causes) {
        if(cause is MultipleNumbersOfType) {
          // At present, Blacklist and DataEntryFix can only be proposed by the MultipleNumbersOfType
          // conflict, so we can just take the first one of those.
          var solution = conflict.proposedActions.firstWhereOrNull((e) => e is DataEntryFix || e is Blacklist);
          if(solution is DataEntryFix) {
            for(var type in ambiguousCheckNumbers.keys) {
              ambiguousCheckNumbers[type]!.remove(solution.sourceNumber);
            }
          }
          else if(solution is Blacklist) {
            // MultipleNumbersOfType only blacklists numbers of like type, so if
            // we have a blacklist, we can't actually remove anything from the list,
            // unless there are no other types of numbers in the map.
            var multipleNumbersType = (conflict.causes.first as MultipleNumbersOfType).memberNumberType;
            bool hasOtherTypes = false;
            for(var type in ambiguousCheckNumbers.keys.whereNot((e) => e == multipleNumbersType)) {
              if(ambiguousCheckNumbers[type]!.isNotEmpty) {
                hasOtherTypes = true;
                break;
              }
            }
            if(!hasOtherTypes) {
              ambiguousCheckNumbers[multipleNumbersType]!.remove(solution.sourceNumber);
              ambiguousCheckNumbers[multipleNumbersType]!.remove(solution.targetNumber);
            }
          }
        }
      }

      List<MemberNumberType> conflictingTypes = [];
      Map<MemberNumberType, bool> hasEntries = {};
      for(var type in ambiguousCheckNumbers.keys) {
        if(ambiguousCheckNumbers[type]!.length > 1) {
          conflictingTypes.add(type);
        }
        hasEntries[type] = ambiguousCheckNumbers[type]!.isNotEmpty;
      }

      if(conflictingTypes.isEmpty && hasEntries.values.where((e) => e).length <= 1) {
        // If there are no conflicting types and at most one type with any entries left,
        // then we don't need to add an ambiguous mapping entry (i.e., all of the
        // numbers have been handled in some previous conflict or mapping).
        conflicts.add(conflict);
        continue;
      }

      var targetNumbers = targetNumber(ambiguousCheckNumbers);
      var sourceNumbers = ambiguousCheckNumbers.values.flattened.toList();

      // If every remaining number is blacklisted to every other number, we can skip
      // the remaining checks.
      bool allBlacklisted = true;
      for(var s1 in sourceNumbers) {
        for(var s2 in sourceNumbers) {
          if(s1 != s2 && !(blacklist[s1]?.contains(s2) ?? false)) {
            allBlacklisted = false;
            break;
          }
        }
      }

      if(allBlacklisted) {
        // If there are causes or actions, present the conflict to the user;
        // otherwise, we've already done everything we need to do.
        if(conflict.causes.isNotEmpty || conflict.proposedActions.isNotEmpty) {
          conflicts.add(conflict);
        }
        continue;
      }

      // Remove the target numbers from source numbers to match the expected behavior
      // in [AmbiguousMapping].
      sourceNumbers.removeWhere((e) => targetNumbers.contains(e));

      // At this point, we might have a numbers map with only one element of each type,
      // which is an unambiguous mapping if not blacklisted.

      if(targetNumbers.length == 1) {
        var target = targetNumbers.first;
        var sources = [...sourceNumbers];
        bool allTypesHaveOneNumber = true;
        for(var list in ambiguousCheckNumbers.values) {
          if(list.length > 1) {
            allTypesHaveOneNumber = false;
            break;
          }
        }

        if(allTypesHaveOneNumber) {
          // Remove any blacklisted mappings from sources to target.
          Set<String> blacklistedSources = {};
          for(var source in sources) {
            if(blacklist[source]?.contains(target) ?? false) {
              blacklistedSources.add(source);
            }
          }
          sources.removeWhere((e) => blacklistedSources.contains(e));

          if(sources.isNotEmpty) {
            conflict.causes.add(AmbiguousMapping(
              deduplicatorName: name,
              sourceNumbers: sourceNumbers,
              targetNumbers: [target],
              sourceConflicts: false,
              targetConflicts: false,
              conflictingTypes: [],
              relevantBlacklistEntries: {},
            ));
            conflict.proposedActions.add(AutoMapping(
              sourceNumbers: sources,
              targetNumber: target,
            ));

            // Remove target and sources from the numbers map, so that we
            // don't report unnecessary AmbiguousMappings in the below check.
            for(var number in [target, ...sources]) {
              ambiguousCheckNumbers[classify(number)]!.remove(number);
            }
          }
        }
      }

      if(ambiguousCheckNumbers.deepEmpty()) {
        conflicts.add(conflict);
        continue;
      }

      var sourceConflicts = false;
      for(var number in sourceNumbers) {
        var type = classify(number);
        if(conflictingTypes.contains(type)) {
          sourceConflicts = true;
          break;
        }
      }

      var targetConflicts = targetNumbers.length > 1;

      // Find blacklist entries that are relevant to the ambiguous mapping
      Map<String, List<String>> relevantBlacklistEntries = {};
      for(var sourceNumber in sourceNumbers) {
        var blacklistEntries = blacklist[sourceNumber];
        if(blacklistEntries != null) {
          for(var number in [...targetNumbers, ...sourceNumbers]) {
            if(blacklistEntries.contains(number)) {
              relevantBlacklistEntries[sourceNumber] ??= [];
              relevantBlacklistEntries[sourceNumber]!.add(number);
            }
          }
        }
      }

      conflict.causes.add(AmbiguousMapping(
        deduplicatorName: name,
        sourceNumbers: sourceNumbers,
        targetNumbers: targetNumbers,
        sourceConflicts: sourceConflicts,
        targetConflicts: targetConflicts,
        conflictingTypes: conflictingTypes,
        relevantBlacklistEntries: relevantBlacklistEntries,
      ));
      conflicts.add(conflict);
    }

    return DeduplicationResult.ok(conflicts);
  }

  bool _badDataEntryFixTarget(String number) {
    // If the number ends with a letter, it's probably a typo or
    // data entry error of the form "TY123456L" or something,
    // which I have seen in the wild.
    if(number.contains(RegExp(r"[A-Z]$"))) {
      return true;
    }

    // If the number is all uppercase letters, it's probably a typo or
    // a badly entered number.
    if(number.startsWith(RegExp(r"[A-Z]+$"))) {
      return true;
    }

    // If the number is too long or too short for its type, it isn't
    // a valid target.
    var n = USPSAMemberNumber(number);
    if(n.type == MemberNumberType.standard && (n.internalNumber.length < 5 || n.internalNumber.length > 6)) {
      return true;
    }

    if(n.type == MemberNumberType.life && (n.numericComponent.length < 3 || n.numericComponent.length > 4)) {
      return true;
    }

    if(n.type == MemberNumberType.benefactor && (n.numericComponent.length < 2 || n.numericComponent.length > 3)) {
      return true;
    }

    return false;
  }

  /// Map ratings from one shooter to another. [source]'s history will
  /// be added to [target].
  void _mapRatings({
    required Map<String, DbShooterRating> knownShooters,
    required Map<String, String> currentMappings,
    required DbShooterRating target,
    required DbShooterRating source,
  }) {
    target.copyRatingFrom(source);
    knownShooters.remove(source.memberNumber);
    currentMappings[source.memberNumber] = target.memberNumber;

    // Three-step mapping. If the target of another member number mapping
    // is the source of this mapping, map the source of that mapping to the
    // target of this mapping.
    for(var sourceNum in currentMappings.keys) {
      var targetNum = currentMappings[sourceNum]!;

      if(targetNum == source.memberNumber && currentMappings[sourceNum] != target.memberNumber) {
        _log.i("Additionally mapping $sourceNum to ${target.memberNumber}");
        currentMappings[sourceNum] = target.memberNumber;
      }
    }
  }

  Map<String, String> _normalizeNumberCache = {};
  /// Normalized USPSA numbers are all uppercase and contain only the following letters
  /// in addition to numbers: FYTABLRD
  @override
  String normalizeNumber(String number) {
    if(_normalizeNumberCache.containsKey(number)) return _normalizeNumberCache[number]!;
    var n = number.toUpperCase().replaceAll(RegExp(r"[^FYTABLRD0-9]"), "");
    _normalizeNumberCache[number] = n;
    return n;
  }

  /// Processed USPSA numbers are identical to [normalizeNumber] normalized
  /// numbers.
  @override
  String processNumber(String number) {
    // If the number is all zeroes, it's invalid, and we won't be able to use it to 
    // identify a competitor.
    if(RegExp(r"^0+$").hasMatch(number)) {
      return "";
    }

    return normalizeNumber(number);
  }

  Map<String, String> _stripATYFYCache = {};
  String _stripATYFY(String number) {
    if(_stripATYFYCache.containsKey(number)) return _stripATYFYCache[number]!;
    var n = number.replaceFirst(RegExp(r"[ATFY]{1,3}"), "");
    _stripATYFYCache[number] = n;
    return n;
  }

  /// Return the best (i.e. longest) associate number from a list of numbers.
  String _bestAssociateNumber(List<String> numbers) {
    String? fy;
    String? ty;
    String? a;

    for(var number in numbers) {
      if(number.startsWith("FY")) fy = number;
      else if(number.startsWith("TY")) ty = number;
      else if(number.startsWith("A")) a = number;
    }
    return fy ?? ty ?? a ?? numbers.first;
  }

  List<String> alternateForms(String number) {
    var type = classify(number);
    if(type == MemberNumberType.standard) {
      var numericComponent = number.replaceAll(RegExp(r"[^0-9]"), "");
      return ["A$numericComponent", "TY$numericComponent", "FY$numericComponent"];
    }
    else if(type == MemberNumberType.international) {
      return [number, "INTL$number"];
    }
    else {
      return [number];
    }
  }

  MemberNumberType classify(String number) {
    // If the number contains no digits, treat it as a standard number so
    // it will more likely get caught as an invalid number.
    if(!number.contains(RegExp(r"[0-9]"))) return MemberNumberType.standard;

    if(number.startsWith("RD")) return MemberNumberType.regionDirector;
    if(number.startsWith("B")) return MemberNumberType.benefactor;
    // Empirically, "FL" appears to be "foreign life"
    // cf. Lise Mahoney
    // Intended to match: L<digit> and FL<digit>
    if(number.startsWith(RegExp("L[0-9]")) || number.startsWith(RegExp("FL[0-9]"))) return MemberNumberType.life;

    // Intended to match: A, TY, FY, F, TYF, and FYF.
    if(number.startsWith(RegExp(r"[ATFY]{1,3}"))) return MemberNumberType.standard;

    // International competitors sometimes enter a pure-numeric IPSC regional member number,
    // and we don't want to add A/TY/FY to those in [alternateForms] to avoid overlapping with
    // USPSA-issued member numbers. We handle the special case when an American competitor
    // enters their USPSA number without a prefix in a separate check, and treat it as a
    // data entry error.
    if(number.startsWith(RegExp(r"[0-9]"))) return MemberNumberType.international;
    // Commonly observed in the wild.
    if(number.startsWith("AB")) return MemberNumberType.international;

    return MemberNumberType.standard;
  }

  List<String> targetNumber(Map<MemberNumberType, List<String>> numbers) {
    for(var type in MemberNumberType.values.reversed) {
      var v = numbers[type];
      if(v != null && v.isNotEmpty) return v;
    }

    throw ArgumentError("Empty map provided");
  }

  List<String>? maybeTargetNumber(Map<MemberNumberType, List<String>> numbers) {
    for(var type in MemberNumberType.values.reversed) {
      var v = numbers[type];
      if(v != null && v.isNotEmpty) return v;
    }

    return null;
  }

  @override
  InlineSpan linksForMemberNumbers({
    required BuildContext context,
    required String text,
    required List<String> memberNumbers,
    TextStyle? runningStyle,
    TextStyle? linkStyle,
  }) {
    runningStyle ??= TextStyles.bodyMedium(context);
    linkStyle ??= TextStyles.linkBodyMedium(context);

    // sort member numbers by length, longest first, so that
    // we never split a longer member number by a shorter one
    // that happens to be a substring of it
    // e.g. for "53007" and "A53007", if we split by "53007" first
    // we'll end up with "A53007" -> ["A", "53007"] eventually
    memberNumbers.sort((a, b) => b.length.compareTo(a.length));

    Map<String, TextSpan> spans = {};
    for(var number in memberNumbers) {
      spans[number] = TextSpan(
        text: number,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse("https://uspsa.org/classification/$number")),
        mouseCursor: SystemMouseCursors.click,
      );
    }

    int index = 0;
    Map<int, String> numberIndexes = {};

    // Replace each member number with a guard string that will let us split
    // after the member number.
    // e.g.: "String contains A123456, a standard number" -> "String contains ZzZ0XxX, a standard number"
    List<TextSpan> allSpans = [];
    String splittableText = text;
    for(var n in memberNumbers) {
      numberIndexes[index] = n;
      splittableText = splittableText.replaceAll(n, "ZzZ${index}XxX");
      index++;
    }

    // Split the text into parts, and replace each part with a TextSpan, replacing each
    // member number guard string with the corresponding text span.
    // e.g.: "String contains ZzZ0XxX, a standard number" -> ["String contains ZzZ0", ", a standard number"]
    List<String> parts = splittableText.split("XxX");
    for(var part in parts) {
      TextSpan? linkSpan;
      // Each part should contain zero or one guard strings of the format ZzZ<index>.
      // Extract it and replace it with the corresponding TextSpan.
      var pattern = RegExp(r"ZzZ(\d+)");
      var match = pattern.firstMatch(part);
      if(match != null) {
        var index = int.parse(match.group(1)!);
        var number = numberIndexes[index];
        linkSpan = spans[number];
        part = part.replaceFirst(pattern, "");
      }

      allSpans.add(TextSpan(text: part, style: runningStyle));
      if(linkSpan != null) {
        allSpans.add(linkSpan);
      }
    }

    return TextSpan(
      children: allSpans,
    );
  }
}

extension DeepCopyMemberNumberMap<T, U> on Map<T, List<U>> {
  Map<T, List<U>> deepCopy() {
    return {
      for(var type in keys) 
        type: [...this[type]!]
    };
  }

  bool deepEmpty() {
    for(var value in values) {
      if(value.isNotEmpty) return false;
    }
    return true;
  }
}
