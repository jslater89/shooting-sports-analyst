// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("USPSADeduplicator");

class DeduplicationResult extends Result<List<DeduplicatorCollision>, RatingError> {
  DeduplicationResult.ok(super.value) : super.ok();
  DeduplicationResult.err(super.error) : super.err();
}

class USPSADeduplicator extends ShooterDeduplicator {
  const USPSADeduplicator();

  @override
  Future<DeduplicationResult> deduplicateShooters({
    required DbRatingProject ratingProject,
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

    Map<String, String> detectedMappings = {};
    Map<String, String> detectedUserMappings = {};

    // The blacklist operates in subtly different ways for different
    // kinds of conflicts.
    // When checking if we can auto-map, we want to be as permissive as
    // possible—if the target of a blacklist is also the target of the
    // proposed automapping, prefer to remove the source of the blacklist
    // rather than the target.
    var blacklist = ratingProject.settings.memberNumberMappingBlacklist;

    Set<String> deduplicatorNames = {};

    Map<String, List<String>> namesToNumbers = {};
    Map<String, List<DbShooterRating>> ratingsByName = {};

    List<DeduplicatorCollision> conflicts = [];

    // Retrieve deduplicator names from the new ratings.
    // The only names that can cause conflicts are those
    // that we just added, since we do this every time we
    // add ratings.
    for(var rating in newRatings) {
      deduplicatorNames.add(rating.deduplicatorName);
    }

    // Detect conflicts for each name.
    for(var name in deduplicatorNames) {
      var ratingsRes = await ratingProject.getRatingsByDeduplicatorName(name);

      if(ratingsRes.isErr()) {
        _log.w("Failed to retrieve ratings for deduplicator name $name", error: ratingsRes.unwrapErr());
        continue;
      }

      var ratings = ratingsRes.unwrap();

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
          numbers[type] ??= [];
          numbers[type]!.add(number);
          numbersToRatings[number] = rating;
        }
      }

      // TODO: applying a user mapping may make further deduplication unnecessary.
      /* thinking aloud here...
      in what cases is further deduplication unnecessary?
      * if we have user mapping, we know that source -> target is true.
      * a better automapping is possible, but only if the target number type is better
        than the mapping's target. We should probably present that to the user as a
        proposed UserMapping rather than an AutoMapping, so we don't have to do anything
        funky with the UserMapping overrides AutoMapping priority. (If we send a UserMapping
        with all of the member numbers, it'll overwrite the old mappings in the project settings,
        so we don't need to worry about that on the next recalc.)
      * MultipleNumbersOfType conflicts are possible without exception, and also possible
        in cases where they wouldn't otherwise be possible (A123456 -> L1234, A123457 e.g.),
        since the mapped number only counts as one.
      * AmbiguousMapping conflicts are not possible with any of the source or target numbers,
        because we've already mapped manually.

        So we need to progress, but we also need to check against detectedUserMappings.
      */

      // Check if any user mappings apply to the list of ratings, and if they haven't been
      // previously applied. This can happen if we're doing a full recalculation.
      List<PreexistingMapping> preexistingMappingActions = [];
      List<AmbiguousMapping> ambiguousMappings = [];
      for(var rating in ratings) {
        // Find all of the mappings that apply to this rating.
        Map<String, String> userMappingsForRating = {};
        Map<String, String> autoMappingsForRating = {};
        for(var number in rating.knownMemberNumbers) {
          var userTarget = userMappings[number];
          var autoTarget = allMappings[number];
          if(userTarget != null && !rating.knownMemberNumbers.contains(userTarget)) {
            userMappingsForRating[number] = userTarget;
          }
          if(autoTarget != null && !rating.knownMemberNumbers.contains(autoTarget)) {
            autoMappingsForRating[number] = autoTarget;
          }
        }

        // Find all of the targets for those mappings.
        Set<String> targetNumbers = {};
        Set<String> userTargetNumbers = {};
        for(var target in userMappingsForRating.values) {
          targetNumbers.add(target);
          userTargetNumbers.add(target);
        }
        for(var target in autoMappingsForRating.values) {
          targetNumbers.add(target);
        }

        // If all of the target numbers are the same, the mappings are consistent,
        // and we can add them to preexistingMappingActions.
        if(targetNumbers.length == 1) {
          for(var source in autoMappingsForRating.keys) {
            preexistingMappingActions.add(PreexistingMapping(
              sourceNumber: source,
              targetNumber: targetNumbers.first,
            ));
            detectedMappings[source] = targetNumbers.first;
          }
          for(var source in userMappingsForRating.keys) {
            preexistingMappingActions.add(PreexistingMapping(
              sourceNumber: source,
              targetNumber: targetNumbers.first,
            ));
            detectedUserMappings[source] = targetNumbers.first;
            detectedMappings[source] = targetNumbers.first;
          }
        }
        else {
          // If there are multiple target numbers, we have a cross mapping. We might
          // be able to resolve it automatically if there's a single best target number.
          _log.w("Cross mapping for rating $rating\n    User mappings: $userMappingsForRating\n    Auto mappings: $autoMappingsForRating");
          Map<MemberNumberType, List<String>> classifiedTargetNumbers = {};
          for(var target in targetNumbers) {
            var type = classify(target);
            classifiedTargetNumbers[type] ??= [];
            classifiedTargetNumbers[type]!.add(target);
          }
          var finalTargets = targetNumber(classifiedTargetNumbers);
          if(finalTargets.length == 1) {
            var finalTarget = finalTargets.first;
            for(var source in autoMappingsForRating.keys) {
              preexistingMappingActions.add(PreexistingMapping(
                sourceNumber: source,
                targetNumber: finalTarget,
              ));
              detectedMappings[source] = finalTarget;
            }
            for(var source in userMappingsForRating.keys) {
              preexistingMappingActions.add(PreexistingMapping(
                sourceNumber: source,
                targetNumber: finalTarget,
              ));
              detectedUserMappings[source] = finalTarget;
              detectedMappings[source] = finalTarget;
            }
          }
          else {
            _log.e("Unable to resolve cross mapping");
            var targetTypes = classifiedTargetNumbers.keys.toList();
            ambiguousMappings.add(AmbiguousMapping(
              deduplicatorName: name,
              sourceNumbers: rating.knownMemberNumbers.toList(),
              targetNumbers: targetNumbers.toList(),
              sourceConflicts: false,
              targetConflicts: true,
              conflictingTypes: targetTypes,
              relevantBlacklistEntries: {},
              crossMapping: true,
            ));
            continue;
          }
        }
      }

      // If we have any entries in the ambiguousMappings list, this is a cross mapping, and
      // we need the user to tell us what to do.
      if(ambiguousMappings.isNotEmpty) {
        conflicts.add(DeduplicatorCollision(
          deduplicatorName: name,
          memberNumbers: numbers.values.flattened.toList(),
          shooterRatings: numbersToRatings,
          matches: {},
          causes: ambiguousMappings,
          proposedActions: [],
        ));
        continue;
      }

      // Otherwise, if we have preexisting mapping actions, add a 'conflict' so that the
      // resolution system knows to 
      if(preexistingMappingActions.isNotEmpty) {
        conflicts.add(DeduplicatorCollision(
          deduplicatorName: name,
          memberNumbers: numbers.values.flattened.toList(),
          shooterRatings: numbersToRatings,
          matches: {},
          causes: [],
          proposedActions: preexistingMappingActions,
        ));
      }

      // Simplest case: there is only one member number of each type
      // appearing, so we assume that the multiple entries are for
      // the same person.
      bool canAutoMap = false;
      for(var type in numbers.keys) {
        if(numbers[type]!.length == 1) {
          canAutoMap = true;
          break;
        }
      }

      if(canAutoMap) {
        // If canAutoMap is true, then all of our member number lists have
        // length 1, so we can assume that 'first' is a valid operation at
        // this point.
        var localNumbers = numbers;
        var localAllNumbers = localNumbers.values.flattened.toList();
        var target = maybeTargetNumber(localNumbers)?.first;
        var blacklisted = false;

        // Check for blacklisted mappings.
        // If N1 -> N2 is blacklisted and N2 is the target, then
        // remove N1 from the list of sources. Otherwise, remove
        // N2 from the numbers map. In both cases, recalculate
        // the target after doing so.
        for(var n1 in localAllNumbers) {
          for(var n2 in localAllNumbers) {
            if(blacklist[n1]?.contains(n2) == true) {
              if(n2 == target) {
                localNumbers.values.forEach((e) => e.remove(n1));
                var maybeTarget = maybeTargetNumber(localNumbers)?.firstOrNull;
                if(maybeTarget != null) {
                  target = maybeTarget;
                }
                else {
                  blacklisted = true;
                }
              }
              else {
                localNumbers.values.forEach((e) => e.remove(n2));
                var maybeTarget = maybeTargetNumber(localNumbers)?.firstOrNull;
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
        localAllNumbers = localNumbers.values.flattened.toList();
        var sources = localAllNumbers.where((e) => e != target).toList();

        if(target == null || sources.isEmpty) {
          blacklisted = true;
        }

        if(!blacklisted) {
          conflicts.add(DeduplicatorCollision(
            deduplicatorName: name,
            memberNumbers: localAllNumbers,
            shooterRatings: numbersToRatings,
            matches: {},
            causes: [],
            proposedActions: [
              AutoMapping(
                sourceNumbers: sources,
                targetNumber: target!,
              ),
            ],
          ));
        }

        continue;
      }


      // More complicated cases follow.

      // Assumptions at this point:
      // 1. At least one member number type has more than one member number.

      // MultipleNumbersOfType conflicts are a simpler case of AmbiguousMapping
      // conflicts. We can report MultipleNumbersOfType conflicts on their own
      // only if there are member numbers of only one type.
      List<MemberNumberType> typesWithMultipleNumbers = [];
      for(var type in numbers.keys) {
        if(numbers[type]!.length > 1) {
          typesWithMultipleNumbers.add(type);
        }
      }

      if(typesWithMultipleNumbers.length == 1 && numbers[typesWithMultipleNumbers.first]!.length > 1) {
        var type = typesWithMultipleNumbers.first;
        List<DeduplicationAction> proposedActions = [];
        // Since callers of this function will probably pass in member numbers in order of appearance,
        // for member numbers that are likely typos, the first item in the list is probably the
        // correct one. Do fuzzy string comparison to determine if we propose a blacklist for a given
        // number, or a user mapping.
        var probableTarget = numbers[type]!.first;
        List<String> sourceNumbers = [];
        for(var number in numbers[type]!.sublist(1)) {
          var strdiff = fuzzywuzzy.weightedRatio(probableTarget, number);
          if(strdiff > 65) {
            // experimentally, 65 (on a 0-100 scale) works pretty well.
            sourceNumbers.add(number);
          }
          else if(blacklist[number]?.contains(probableTarget) == false) {
            proposedActions.add(Blacklist(
              sourceNumber: number,
              targetNumber: probableTarget,
              bidirectional: true,
            ));
          }
        }

        if(sourceNumbers.isNotEmpty) {
          for(var blacklistSource in blacklist.keys) {
            var blacklistTarget = blacklist[blacklistSource]!;
            if(blacklistTarget == probableTarget) {
              sourceNumbers.remove(blacklistSource);
            }
          }

          if(sourceNumbers.isNotEmpty) {
            proposedActions.add(UserMapping(
              sourceNumbers: sourceNumbers,
              targetNumber: probableTarget,
            ));
          }
        }

        conflicts.add(DeduplicatorCollision(
          deduplicatorName: name,
          memberNumbers: numbers[typesWithMultipleNumbers.first]!,
          shooterRatings: numbersToRatings,
          matches: {},
          causes: [
            MultipleNumbersOfType(
              deduplicatorName: name,
              memberNumberType: typesWithMultipleNumbers.first,
              memberNumbers: numbers[typesWithMultipleNumbers.first]!,
            ),
          ],
          proposedActions: proposedActions,
        ));

        // In the scenario expressed by the conditional, we don't have anything else to do here.
        continue;
      }

      // Assumptions at this point:
      // 1. At least one member number type has more than one member number.
      // 2. At least two member number types have more than zero member numbers.
      // This is an ambiguous mapping, and we can't really guess about it.

      // TODO: remove any detected mappings from the numbers map.

      List<MemberNumberType> conflictingTypes = [];
      for(var type in numbers.keys) {
        if(numbers[type]!.length > 1) {
          conflictingTypes.add(type);
        }
      }

      var targetNumbers = targetNumber(numbers);
      var sourceNumbers = numbers.values.flattened.where((e) => !targetNumbers.contains(e)).toList();

      var sourceConflicts = false;
      for(var number in sourceNumbers) {
        var type = classify(number);
        if(conflictingTypes.contains(type)) {
          sourceConflicts = true;
          break;
        }
      }

      var targetConflicts = targetNumbers.length > 1;

      Map<String, List<String>> relevantBlacklistEntries = {};
      for(var number in sourceNumbers) {
        var blacklistEntries = blacklist[number];
        if(blacklistEntries != null) {
          for(var number in [...targetNumbers, ...sourceNumbers]) {
            if(blacklistEntries.contains(number)) {
              relevantBlacklistEntries[number] ??= [];
              relevantBlacklistEntries[number]!.add(number);
            }
          }
        }
      }

      conflicts.add(DeduplicatorCollision(
        deduplicatorName: name,
        memberNumbers: numbers.values.flattened.toList(),
        shooterRatings: numbersToRatings,
        matches: {},
        causes: [
          AmbiguousMapping(
            deduplicatorName: name,
            sourceNumbers: sourceNumbers,
            targetNumbers: targetNumbers,
            sourceConflicts: sourceConflicts,
            targetConflicts: targetConflicts,
            conflictingTypes: conflictingTypes,
            relevantBlacklistEntries: relevantBlacklistEntries,
          ),
        ],
        proposedActions: [],
      ));
    }

    return DeduplicationResult.ok(conflicts);
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
    if(number.startsWith("RD")) return MemberNumberType.regionDirector;
    if(number.startsWith("B")) return MemberNumberType.benefactor;
    if(number.startsWith("L")) return MemberNumberType.life;

    // A/TY/FY numbers issued to international competitors sometimes have an 'F' suffix,
    // hence 1-3.
    if(number.startsWith(RegExp(r"[ATFY]{1,3}"))) return MemberNumberType.standard;
    // International competitors sometimes enter a pure-numeric IPSC regional member number,
    // and we don't want to add A/TY/FY to those in [alternateForms] to avoid overlapping with
    // USPSA-issued member numbers.
    if(number.startsWith(RegExp(r"[0-9]"))) return MemberNumberType.international;

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
}