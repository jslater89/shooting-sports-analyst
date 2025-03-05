/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("IcoreDeduplicator");

/// Wraps ICORE numbers, providing some normalized accessors and an equality test.
/// 
/// ICORE numbers are relatively straightforward: they consist of a prefix of 2-4 letters,
/// in the form:
///  [L]<2-digit-state-code>|<3-digit-country-code><1-n-digit-number|custom-alphanumeric-string-life-only>
/// 
/// The L is a literal L, which indicates a life member if present.
/// The next element is a 2-digit US state code or a 3-digit ISO country code.
/// The final element is either a numeric ID, or in some rare cases for life members only, a
/// custom alphanumeric string. This final element is the unique identifier.
class IcoreMemberNumber {
  late final MemberNumberType type;

  /// The normalized number, rendered in all-caps alphanumeric characters.
  late final String normalizedNumber;

  /// Whether the member number is a life member.
  late final bool lifeMember;

  /// The geo code for the member number, which is the 2-character state code or 3-character country code.
  late final String geoCode;

  /// The unique identifier for the member number, which is the component following the
  /// L+state-or-country-code.
  late final String uniqueIdentifier;

  /// Whether the member number is a vanity member number, which for our purposes means
  /// that it is not a simple numeric ID.
  /// 
  /// Some vanity IDs are entirely numeric, but we treat those as non-vanity IDs.
  bool get isVanity {
    return !RegExp(r'^[0-9]+$').hasMatch(uniqueIdentifier);
  }

  IcoreMemberNumber(String number) {
    normalizedNumber = IcoreDeduplicator.instance.normalizeNumber(number);
    var match = _icoreNumberRegex.firstMatch(normalizedNumber);
    if(match == null) {
      throw ArgumentError("Invalid ICORE number: $number");
    }
    lifeMember = match.group(1) == "L";
    geoCode = match.group(2)!;
    uniqueIdentifier = match.group(3)!;
  }

  /// Whether this member number is the same as another member number.
  /// 
  /// This is true across lifetime memeber number upgrades, but not across
  /// vanity member number changes.
  @override
  operator ==(Object other) {
    if(other is IcoreMemberNumber) {
      return sameMember(other);
    }
    else if(other is String) {
      var otherNumber = IcoreMemberNumber(other);
      return sameMember(otherNumber);
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(geoCode, uniqueIdentifier);

  bool sameMember(IcoreMemberNumber other) {
    return geoCode == other.geoCode && uniqueIdentifier == other.uniqueIdentifier;
  }
}

/// A regex for matching ICORE numbers.
/// 
/// Capture group 1: "L" if life member, empty/null otherwise.
/// 
/// Capture group 2: geo code, either an ISO-3166-1 country code or a USPS state code.
/// 
/// Capture group 3: the unique identifier, which is a 1-12 character string of non-whitespace characters.
final _icoreNumberRegex = RegExp(r'^(L?)(' + "$_countryCodes|$_stateCodes" + r')([^\s]{1,12})$');


class IcoreDeduplicator extends ShooterDeduplicator {
  IcoreDeduplicator._();

  static final _instance = IcoreDeduplicator._();

  static IcoreDeduplicator get instance => _instance;
  factory IcoreDeduplicator() => _instance;

  @override
  List<String> alternateForms(String number, {bool includeInternationalVariants = false}) {
    var member = IcoreMemberNumber(number);
    if(!member.lifeMember) {
      return [member.normalizedNumber, "L${member.normalizedNumber}"];
    }
    else {
      return [member.normalizedNumber, member.normalizedNumber.replaceFirst("L", "")];
    }
  }

  @override
  MemberNumberType classify(String number) {
    if(number.toLowerCase().startsWith("xxx")) {
      return MemberNumberType.invalid;
    }
    var member = IcoreMemberNumber(number);
    if(member.lifeMember) {
      return MemberNumberType.life;
    }
    else {
      return MemberNumberType.standard;
    }
  }

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

    await progressCallback?.call(0, 2, "Preparing data");

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

      var conflict = DeduplicationCollision(
        deduplicatorName: name,
        memberNumbers: numbers.deepCopy(),
        shooterRatings: numbersToRatings,
        matches: {},
        causes: [],
        proposedActions: [],
      );

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

      // At this point, we've exhausted what we have in common with USPSA.
      // Now we're doing the ICORE-specific detection.

      // Since ICORE is way (_way_) simpler than USPSA in terms of member numbers, we
      // only have a few cases to consider.

      // Case 1: multiple member numbers of either standard or life type, in which case
      // we propose either data fixes or blacklists.

      // Case 2: standard and life numbers in a combination that we can make reasonable
      // proposals for. Standard -> life -> life-vanity is the archetypal case.

      // Case 3: ambiguous mappings, where we may be able to propose actions, but need
      // user input to fully resolve. Typically, though, those proposed actions will be
      // hanging around from earlier stages that failed to fully resolve the conflict.
    }

    return DeduplicationResult.ok(conflicts);
  }

  @override
  List<String>? maybeTargetNumber(Map<MemberNumberType, List<String>> numbers) {
    if(numbers.containsKey(MemberNumberType.standard) && numbers.containsKey(MemberNumberType.life)) {
      return numbers[MemberNumberType.life]!;
    }
    else {
      return null;
    }
  }

  @override
  List<String> targetNumber(Map<MemberNumberType, List<String>> numbers) {
    if(numbers.containsKey(MemberNumberType.standard) && numbers.containsKey(MemberNumberType.life)) {
      return numbers[MemberNumberType.life]!;
    }
    else {
      throw ArgumentError("Empty map provided");
    }
  }
}

/// State codes as used in ICORE numbers: the 2-letter US postal service codes.
const _stateCodes = r"AZ|CA|CO|CT|DE|FL|GA|HI|IA|ID|IL|IN|KS|KY|MA|MD|ME|MI|MN|MO|MS|MT|NC"
r"|ND|NE|NH|NJ|NM|NV|NY|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VA|WA|WI|WV|WY";

/// Country codes as used in ICORE numbers, including the incorrect 'DEN' for Denmark in addition
/// to the official ISO-3166-1 codes in [_officialCountryCodes].
const _countryCodes = "DEN|$_officialCountryCodes";

/// All official 3-character ISO-3166-1 country codes.
const _officialCountryCodes = r"ABW|AFG|AGO|AIA|ALA|ALB|AND|ARE|ARG|ARM|ASM|ATA|ATF|ATG|AUS|AUT"
r"|AZE|BDI|BEL|BEN|BES|BFA|BGD|BGR|BHR|BHS|BIH|BLM|BLR|BLZ|BMU|BOL|BRA|BRB|BRN|BTN|BVT"
r"|BWA|CAF|CAN|CCK|CHE|CHL|CHN|CIV|CMR|COD|COG|COK|COL|COM|CPV|CRI|CUB|CUW|CXR|CYM|CYP"
r"|CZE|DEU|DJI|DMA|DNK|DOM|DZA|ECU|EGY|ERI|ESH|ESP|EST|ETH|FIN|FJI|FLK|FRA|FRO|FSM|GAB"
r"|GBR|GEO|GGY|GHA|GIB|GIN|GLP|GMB|GNB|GNQ|GRC|GRD|GRL|GTM|GUF|GUM|GUY|HKG|HMD|HND|HRV"
r"|HTI|HUN|IDN|IMN|IND|IOT|IRL|IRN|IRQ|ISL|ISR|ITA|JAM|JEY|JOR|JPN|KAZ|KEN|KGZ|KHM|KIR"
r"|KNA|KOR|KWT|LAO|LBN|LBR|LBY|LCA|LIE|LKA|LSO|LTU|LUX|LVA|MAC|MAF|MAR|MCO|MDA|MDG|MDV"
r"|MEX|MHL|MKD|MLI|MLT|MMR|MNE|MNG|MNP|MOZ|MRT|MSR|MTQ|MUS|MWI|MYS|MYT|NAM|NCL|NER|NFK"
r"|NGA|NIC|NIU|NLD|NOR|NPL|NRU|NZL|OMN|PAK|PAN|PCN|PER|PHL|PLW|PNG|POL|PRI|PRK|PRT|PRY"
r"|PSE|PYF|QAT|REU|ROU|RUS|RWA|SAU|SDN|SEN|SGP|SGS|SHN|SJM|SLB|SLE|SLV|SMR|SOM|SPM|SRB"
r"|SSD|STP|SUR|SVK|SVN|SWE|SWZ|SXM|SYC|SYR|TCA|TCD|TGO|THA|TJK|TKL|TKM|TLS|TON|TTO|TUN"
r"|TUR|TUV|TWN|TZA|UGA|UKR|UMI|URY|USA|UZB|VAT|VCT|VEN|VGB|VIR|VNM|VUT|WLF|WSM|YEM|ZAF"
r"|ZMB|ZWE";
