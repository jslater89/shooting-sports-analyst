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
import 'package:shooting_sports_analyst/data/ranking/deduplication/standard_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzywuzzy;

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

  /// The original number as provided by the user, which may or may not have been
  /// normalized by other processes.
  late final String originalNumber;

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
  late final bool isVanity;

  /// Whether the member number is valid.
  late final bool valid;

  /// The non-life component of this member number: the geocode and unique identifier.
  String get nonLifeNumber => "$geoCode$uniqueIdentifier";

  IcoreMemberNumber(String number) {
    originalNumber = number;
    normalizedNumber = IcoreDeduplicator.instance.normalizeNumber(number);
    var match = _icoreNumberRegex.firstMatch(normalizedNumber);
    if(match == null) {
      _log.w("Invalid ICORE number: $number");
      lifeMember = false;
      geoCode = "";
      uniqueIdentifier = number;
      isVanity = false;
      valid = false;
    }
    else {
      lifeMember = match.group(1) == "L";
      geoCode = match.group(2)!;
      uniqueIdentifier = match.group(3)!;
      isVanity = !RegExp(r'^[0-9]+$').hasMatch(uniqueIdentifier);
      valid = true;
    }
    
    if(lifeMember && isVanity) {
      type = MemberNumberType.benefactor;
    }
    else if(lifeMember) {
      type = MemberNumberType.life;
    }
    else {
      type = MemberNumberType.standard;
    }
  }

  /// Whether this member number is the same as another member number across
  /// all three components: life/standard status, geo code, and unique identifier.
  /// 
  /// Calls [sameMember] to check equality. Can be called on either another
  /// [IcoreMemberNumber] or a [String], in which case the string will be 
  /// converted to an [IcoreMemberNumber] for comparison.
  @override
  operator ==(Object other) {
    if(other is IcoreMemberNumber) {
      return sameMember(other, ignoreLifeDifference: false);
    }
    else if(other is String) {
      var otherNumber = IcoreMemberNumber(other);
      return sameMember(otherNumber, ignoreLifeDifference: false);
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(geoCode, uniqueIdentifier);

  /// Whether this member number definitely represents the same member as another
  /// member number.
  /// 
  /// If [ignoreLifeDifference] is true (the default), then a life number and a
  /// standard number with the same geocode and unique identifier will be considered
  /// the same member. Otherwise, the life/standard status must also match.
  bool sameMember(IcoreMemberNumber other, {bool ignoreLifeDifference = true}) {
    if(ignoreLifeDifference) {
      return geoCode == other.geoCode && uniqueIdentifier == other.uniqueIdentifier;
    }
    else {
      return geoCode == other.geoCode && uniqueIdentifier == other.uniqueIdentifier && lifeMember == other.lifeMember;
    }
  }

  @override
  String toString() {
    return "$lifeMember$geoCode$uniqueIdentifier";
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


class IcoreDeduplicator extends StandardDeduplicator {
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

  /// In ICORE, member numbers are one of three types:
  /// 
  /// - [MemberNumberType.standard]: an ordinary member number of the form PA1234.
  /// - [MemberNumberType.life]: a life member number of the form LPA1234.
  /// - [MemberNumberType.benefactor]: a member number with a vanity identifier, like LINREVOSHTR.
  @override
  MemberNumberType classify(String number) {
    if(number.toLowerCase().startsWith("xxx")) {
      return MemberNumberType.invalid;
    }
    var member = IcoreMemberNumber(number);
    if(member.lifeMember && !member.isVanity) {
      return MemberNumberType.life;
    }
    else if(member.lifeMember && member.isVanity) {
      return MemberNumberType.benefactor;
    }
    else {
      return MemberNumberType.standard;
    }
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

  static const similarityThreshold = 65;
  
  @override
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
  }) {
    // Since ICORE is way (_way_) simpler than USPSA in terms of member numbers, we
    // only have a few cases to consider.

    // Case 0: the trivial case, where we have two records, and they only differ by
    // life/standard status.

    // Case 1: multiple member numbers of either standard or life type, in which case
    // we propose either data fixes or blacklists.

    // Case 2: standard and life numbers in a combination that we can make reasonable
    // proposals for. Standard -> life -> life-vanity is the archetypal case.

    // Case 3: ambiguous mappings, where we may be able to propose actions, but need
    // user input to fully resolve. Typically, though, those proposed actions will be
    // hanging around from earlier stages that failed to fully resolve the conflict.

    // We lean heavily on the geocode/identifier/lifetime parameters of IcoreMemberNumber
    // to resolve conflicts, so let's precalculate those for everything.
    Map<String, IcoreMemberNumber> icoreNumbers = {};
    for(var number in numbers.values.flattened) {
      var member = IcoreMemberNumber(number);
      icoreNumbers[number] = member;

      // If we come across any cases where a member's original number is not the same
      // as the normalized number, add a DataEntryFix so that we can work with normalized
      // numbers for the rest of the process.
      if(member.originalNumber != member.normalizedNumber) {
        conflict.proposedActions.add(DataEntryFix(
          deduplicatorName: name,
          sourceNumber: member.originalNumber,
          targetNumber: member.normalizedNumber,
        ));
      }
    }

    var originalNumbers = numbers;
    var ongoingNumbers = numbers.deepCopy();

    // Case: -1: fix typos/add blacklists in all categories, so we can remove typos from
    // the source/target lists.
    for(var type in numbers.keys) {
      var numbersOfType = numbers[type] ?? [];
      // Compare numbers pairwise, add either fixes or blacklists as appropriate (if not
      // already blacklisted).
      for(var i = 0; i < numbersOfType.length; i++) {
        for(var j = i + 1; j < numbersOfType.length; j++) {
          var number1 = numbersOfType[i];
          var number2 = numbersOfType[j];
          var member1 = icoreNumbers[number1]!;
          var member2 = icoreNumbers[number2]!;
          var similarity = fuzzywuzzy.weightedRatio(member1.nonLifeNumber, member2.nonLifeNumber);

          // If the numbers are highly similar, propose a data entry fix from the second
          // number appearing to the first. Otherwise, add a blacklist entry.

          bool invalidNumbers = !member1.valid || !member2.valid;
          if(similarity > similarityThreshold || invalidNumbers) {
            var probableTarget = number1;
            var probableSource = number2;
            if(!member1.valid) {
              probableTarget = number2;
              probableSource = number1;
            }
            conflict.proposedActions.add(DataEntryFix(
              deduplicatorName: name,
              sourceNumber: probableSource,
              targetNumber: probableTarget,
            ));

            // Remove the data fix source number from the list.
            ongoingNumbers[type]!.remove(number2);
          }
          else if(!blacklist.isBlacklisted(number1, number2, bidirectional: true)) {
            conflict.proposedActions.add(Blacklist(
              sourceNumber: number1,
              targetNumber: number2,
              bidirectional: true,
            ));
          }
        }
      }
    }

    numbers = ongoingNumbers.deepCopy();

    bool singleNumberOfMultipleTypes = numbers.length > 1;
    for(var type in numbers.keys) {
      if(numbers[type]!.length != 1) {
        singleNumberOfMultipleTypes = false;
      }
    }

    // Handle various standard -> life mapping cases.
    // If we have at most one number of each type, we can do some tricks.
    if(singleNumberOfMultipleTypes) {
      IcoreMemberNumber? standard;
      IcoreMemberNumber? life;
      IcoreMemberNumber? vanity;
      if(numbers.containsKey(MemberNumberType.standard)) {
        standard = icoreNumbers[numbers[MemberNumberType.standard]!.first]!;
      }
      if(numbers.containsKey(MemberNumberType.life)) {
        life = icoreNumbers[numbers[MemberNumberType.life]!.first]!; 
      }
      if(numbers.containsKey(MemberNumberType.benefactor)) {
        vanity = icoreNumbers[numbers[MemberNumberType.benefactor]!.first]!;
      }

      // Standard can't be the best type, because we have a single number of at least
      // two types.
      // We have one of four situations:
      // 1. Standard -> Life
      // 2. Standard -> Vanity
      // 3. Life -> Vanity
      // 4. Standard -> Life -> Vanity
      var bestType = vanity != null ? MemberNumberType.benefactor : MemberNumberType.life;
      var bestMember = vanity ?? life!;

      // We'll handle each of the four situations in turn, individually, and combine them into
      // the final mapping.
      Mapping finalMapping = AutoMapping(
        sourceNumbers: [],
        targetNumber: bestMember.normalizedNumber,
      );
      bool finalMappingIsUserMapping = false;

      if(standard != null && life != null) {
        if(standard.sameMember(life)) {
          // If the standard and life numbers are the same, map standard to life. 
          // There's no need to check for blacklisting here, because
          // blacklisting PA1234 to LPA1234 is not a valid operation.
          if(!alreadyMapped(standard.normalizedNumber, life.normalizedNumber, detectedUserMappings)) {
            finalMapping.sourceNumbers.addIfMissing(standard.normalizedNumber);
          }
        }
        else if(
          standard.geoCode == life.geoCode 
          && fuzzywuzzy.weightedRatio(standard.nonLifeNumber, life.nonLifeNumber) > similarityThreshold
          && !blacklist.isBlacklisted(standard.normalizedNumber, life.normalizedNumber)
        ) {
          // If the standard and life numbers are similar, add a data entry fix from
          // the standard (presumed typo) to the life's non-life component, and map from
          // the corrected standard number to the life number, provided that the data entry
          // fix is not blacklisted.
          conflict.proposedActions.add(DataEntryFix(
            deduplicatorName: name,
            sourceNumber: standard.normalizedNumber,
            targetNumber: life.nonLifeNumber,
          ));
          finalMapping.sourceNumbers.addIfMissing(life.nonLifeNumber);
        }
        else {
          // If we can't determine a valid potential standard -> life mapping, blacklist
          // the standard number from the life number if not already blacklisted.
          if(!blacklist.isBlacklisted(standard.normalizedNumber, life.normalizedNumber)) {
            conflict.proposedActions.add(Blacklist(
              sourceNumber: standard.normalizedNumber,
              targetNumber: life.normalizedNumber,
              bidirectional: true,
            ));
          }
        }
      }

      if(standard != null && vanity != null) {
        if(standard.geoCode == vanity.geoCode) {
          // If the standard and vanity numbers have the same geocode, and are not blacklisted,
          // map from the standard number to the vanity number.
          if(!blacklist.isBlacklisted(standard.normalizedNumber, vanity.normalizedNumber)) {
            var preexistingMapping = detectedMappings[standard.normalizedNumber];
            if(preexistingMapping != null) {
              var preexistingType = classify(preexistingMapping);
              if(preexistingType == MemberNumberType.benefactor && preexistingMapping != vanity.normalizedNumber) {
                // If the preexisting mapping maps to a benefactor/vanity number, and that number
                // is not this number, then we have a cross mapping and need to tell the user.
                conflict.causes.add(
                  AmbiguousMapping(
                    deduplicatorName: name,
                    conflictingTypes: [MemberNumberType.benefactor],
                    sourceNumbers: [
                      standard.normalizedNumber,
                      if(life != null) life.normalizedNumber,
                    ],
                    targetNumbers: [vanity.normalizedNumber],
                    sourceConflicts: false,
                    targetConflicts: true,
                    relevantBlacklistEntries: {},
                    relevantMappings: {
                      standard.normalizedNumber: preexistingMapping,
                    },
                    crossMapping: true,
                  )
                );
                if(finalMapping.sourceNumbers.isNotEmpty) {
                  conflict.proposedActions.add(finalMapping);
                }
                // Not much point in proceeding past this.
                return conflict;
              }
              else {
                // Otherwise, the mapping is from standard to life, or from standard to this vanity,
                // and we don't need to add anything else here.
              }
            }
            else {
              finalMapping.sourceNumbers.addIfMissing(standard.normalizedNumber);
              conflict.causes.addIfMissing(
                const ManualReviewRecommended()
              );
            }
          }
        }
      }

      // We're doing the same exact thing for life->vanity as we did for standard->vanity.
      if(life != null && vanity != null) {
        if(life.geoCode == vanity.geoCode) {
          // If the life and vanity numbers have the same geocode, and are not blacklisted,
          // map from the life number to the vanity number.
          if(!blacklist.isBlacklisted(life.normalizedNumber, vanity.normalizedNumber)) {
            var preexistingMapping = detectedMappings[life.normalizedNumber];
            if(preexistingMapping != null) {
              var preexistingType = classify(preexistingMapping);
              if(preexistingType == MemberNumberType.benefactor && preexistingMapping != vanity.normalizedNumber) {
                // If the preexisting mapping maps to a benefactor/vanity number, and that number
                // is not this number, then we have a cross mapping and need to tell the user.
                conflict.causes.add(
                  AmbiguousMapping(
                    deduplicatorName: name,
                    conflictingTypes: [MemberNumberType.benefactor],
                    sourceNumbers: [
                      life.normalizedNumber,
                      if(standard != null) standard.normalizedNumber,
                    ],
                    targetNumbers: [vanity.normalizedNumber],
                    sourceConflicts: false,
                    targetConflicts: true,
                    relevantBlacklistEntries: {},
                    relevantMappings: {
                      life.normalizedNumber: preexistingMapping,
                    },
                    crossMapping: true,
                  )
                );
                if(finalMapping.sourceNumbers.isNotEmpty) {
                  conflict.proposedActions.add(finalMapping);
                }
                // Not much point in proceeding past this.
                return conflict;
              }
              else {
                // Otherwise, the mapping is from standard to life, and we'll handle that in
                // the life->vanity step.
              }
            }
            else {
              finalMapping.sourceNumbers.addIfMissing(life.normalizedNumber);
              conflict.causes.addIfMissing(
                const ManualReviewRecommended()
              );
            }
          }
        }
      }

      if(finalMapping.sourceNumbers.isNotEmpty) {
        conflict.proposedActions.add(finalMapping);
        if(conflict.proposedActionsResolveConflict()) {
          return conflict;
        }
      }
    }

    return conflict;
  }
}

/// State codes as used in ICORE numbers: the 2-letter US postal service codes.
const _stateCodes = r"AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|IA|ID|IL|IN|KS|KY|LA|MA|MD|ME|MI|MN|MO|MS|MT|NC"
r"|ND|NE|NH|NJ|NM|NV|NY|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VA|VT|WA|WI|WV|WY";

/// Country codes as used in ICORE numbers, including the invalid 'DEN' for Denmark in addition
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
