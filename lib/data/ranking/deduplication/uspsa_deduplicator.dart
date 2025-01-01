// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as strdiff;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("USPSADeduplicator");

class DeduplicationResult extends Result<List<Conflict>, RatingError> {
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
    var db = AnalystDatabase();
    var userMappings = ratingProject.settings.userMemberNumberMappings;
    var shooterAliases = ratingProject.settings.shooterAliases;

    Set<String> deduplicatorNames = {};

    Map<String, List<String>> namesToNumbers = {};
    Map<String, String> detectedUserMappings = {};
    Map<String, List<DbShooterRating>> ratingsByName = {};

    List<Conflict> conflicts = [];

    // Retrieve deduplicator names from the new ratings.
    // The only names that can cause conflicts are those
    // that we just added, since we do this every time we
    // add ratings.
    for(var rating in newRatings) {
      deduplicatorNames.add(rating.deduplicatorName);
    }

    // Detect conflicts.
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
    else {
      return [number];
    }
  }

  MemberNumberType classify(String number) {
    if(number.startsWith("RD")) return MemberNumberType.regionDirector;
    if(number.startsWith("B")) return MemberNumberType.benefactor;
    if(number.startsWith("L")) return MemberNumberType.life;

    return MemberNumberType.standard;
  }

  List<String> targetNumber(Map<MemberNumberType, List<String>> numbers) {
    for(var type in MemberNumberType.values.reversed) {
      var v = numbers[type];
      if(v != null && v.isNotEmpty) return v;
    }

    throw ArgumentError("Empty map provided");
  }
}