// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';

import '../../database/schema/ratings/shooter_rating.dart';

/// ShooterDeduplicators implement shooter deduplication: the process
/// whereby shooters in sports that can have multiple member numbers
/// per unique person (like USPSA's A/TY/FY, L, B, RD setup) are turned
/// from multiple ratings into a single rating.
abstract class ShooterDeduplicator {
  const ShooterDeduplicator();

  /// deduplicateShooters runs the deduplication logic on the inputs,
  /// editing them in place (!). USPSADeduplicator is the canonical
  /// implementation.
  ///
  /// [knownShooters] is a map of processed member numbers to ratings.
  /// Duplicated shooters must be removed from knownShooters after they
  /// are mapped.
  ///
  /// [shooterAliases] is a map of shooter names that identify the
  /// same person (i.e., maxmicheljr and maxmichel). It is necessary
  /// only when a shooter's registration name and member number
  /// change at the same time.
  ///
  /// [currentMappings] is the current list of active member number
  /// mappings generated by the rating system. Newly-created mappings
  /// as a result of this method will be added to it.
  ///
  /// [userMappings] is the list of user-specified member number mappings
  /// in rater settings, and will not be modified. Mappings identified in
  /// [userMappings] and created by this method must also be entered in
  /// [currentMappings].
  ///
  /// [mappingBlacklist] is the list of user-specified member number mapping
  /// blacklists. Numbers appearing as keys in [mappingBlacklist] must not be
  /// mapped to the corresponding values.
  RatingResult deduplicateShooters({
    required WrappedRatingGenerator ratingWrapper,
    required Map<String, DbShooterRating> knownShooters,
    required Map<String, String> shooterAliases,
    required Map<String, String> currentMappings,
    required Map<String, String> userMappings,
    required Map<String, String> mappingBlacklist,
    bool checkDataEntryErrors = true,
    bool verbose = false,
  });

  static String processName(Shooter shooter) {
    String name = "${shooter.firstName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}"
        + "${shooter.lastName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}";
    name = name.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "");

    return name;
  }

  /// If calculable, return a list of alternate forms of the provided member number.
  /// The returned list will always include the original number, even if no calculation
  /// is possible (in which case it will be the only element in the list).
  /// 
  /// In cases (like frickin' USPSA) where member 123456 may be prefixed in one of
  /// several ways without changing the numeric element (A, TY, FY) or the underlying
  /// member, we want to be able to save all of them to the database at once.
  List<String> alternateForms(String number);

  /// A normalized member number is a member number that has been processed for
  /// display purposes.
  /// 
  /// The default implementation removes all non-alphanumeric characters and
  /// converts to uppercase.
  String normalizeNumber(String number) {
    return number.toUpperCase().replaceAll(RegExp(r"[^A-Z0-9]"), "");
  }

  /// A processed member number is a member number that has been processed to
  /// meet the condition that string equality equals member equality.
  /// 
  /// The default implementation returns the normalized number.
  String processNumber(String number) {
    return normalizeNumber(number);
  }

  /// Classify a member number into a member number type.
  MemberNumberType classify(String number);

  /// Given a map of member number types to lists of member numbers, return
  /// a list of member numbers that are valid target numbers for a member
  /// number mapping.
  List<String> targetNumber(Map<MemberNumberType, List<String>> numbers);
}

/// Types of member numbers that can identify a competitor.
///
/// As of the initial writing, these are USPSA's member number categories.
/// Other sports may be added as necessary, or simply overlap with these.
enum MemberNumberType {
  standard,
  life,
  benefactor,
  regionDirector;

  bool betterThan(MemberNumberType other) {
    return other.index > this.index;
  }
}