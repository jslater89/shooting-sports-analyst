/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/rating_event.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/rating_project.dart';
// import 'package:shooting_sports_analyst/data/db/object/rating/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/model/model_utils.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';
import 'package:shooting_sports_analyst/data/ranking/timings.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart' as newShooter;
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as strdiff;
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("Rater");

class Rater {
  List<PracticalMatch> _matches;
  List<PracticalMatch> _ongoingMatches;

  /// Maps processed member numbers to shooter ratings.
  ///
  /// Contains only canonical entries. Other member numbers for shooters are
  /// in _memberNumberMappings.
  Map<String, ShooterRating> knownShooters = {};

  /// Contains all mappings for normal-to-lifetime member number switches.
  ///
  /// All member numbers are processed.
  Map<String, String> _memberNumberMappings = {};

  /// Contains mappings that should not be made automatically.
  ///
  /// Keys in this map will not be mapped to values in this map.
  /// More precisely, if the target number for an N-number mapping
  /// is a value in this map, the key to that value will not be
  /// included in the N-number mapping.
  Map<String, String> _memberNumberMappingBlacklist = {};

  MemberNumberCorrectionContainer _dataCorrections;

  /// Contains member number mappings configured in the project settings.
  ///
  /// These will be used preferentially. Member numbers appearing as keys
  /// in this table will _not_ be automatically mapped.
  Map<String, String> _userMemberNumberMappings = {};

  /// Contains processed names (lowercase, no punctuation) used to assist
  /// the automatic member number mapper in doing its job.
  Map<String, String> _shooterAliases = {};

  /// Contains every member number encountered, who has shot at least one stage.
  Set<String> _memberNumbersEncountered = Set<String>();

  Map<String, String> get memberNumberMappings => {}..addAll(_memberNumberMappings);
  Set<String> get memberNumbersEncountered => <String>{}..addAll(_memberNumbersEncountered);

  RatingSystem ratingSystem;

  RaterGroup group;

  OldFilterSet get filters => group.filters;

  bool byStage;
  List<String> memberNumberWhitelist;
  Future<void> Function(int, int, String? eventName)? progressCallback;
  final int progressCallbackInterval;
  bool verbose;
  bool checkDataEntryErrors;

  Timings timings = Timings();

  Set<ShooterRating> get uniqueShooters => <ShooterRating>{}..addAll(knownShooters.values);

  Map<String, List<Division>> recognizedDivisions = {};

  Rater({
    required List<PracticalMatch> matches,
    required List<PracticalMatch> ongoingMatches,
    required this.ratingSystem,
    required this.group,
    this.byStage = false,
    this.progressCallback,
    this.progressCallbackInterval = RatingHistory.progressCallbackInterval,
    this.checkDataEntryErrors = true,
    Map<String, String>? shooterAliases,
    Map<String, String> userMemberNumberMappings = const {},
    Map<String, String> memberNumberMappingBlacklist = const {},
    required MemberNumberCorrectionContainer dataCorrections,
    this.verbose = true,
    this.recognizedDivisions = const {},
    this.memberNumberWhitelist = const []})
      : this._matches = matches,
        this._ongoingMatches = ongoingMatches,
        this._memberNumberMappingBlacklist = memberNumberMappingBlacklist,
        this._userMemberNumberMappings = userMemberNumberMappings,
        this._dataCorrections = dataCorrections
  {
    if(shooterAliases != null) this._shooterAliases = shooterAliases;
    else this._shooterAliases = defaultShooterAliases; 

    _matches.sort((a, b) {
      if(a.date == null && b.date == null) {
        return 0;
      }
      if(a.date == null) return -1;
      if(b.date == null) return 1;

      return a.date!.compareTo(b.date!);
    });
  }

  Rater.copy(Rater other) :
        this.knownShooters = {},
        this._matches = other._matches.map((m) => m.copy()).toList(),
        this._ongoingMatches = [], // updated in constructor body
        this.byStage = other.byStage,
        this._memberNumbersEncountered = Set()..addAll(other._memberNumbersEncountered),
        this._memberNumberMappings = {}..addAll(other._memberNumberMappings),
        this._memberNumberMappingBlacklist = {}..addAll(other._memberNumberMappingBlacklist),
        this._userMemberNumberMappings = {}..addAll(other._userMemberNumberMappings),
        this._dataCorrections = other._dataCorrections,
        this._shooterAliases = {}..addAll(other._shooterAliases),
        this.group = other.group,
        this.verbose = other.verbose,
        this.checkDataEntryErrors = other.checkDataEntryErrors,
        this.memberNumberWhitelist = other.memberNumberWhitelist,
        this.progressCallbackInterval = other.progressCallbackInterval,
        this.ratingSystem = other.ratingSystem {
    this._ongoingMatches = _matches.where((match) => other._ongoingMatches.any((otherMatch) => match.practiscoreId == otherMatch.practiscoreId)).toList();
    for(var entry in _memberNumberMappings.entries) {
      if (entry.key == entry.value) {
        // If, per the member number mappings, this is the canonical mapping, copy it immediately.
        // (The canonical mapping is the one where mappings[num] = num—i.e., no mapping)
        knownShooters[entry.value] = ratingSystem.copyShooterRating(other.knownShooter(entry.value));
      }
      // Otherwise, it's an non-canonical number, so we can skip it
    }
  }

  /// Add shooters from a set of matches without adding the matches, since we do the best job of shooter
  /// mapping when we operate with as much data as possible.
  ///
  /// Used by keep-history mode. (Or maybe not.)
  RatingResult addAndDeduplicateShooters(List<PracticalMatch> matches) {
    DateTime start = DateTime.now();
    if(Timings.enabled) start = DateTime.now();
    for(PracticalMatch m in matches) {
      _addShootersFromMatch(m, encounter: true);
    }
    if(Timings.enabled) timings.addShootersMillis = (DateTime.now().difference(start).inMicroseconds / 1000);
    if(Timings.enabled) timings.shooterCount += knownShooters.length;

    if(Timings.enabled) start = DateTime.now();
    var result = _deduplicateShooters();
    if(Timings.enabled) timings.dedupShootersMillis = (DateTime.now().difference(start).inMicroseconds / 1000);

    return result;
  }

  // Future<void> deserializeFrom(List<DbMemberNumberMapping> mappings, List<DbShooterRating> ratings, Map<DbShooterRating, List<DbRatingEvent>> eventsByRating) async {
  //   // Mappings contains only the interesting ones, i.e. number != mapping
  //   // The rest get added later.
  //
  //   // Track the reverse mappings for now, so that we can tell the rating
  //   // deserializer a mapped shooter's first number.
  //   // TODO: triple mappings will break this; needs to be a list!
  //   var reverseMappings = <String, String>{};
  //   for(var m in mappings) {
  //     _memberNumberMappings[m.number] = m.mapping;
  //     reverseMappings[m.mapping] = m.number;
  //   }
  //
  //   for(var r in ratings) {
  //     var numbers = [r.memberNumber];
  //
  //     // If we have a reverse mapping (i.e., new member number to old),
  //     // add that to the list
  //     if(reverseMappings.containsKey(r.memberNumber)) {
  //       numbers.add(reverseMappings[r.memberNumber]!);
  //     }
  //
  //     ShooterRating rating = await r.deserialize(eventsByRating[r]!, numbers);
  //     _memberNumbersEncountered.add(rating.memberNumber);
  //     _memberNumbersEncountered.add(processMemberNumber(rating.originalMemberNumber));
  //     knownShooters[rating.memberNumber] = rating;
  //   }
  // }

  Future<RatingResult> calculateInitialRatings() async {
    late DateTime start;

    DateTime wallStart = DateTime.now();

    if(Timings.enabled) start = DateTime.now();
    for(PracticalMatch m in _matches) {
      _addShootersFromMatch(m);
    }
    if(Timings.enabled) timings.addShootersMillis = (DateTime.now().difference(start).inMicroseconds / 1000);
    if(Timings.enabled) timings.shooterCount += knownShooters.length;

    if(Timings.enabled) start = DateTime.now();

    var dedupResult = _deduplicateShooters();
    if(dedupResult.isErr()) return dedupResult;

    if(Timings.enabled) timings.dedupShootersMillis = (DateTime.now().difference(start).inMicroseconds / 1000);

    int totalSteps = _matches.length;
    int currentSteps = 0;

    for(PracticalMatch m in _matches) {
      var onlyDivisions = recognizedDivisions[m.practiscoreId];
      if(onlyDivisions != null) {
        var divisionsOfInterest = filters.divisions.entries.where((e) => e.value).map((e) => e.key).toList();

        // Process this iff onlyDivisions contains at least one division of interest
        // e.g. this rater/dOI is prod, oD is open/limited; oD contains 0 of dOI, so
        // skip.
        //
        // e.g. this rater/dOI is lim/CO, oD is open/limited; oD contains 1 of dOI,
        // so don't skip.
        bool skip = true;
        for(var d in divisionsOfInterest) {
          if(onlyDivisions.contains(d)) {
            skip = false;
            break;
          }
        }
        if(skip) {
          continue;
        }
      }

      if(Timings.enabled) start = DateTime.now();
      _rankMatch(m);
      if(Timings.enabled) timings.rateMatchesMillis += (DateTime.now().difference(start).inMicroseconds / 1000);
      if(Timings.enabled) timings.matchCount += 1;

      currentSteps += 1;
      if(currentSteps % progressCallbackInterval == 0) await progressCallback?.call(currentSteps, totalSteps, m.name);
    }

    if(Timings.enabled) start = DateTime.now();
    _removeUnseenShooters();
    if(Timings.enabled) timings.removeUnseenShootersMillis += (DateTime.now().difference(start).inMicroseconds / 1000);

    List<int> matchLengths = [];
    List<int> matchRoundCounts = [];
    List<int> stageRoundCounts = [];
    List<double> dqsPer100 = [];

    for(var m in _matches) {
      var totalRounds = 0;
      var stages = 0;
      for(var s in m.stages) {
        if(s.type == Scoring.chrono) continue;

        stages += 1;
        totalRounds += s.minRounds;
        stageRoundCounts.add(s.minRounds);

        if(s.minRounds <= 4) _log.d("${m.name} ${s.name} ${s.minRounds}rds");
      }
      matchLengths.add(stages);
      matchRoundCounts.add(totalRounds);

      int dqs = 0;
      for(var s in m.shooters) {
        if(s.dq) dqs += 1;
      }
      dqsPer100.add(dqs * (100 / m.shooters.length));
    }

    matchLengths.sort();
    matchRoundCounts.sort();
    stageRoundCounts.sort();
    dqsPer100.sort();

    var matchLengthMode = mode(matchLengths);
    var stageRoundsMode = mode(stageRoundCounts);
    var matchRoundsMode = mode(matchRoundCounts);

    if(Timings.enabled) timings.wallTimeMillis += DateTime.now().difference(wallStart).inMilliseconds;

    _log.i("Initial ratings complete for ${knownShooters.length} shooters in ${_matches.length} matches in ${filters.activeDivisions.toList()}");
    _log.i("Match length in stages (min/max/average/median/mode): ${matchLengths.min}/${matchLengths.max}/${matchLengths.average.toStringAsFixed(1)}/${matchLengths[matchLengths.length ~/ 2]}/$matchLengthMode");
    _log.i("Match length in rounds (average/median/mode): ${matchRoundCounts.min}/${matchRoundCounts.max}/${matchRoundCounts.average.toStringAsFixed(1)}/${matchRoundCounts[matchRoundCounts.length ~/ 2]}/$matchRoundsMode");
    _log.i("Stage length in rounds (average/median/mode): ${stageRoundCounts.min}/${stageRoundCounts.max}/${stageRoundCounts.average.toStringAsFixed(1)}/${stageRoundCounts[stageRoundCounts.length ~/ 2]}/$stageRoundsMode");
    _log.i("DQs per 100 shooters (average/median): ${dqsPer100.min.toStringAsFixed(3)}/${dqsPer100.max.toStringAsFixed(3)}/${dqsPer100.average.toStringAsFixed(3)}/${dqsPer100[dqsPer100.length ~/ 2].toStringAsFixed(3)}");
    // _log.i("Stage round counts: $stageRoundCounts");

    return RatingResult.ok();
  }

  RatingResult addMatch(PracticalMatch match) {
    _cachedStats = null;
    _matches.add(match);

    int changed = _addShootersFromMatch(match);
    var result = _deduplicateShooters();
    if(result.isErr()) return result;

    _rankMatch(match);

    _removeUnseenShooters();

    _log.i("Ratings update complete for $changed shooters (${knownShooters.length} total) in ${_matches.length} matches in ${filters.activeDivisions.toList()}");
    return RatingResult.ok();
  }

  /// Returns the number of shooters added or updated.
  ///
  /// Use [encounter] if you want shooters to be added regardless of whether they appear
  /// in scores. (i.e., shooters who DQ on the first stage, or are no-shows but still included in the data)
  int _addShootersFromMatch(PracticalMatch match, {bool encounter = false}) {
    int added = 0;
    int updated = 0;
    var shooters = _getShooters(match);
    for(Shooter s in shooters) {
      var processed = processMemberNumber(s.memberNumber);
      var corrections = _dataCorrections.getByInvalidNumber(processed);
      var name = _processName(s);
      for(var correction in corrections) {
          if (correction.name == name) {
            processed = correction.correctedNumber;
            break;
          }
      }
      if(processed.isEmpty) {
        var emptyCorrection = _dataCorrections.getEmptyCorrectionByName(name);
        if(emptyCorrection != null) {
          processed = emptyCorrection.correctedNumber;
        }
      }
      if(processed.isNotEmpty && !s.reentry) {
        s.memberNumber = processed;
        var rating = maybeKnownShooter(s.memberNumber);
        if(rating == null) {
          knownShooters[s.memberNumber] = ratingSystem.newShooterRating(s, date: match.date);
          added += 1;
          if(encounter) _encounteredMemberNumber(s.memberNumber);
        }
        else {
          // Update names for existing shooters on add, to eliminate the Mel Rodero -> Mel Rodero II problem in the L2+ set
          rating.firstName = s.firstName;
          rating.lastName = s.lastName;
          updated += 1;
        }
      }
    }

    if(Timings.enabled) timings.matchEntryCount += shooters.length;
    return added + updated;
  }

  ShooterRating? maybeKnownShooter(String processedMemberNumber) {
    var shooter = knownShooters[processedMemberNumber];
    if(shooter == null) {
      var number = _memberNumberMappings[processedMemberNumber];
      if(number != processedMemberNumber) shooter = knownShooters[number];
    }

    return shooter;
  }

  ShooterRating knownShooter(String processedMemberNumber) {
    return maybeKnownShooter(processedMemberNumber)!;
  }

  ShooterRating? ratingFor(Shooter s) {
    var processed = processMemberNumber(s.memberNumber);
    return maybeKnownShooter(processed);
  }

  ShooterRating? ratingForNew(newShooter.MatchEntry s) {
    var processed = processMemberNumber(s.memberNumber);
    return maybeKnownShooter(processed);
  }

  String _processName(Shooter shooter) {
    String name = "${shooter.firstName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}"
        + "${shooter.lastName.toLowerCase().replaceAll(RegExp(r"\s+"), "")}";
    name = name.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "");

    return name;
  }

  RatingResult _deduplicateShooters() {
    Map<String, List<String>> namesToNumbers = {};

    Map<String, String> detectedUserMappings = {};

    Map<String, List<ShooterRating>> ratingsByName = {};

    for(var num in knownShooters.keys) {
      var userMapping = _userMemberNumberMappings[num];
      if(userMapping != null) {
        detectedUserMappings[num] = userMapping;
      }

      var shooter = knownShooters[num]!;
      var name = _processName(shooter);

      var finalName = _shooterAliases[name] ?? name;

      namesToNumbers[finalName] ??= [];
      namesToNumbers[finalName]!.add(num);
      if(userMapping != null) namesToNumbers[finalName]!.add(userMapping);

      ratingsByName[finalName] ??= [];
      ratingsByName[finalName]!.add(shooter);

      _memberNumberMappings[num] ??= num;
    }

    // TODO: three-step mapping
    // TODO: see other TODO in this file about triple mapping
    // Say we have John Doe, A12345 in the set already, and
    // John Doe, L1234 shows up. We have:
    // 1. John Doe, A12345 with history
    // 2. John Doe, L1234 with no history
    // 3. _memberNumberMappings[12345] = 12345, and _memberNumberMappings[1234] = 1234;
    //
    // We get:
    // 1. John Doe, L1234 with history
    // 2. _memberNumberMappings[12345] = 1234, and ...[1234] = 1234;
    //
    // If we add another number for Doe (AD8, say) after the first update, we have:
    // 1. John Doe, L1234 with history
    // 2. John Doe, AD8 with no history
    // 3. _memberNumberMappings[12345] and [1234] = 1234
    //
    // We want:
    // 1. John Doe, AD8 with history
    // 2. _memberNumberMappings[12345], [1234], and [8] = 8
    //
    // We won't currently get that, because we don't have any reference to 12345
    // to update it--it's not in knownShooters.keys anymore. At the moment, though,
    // that will only cause trouble if someone uses their A/TY/FY number after getting
    // both a lifetime number and a BoD/pres number, which seems unlikely.
    //
    // We'll want to improve the detection logic: basically, only map when we're going
    // 'downhill', from a 5-6-digit A number to a 4-digit L number (or maybe a 4-5-digit L
    // number?) to a 1-3-digit BoD/pres number. Or maybe not. Hard problem.

    for(var name in namesToNumbers.keys) {
      var list = namesToNumbers[name]!;

      if(list.length >= 2) {
        // There are three categories of number, and we only map from 'high' to 'low':
        // 4-6 digit A/TY/FY (>=9000)
        // 3-4 digit L (>=L100)
        // 1-3-digit B (>=B1)
        // 1-3-digit AD/RD (<=99)

        // To automatically map any given shooter, we need:
        // 1. No more than 4 numbers (minus manual mappings)
        // 2. One number per category (minus manual mappings)
        // 3. At most one number with history
        // 4. Numbers not already mapped to the target.
        // 5. No numbers mapped to any numbers that aren't in list

        // Verify 1 and 2
        Map<_MemNumType, List<String>> numbers = {};
        bool automaticMappingFailed = false;
        _MemNumType? failedType;
        for(var n in list) {
          var type = _MemNumType.classify(n);
          numbers[type] ??= [];

          // The Joey Sauerland rule
          if(!numbers[type]!.contains(n)) {
            numbers[type]!.add(n);
          }
        }

        var bestNumberOptions = _MemNumType.targetNumber(numbers);
        String? bestCandidate;

        if(bestNumberOptions.length == 1) bestCandidate = bestNumberOptions.first;

        for(var type in numbers.keys) {
          // New list so we can remove blacklisted options
          var nList = []..addAll(numbers[type]!);

          for(var n in nList) {
            if(bestCandidate != null && _memberNumberMappingBlacklist[n] == bestCandidate) {
              numbers[_MemNumType.classify(bestCandidate)]!.remove(bestCandidate);
            }
          }

          nList = []..addAll(numbers[type]!);
          if(nList.length <= 1) continue;

          // To have >1 number in the same type and still be able to map
          // automatically, it must be part of a valid user mapping.
          Set<String> legalValues = {};
          for(var n in nList) {
            var userMapping = _userMemberNumberMappings[n];
            if(userMapping != null && nList.contains(userMapping)) {
              legalValues.add(n);
              legalValues.add(userMapping);
            }
          }

          for(var n in nList) {
            if(!legalValues.contains(n)) {
              automaticMappingFailed = true;
              failedType = type;
            }
          }
        }

        if(automaticMappingFailed) {
          if(verbose) _log.i("Automapping failed for $name with numbers $list: multiple numbers of type ${failedType?.name}");
          if(checkDataEntryErrors && failedType != null && numbers[failedType]!.length == 2) {
            var n1 = numbers[failedType]![0];
            var n2 = numbers[failedType]![1];

            // Blacklisting two numbers in the same type means we should ignore them.

            // TODO: we also need a blacklist solution for this:
            // John Doe           John Doe
            //  A12345             A67890
            //  L1234
            // What we need in the project settings is 'blacklist A67890 -> L1234'.
            // We'll need to make blacklists into a list for each member number, since
            // A67890 may be blacklisted against several numbers.
            //
            // Then we also need to check that before saying 'automatic mapping failed'.
            // That is, if A67890's blacklist list contains the best target for this mapping,
            // remove A67890 from the 'numbers' map.
            //
            // TODO: UI for this
            // A dialog box with a column for 'is one shooter' and 'is not that shooter'.
            // Everything in 'is not that shooter' will get blacklisted against everything in
            // 'is one shooter'.
            if(_memberNumberMappingBlacklist[n1] == n2 || _memberNumberMappingBlacklist[n2] == n1) {
              _log.i("Mapping is blacklisted");
              continue;
            }
            else if (strdiff.ratio(n1, n2) > 65 || n1.length > 6 || n2.length > 6) {
              var s1 = knownShooters[n1];
              var s2 = knownShooters[n2];
              if(s1 != null && s2 != null) {
                _log.d("$name ");
                return RatingResult.err(ShooterMappingError(
                  culprits: [s1, s2],
                  accomplices: {},
                  dataEntry: true,
                ));
              }
            }
            else {
              var s1 = knownShooters[n1];
              var s2 = knownShooters[n2];
              _log.w("$s1 ($n1) and $s2 ($n2) could not be mapped but may be the same person");
              continue;
            }
          }
          else {
            _log.i("More than 2 member numbers");
            continue;
          }
        }

        // Reset this, now that we've filtered out everything we can.
        bestNumberOptions = _MemNumType.targetNumber(numbers);
        bestCandidate = null;

        // options will only be length > 1 if we have a manual mapping in the best number options,
        // so pick the first one that's a target.
        if(bestNumberOptions.length > 1) {
          bool found = false;
          for(var n in bestNumberOptions) {
            var m = _userMemberNumberMappings[n];
            if(m != null) {
              bestCandidate = m;
              found = true;
              break;
            }
          }
          if(!found) throw StateError("bestNumber not set");
        }
        else {
          bestCandidate = bestNumberOptions.first;
        }

        String bestNumber = bestCandidate!;

        // Whether any of the numbers are not mapped to [bestNumber].
        bool unmapped = false;

        // Whether any of the numbers are mapped to something not in the list of numbers. If this is
        // true, we have a weird state where something is mapped and not supposed to be.
        bool crossMapped = false;

        // A list of blacklisted member numbers.
        // Should this come sooner?
        List<String> blacklisted = [];

        for(var nList in numbers.values) {
          for(var n in nList) {
            if (_memberNumberMappings[n] == bestNumber) {
              unmapped = true;
            }
            else {
              var target = _memberNumberMappings[n];
              if (!numbers.values.flattened.contains(target)) crossMapped = true;
              if (_memberNumberMappingBlacklist[n] == target) {
                blacklisted.add(n);
              }
            }
          }
        }

        for(var n in blacklisted) {
          numbers.removeWhere((key, value) => value.contains(n));
        }

        if(!unmapped) {
          if(verbose) _log.v("Nothing to do for $name and $list; all mapped to $bestNumber already");
          continue;
        }

        if(crossMapped) {
          if(verbose) _log.v("$name with $list has cross mappings");
          continue;
        }

        // If, after all other checks, we still have two shooters with history...
        List<ShooterRating> withHistory = [];
        for(var n in numbers.values) {
          var rating = knownShooters[n];
          if(rating != null && rating.length > 0) withHistory.add(rating);
        }

        if(withHistory.length > 1) {
          if(verbose) _log.w("Ignoring $name with numbers $list: ${withHistory.length} ratings have history: $withHistory");
          Map<ShooterRating, List<ShooterRating>> accomplices = {};

          for(var culprit in withHistory) {
            accomplices[culprit] = []..addAll(ratingsByName[_processName(culprit)]!);
            accomplices[culprit]!.remove(culprit);
          }

          return RatingResult.err(ShooterMappingError(
            culprits: withHistory,
            accomplices: accomplices,
          ));
        }

        if(verbose) _log.v("Shooter $name has >=2 member numbers, mapping: ${numbers.values.flattened.toList()} to $bestNumber");

        var target = knownShooters[bestNumber]!;

        for(var n in numbers.values.flattened) {
          if(n == bestNumber) continue;

          var source = knownShooters[n];
          if(source != null) {
            // If source was not previously mapped, do the full mapping.
            _mapRatings(target, source);
          }
          else {
            // Otherwise, source was previously mapped, so just update the source->target
            // entry in the map to point to the new true rating.
            _memberNumberMappings[n] = bestNumber;
          }
        }
      }
    }

    return RatingResult.ok();
  }

  /// Map ratings from one shooter to another. [source]'s history will
  /// be added to [target].
  void _mapRatings(ShooterRating target, ShooterRating source) {
    target.copyRatingFrom(source);
    knownShooters.remove(source.memberNumber);
    _memberNumberMappings[source.memberNumber] = target.memberNumber;

    // Three-step mapping. If the target of another member number mapping
    // is the source of this mapping, map the source of that mapping to the
    // target of this mapping.
    for(var sourceNum in _memberNumberMappings.keys) {
      var targetNum = _memberNumberMappings[sourceNum]!;

      if(targetNum == source.memberNumber && _memberNumberMappings[sourceNum] != target.memberNumber) {
        _log.i("Additionally mapping $sourceNum to ${target.memberNumber}");
        _memberNumberMappings[sourceNum] = target.memberNumber;
      }
    }
  }

  void _removeUnseenShooters() {
    List<String> shooterNumbers = knownShooters.keys.toList();
    for(String num in shooterNumbers) {
      if(!_memberNumbersEncountered.contains(num)) {
        knownShooters.remove(num);
        _memberNumberMappings.remove(num);
        _memberNumberMappings.removeWhere((key, value) => value == num);
      }
    }
  }

  List<Shooter> _getShooters(PracticalMatch match, {bool verify = false}) {
    var shooters = <Shooter>[];
    shooters = match.filterShooters(
      filterMode: filters.mode,
      divisions: filters.activeDivisions.toList(),
      powerFactors: [],
      classes: [],
      allowReentries: false,
    );

    for(var shooter in shooters) {
      shooter.memberNumber = processMemberNumber(shooter.memberNumber);
    }

    if(verify) {
      shooters.retainWhere((element) => _verifyShooter(element));
    }

    return shooters;
  }

  void _rankMatch(PracticalMatch match) {
    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    var shooters = _getShooters(match, verify: true);
    var scores = match.getScores(shooters: shooters, scoreDQ: byStage);
    if(Timings.enabled) timings.getShootersAndScoresMillis += (DateTime.now().difference(start).inMicroseconds / 1000);


    int changeCount = 0;
    if(Timings.enabled) start = DateTime.now();
    // Based on strength of competition, vary rating gain between 25% and 150%.
    var matchStrength = 0.0;
    for(var shooter in shooters) {
      matchStrength += _strengthForClass(shooter.classification);

      var rating = maybeKnownShooter(shooter.memberNumber);
      if(rating != null) {
        if(shooter.classification != null && shooter.classification!.index < rating.lastClassification.index) {
          rating.lastClassification = shooter.classification!;
        }

        // Update the shooter's name: the most recent one is probably the most interesting/useful
        rating.firstName = shooter.firstName;
        rating.lastName = shooter.lastName;

        // Update age categories
        rating.categories.clear();
        rating.categories.addAll(shooter.categories);

        // Update the shooter's member number: the CSV exports are more useful if it's the most
        // recent one. // TODO: this would be handy, but it changes the math somehow (not removing unseen?)
        // rating.shooter.memberNumber = shooter.memberNumber;
      }
    }
    matchStrength = matchStrength / shooters.length;
    double strengthMod =  (1.0 + max(-0.75, min(0.5, ((matchStrength) - _strengthForClass(Classification.A)) * 0.2))) * (match.level?.strengthBonus ?? 1.0);
    if(Timings.enabled) timings.matchStrengthMillis += (DateTime.now().difference(start).inMicroseconds / 1000);

    if(Timings.enabled) start = DateTime.now();
    // Based on connectedness, vary rating gain between 80% and 120%
    var totalConnectedness = 0.0;
    var totalShooters = 0.0;
    var connectednesses = <double>[];

    for(var shooter in knownShooters.values) {
      var mod = ShooterRating.baseTrendWindow / (byStage ? 1 : 1 * ShooterRating.trendStagesPerMatch);
      if (shooter.ratingEvents.length > mod) {
        totalConnectedness += shooter.connectedness;
        connectednesses.add(shooter.connectedness);
        totalShooters += 1;
      }
    }
    var globalAverageConnectedness = totalShooters < 1 ? 105.0 : totalConnectedness / totalShooters;
    var globalMedianConnectedness = totalShooters < 1 ? 105.0 : connectednesses[connectednesses.length ~/ 2];
    var connectednessDenominator = max(105.0, globalMedianConnectedness);

    totalConnectedness = 0.0;
    totalShooters = 0;
    for(var shooter in shooters) {
      var rating = maybeKnownShooter(shooter.memberNumber);

      if(rating != null) {
        totalConnectedness += rating.connectedness;
        totalShooters += 1;
      }
    }
    var localAverageConnectedness = totalConnectedness / (totalShooters > 0 ? totalShooters : 1.0);
    var connectednessMod = /*1.0;*/ 1.0 + max(-0.2, min(0.2, (((localAverageConnectedness / connectednessDenominator) - 1.0) * 2))); // * 1: how much to adjust the percentages by
    if(Timings.enabled) timings.connectednessModMillis += (DateTime.now().difference(start).inMicroseconds / 1000);

    // _log.d("Connectedness for ${match.name}: ${localAverageConnectedness.toStringAsFixed(2)}/${connectednessDenominator.toStringAsFixed(2)} => ${connectednessMod.toStringAsFixed(3)}");

    Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes = {};
    Set<ShooterRating> shootersAtMatch = Set();

    if(Timings.enabled) start = DateTime.now();
    // Process ratings for each shooter.
    if(byStage) {
      for(Stage s in match.stages) {

        var (filteredShooters, filteredScores) = _filterScores(shooters, scores, s);

        var weightMod = 1.0 + max(-0.20, min(0.10, (s.maxPoints - 120) /  400));

        Map<ShooterRating, RelativeScore> stageScoreMap = {};
        Map<ShooterRating, RelativeMatchScore> matchScoreMap = {};

        for(var score in filteredScores) {
          String num = score.shooter.memberNumber;
          var stageScore = score.stageScores[s]!;
          var rating = knownShooter(num);
          stageScoreMap[rating] = stageScore;
          matchScoreMap[rating] = score;
        }

        if(ratingSystem.mode == RatingMode.wholeEvent) {
          _processWholeEvent(
            match: match,
            stage: s,
            scores: filteredScores,
            changes: changes,
            matchStrength: strengthMod,
            connectednessMod: connectednessMod,
            weightMod: weightMod
          );
        }
        else {
          for(int i = 0; i < filteredShooters.length; i++) {
            if(ratingSystem.mode == RatingMode.roundRobin) {
              _processRoundRobin(
                match: match,
                stage: s,
                shooters: filteredShooters,
                scores: filteredScores,
                startIndex: i,
                changes: changes,
                matchStrength: strengthMod,
                connectednessMod: connectednessMod,
                weightMod: weightMod,
              );
            }
            else {
              _processOneshot(
                match: match,
                stage: s,
                shooter: filteredShooters[i],
                scores: filteredScores,
                stageScores: stageScoreMap,
                matchScores: matchScoreMap,
                changes: changes,
                matchStrength: strengthMod,
                connectednessMod: connectednessMod,
                weightMod: weightMod
              );
            }
          }
        }

        for(var r in changes.keys) {
          r.updateFromEvents(changes[r]!.values.toList());
          r.updateTrends(changes[r]!.values.toList());
          shootersAtMatch.add(r);
        }
        changeCount += changes.length;
        changes.clear();
      }
    }
    else { // by match
      var (filteredShooters, filteredScores) = _filterScores(shooters, scores, null);

      Map<ShooterRating, RelativeMatchScore> matchScoreMap = {};

      for(var score in filteredScores) {
        String num = score.shooter.memberNumber;
        matchScoreMap[knownShooter(num)] = score;
      }

      if(ratingSystem.mode == RatingMode.wholeEvent) {
        _processWholeEvent(
            match: match,
            stage: null,
            scores: filteredScores,
            changes: changes,
            matchStrength: strengthMod,
            connectednessMod: connectednessMod,
            weightMod: 1.0
        );
      }
      else {
        for(int i = 0; i < filteredShooters.length; i++) {
          if(ratingSystem.mode == RatingMode.roundRobin) {
            _processRoundRobin(
              match: match,
              stage: null,
              shooters: filteredShooters,
              scores: filteredScores,
              startIndex: i,
              changes: changes,
              matchStrength: strengthMod,
              connectednessMod: connectednessMod,
              weightMod: 1.0,
            );
          }
          else {
            _processOneshot(
                match: match,
                stage: null,
                shooter: filteredShooters[i],
                scores: filteredScores,
                stageScores: matchScoreMap.map((k, v) => MapEntry(k, v.total)),
                matchScores: matchScoreMap,
                changes: changes,
                matchStrength: strengthMod,
                connectednessMod: connectednessMod,
                weightMod: 1.0
            );
          }
        }
      }

      for(var r in changes.keys) {
        r.updateFromEvents(changes[r]!.values.toList());
        r.updateTrends(changes[r]!.values.toList());
        shootersAtMatch.add(r);
      }
      changeCount += changes.length;
      changes.clear();
    }
    if(Timings.enabled) timings.rateShootersMillis += (DateTime.now().difference(start).inMicroseconds / 1000);

    if(Timings.enabled) start = DateTime.now();
    if(match.date != null && shooters.length > 1) {
      var averageBefore = 0.0;
      var averageAfter = 0.0;

      // We need only consider at most the best [ShooterRating.maxConnections] connections. If a shooter's list is
      // empty, we'll fill their list with these shooters. If a shooter's list is not empty, we can end up with at
      // most maxConnections new entries in the list, by definition.
      var encounteredList = shootersAtMatch
          .sorted((a, b) => b.connectedness.compareTo(a.connectedness))
          .sublist(0, min(ShooterRating.maxConnections, shootersAtMatch.length));

      // _log.d("Updating connectedness at ${match.name} for ${shootersAtMatch.length} of ${knownShooters.length} shooters");
      for (var rating in shootersAtMatch) {
        averageBefore += rating.connectedness;
        rating.updateConnections(match.date!, encounteredList);
        rating.lastSeen = match.date!;
      }

      for (var rating in shootersAtMatch) {
        rating.updateConnectedness();
        averageAfter += rating.connectedness;
      }

      averageBefore /= encounteredList.length;
      averageAfter /= encounteredList.length;
      // _log.d("Averages: ${averageBefore.toStringAsFixed(1)} -> ${averageAfter.toStringAsFixed(1)} vs. ${expectedConnectedness.toStringAsFixed(1)}");
    }
    timings.ratingEventCount += changeCount;
    if(Timings.enabled) timings.updateConnectednessMillis += (DateTime.now().difference(start).inMicroseconds / 1000);
  }

  Map<Shooter, bool> _verifyCache = {};
  bool _verifyShooter(Shooter s) {
    if(_verifyCache.containsKey(s)) return _verifyCache[s]!;

    var finalMemberNumber = s.memberNumber;
    if(!byStage && s.dq) {
      _verifyCache[s] = false;
      return false;
    }
    if(s.reentry) {
      _verifyCache[s] = false;
      return false;
    }
    if(s.memberNumber.isEmpty) {
      var processedName = _processName(s);
      var emptyCorrection = _dataCorrections.getEmptyCorrectionByName(processedName);
      if(emptyCorrection != null) {
        finalMemberNumber = processMemberNumber(emptyCorrection.correctedNumber);
      }

      _verifyCache[s] = false;
      return false;
    }

    // This is already processed, because _verifyShooter is only called from _getShooters
    // after member numbers have been processed.
    String memNum = finalMemberNumber;

    if(maybeKnownShooter(memNum) == null) {
      _verifyCache[s] = false;
      return false;
    }
    if(memberNumberWhitelist.contains(memNum)) {
      _verifyCache[s] = true;
      return true;
    }

    // if(s.memberNumber.length <= 3) {
    //   _verifyCache[s] = false;
    //   return false;
    // }

    if(s.firstName.endsWith("2") || s.lastName.endsWith("2") || s.firstName.endsWith("3") || s.firstName.endsWith("3")) {
      _verifyCache[s] = false;
      return false;
    }

    _verifyCache[s] = true;
    return true;
  }

  (List<Shooter>, List<RelativeMatchScore>) _filterScores(List<Shooter> shooters, List<RelativeMatchScore> scores, Stage? stage) {
    List<Shooter> filteredShooters = []..addAll(shooters);
    List<RelativeMatchScore> filteredScores = []..addAll(scores);
    for(var s in scores) {
      if(stage != null) {
        var stageScore = s.stageScores[stage];

        if(stageScore == null) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
          _log.w("null stage score for ${s.shooter}");
          continue;
        }

        if(!_isValid(stageScore)) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
        }
      }
      else {
        if(_dnf(s)) {
          filteredScores.remove(s);
          filteredShooters.remove(s.shooter);
        }
      }
    }

    return (filteredShooters, filteredScores);
  }

  void _processRoundRobin({
    required PracticalMatch match,
    Stage? stage,
    required List<Shooter> shooters,
    required List<RelativeMatchScore> scores,
    required int startIndex,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod,
  }) {
    Shooter a = shooters[startIndex];
    var score = scores.firstWhere((element) => element.shooter == a);

    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.total.percent >= 1.0) {
      if(_pubstomp(scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;

    for(int j = startIndex + 1; j < shooters.length; j++) {
      Shooter b = shooters[j];

      String memNumA = a.memberNumber;
      String memNumB = b.memberNumber;

      // unmarked reentries
      if(memNumA == memNumB) continue;

      ShooterRating aRating = knownShooter(memNumA);
      ShooterRating bRating = knownShooter(memNumB);

      changes[aRating] ??= {};
      changes[bRating] ??= {};

      RelativeMatchScore aScore = scores.firstWhere((score) => score.shooter == a);
      RelativeMatchScore bScore = scores.firstWhere((score) => score.shooter == b);

      if(stage != null) {
        RelativeScore aStageScore = aScore.stageScores[stage]!;
        RelativeScore bStageScore = bScore.stageScores[stage]!;

        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          match: match,
          isMatchOngoing: _ongoingMatches.contains(match),
          shooters: [aRating, bRating],
          scores: {
            aRating: aStageScore,
            bRating: bStageScore,
          },
          matchScores: {
            aRating: aScore,
            bRating: bScore,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
          eventWeightMultiplier: weightMod,
        );

        changes[aRating]![aStageScore] ??= ratingSystem.newEvent(rating: aRating, match: match, stage: stage, score: aStageScore);
        changes[bRating]![bStageScore] ??= ratingSystem.newEvent(rating: bRating, match: match, stage: stage, score: bStageScore);

        changes[aRating]![aStageScore]!.apply(update[aRating]!);
        changes[bRating]![bStageScore]!.apply(update[bRating]!);
      }
      else {
        _encounteredMemberNumber(memNumA);
        _encounteredMemberNumber(memNumB);

        var update = ratingSystem.updateShooterRatings(
          match: match,
          shooters: [aRating, bRating],
          scores: {
            aRating: aScore.total,
            bRating: bScore.total,
          },
          matchScores: {
            aRating: aScore,
            bRating: bScore,
          },
          matchStrengthMultiplier: matchStrength,
          connectednessMultiplier: connectednessMod,
        );

        changes[aRating]![aScore.total] ??= ratingSystem.newEvent(rating: aRating, match: match, score: aScore.total);
        changes[bRating]![bScore.total] ??= ratingSystem.newEvent(rating: bRating, match: match, score: bScore.total);

        changes[aRating]![aScore.total]!.apply(update[aRating]!);
        changes[bRating]![bScore.total]!.apply(update[bRating]!);
      }
    }
  }

  void _processOneshot({
    required PracticalMatch match,
    Stage? stage,
    required Shooter shooter,
    required List<RelativeMatchScore> scores,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required Map<ShooterRating, RelativeScore> stageScores,
    required Map<ShooterRating, RelativeMatchScore> matchScores,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) {
    String memNum = shooter.memberNumber;

    ShooterRating rating = knownShooter(memNum);

    changes[rating] ??= {};
    RelativeMatchScore score = scores.firstWhere((score) => score.shooter == shooter);

    late DateTime start;
    if(Timings.enabled) start = DateTime.now();
    // Check for pubstomp
    var pubstompMod = 1.0;
    if(score.total.percent >= 1.0) {
      if(_pubstomp(scores)) {
        pubstompMod = 0.33;
      }
    }
    matchStrength *= pubstompMod;
    if(Timings.enabled) timings.pubstompMillis += (DateTime.now().difference(start).inMicroseconds / 1000);

    if(stage != null) {
      RelativeScore stageScore = score.stageScores[stage]!;

      // If the shooter has already had a rating change for this stage, don't recalc.
      for(var existingScore in changes[rating]!.keys) {
        if(existingScore.stage == stage) return;
      }

      _encounteredMemberNumber(memNum);

      if(Timings.enabled) start = DateTime.now();
      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: [rating],
        scores: stageScores,
        matchScores: matchScores,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );
      if(Timings.enabled) timings.updateMillis += (DateTime.now().difference(start).inMicroseconds / 1000);

      if(!changes[rating]!.containsKey(stageScore)) {
        changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore);
        changes[rating]![stageScore]!.apply(update[rating]!);
        changes[rating]![stageScore]!.info = update[rating]!.info;
      }
    }
    else {
      _encounteredMemberNumber(memNum);

      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: [rating],
        scores: matchScores.map((k, v) => MapEntry(k, v.total)),
        matchScores: matchScores,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
      );

      // You only get one rating change per match.
      if(changes[rating]!.isEmpty) {
        changes[rating]![score.total] = ratingSystem.newEvent(
          rating: rating,
          match: match,
          score: score.total,
          info: update[rating]!.info,
        );

        changes[rating]![score.total]!.apply(update[rating]!);
      }
    }
  }

  void _processWholeEvent({
    required PracticalMatch match,
    Stage? stage,
    required List<RelativeMatchScore> scores,
    required Map<ShooterRating, Map<RelativeScore, RatingEvent>> changes,
    required double matchStrength,
    required double connectednessMod,
    required double weightMod
  }) {
    // Check for pubstomp
    var pubstompMod = 1.0;
    if(_pubstomp(scores)) {
      pubstompMod = 0.33;
    }
    matchStrength *= pubstompMod;

    if(stage != null) {
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeMatchScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        var otherScore = s.stageScores[stage]!;
        _encounteredMemberNumber(num);
        scoreMap[knownShooter(num)] = otherScore;
        matchScoreMap[knownShooter(num)] = s;
        changes[knownShooter(num)] ??= {};
      }

      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: scoreMap.keys.toList(),
        scores: scoreMap,
        matchScores: matchScoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
        eventWeightMultiplier: weightMod,
      );

      for(var rating in scoreMap.keys) {
        var stageScore = scoreMap[rating];

        if(stageScore == null) {
          _log.w("Null stage score for $rating on ${stage.name}");
          continue;
        }

        if (!changes[rating]!.containsKey(stageScore)) {
          changes[rating]![stageScore] = ratingSystem.newEvent(rating: rating, match: match, stage: stage, score: stageScore);
          changes[rating]![stageScore]!.apply(update[rating]!);
          changes[rating]![stageScore]!.info = update[rating]!.info;
        }
      }
    }
    else {
      var scoreMap = <ShooterRating, RelativeScore>{};
      var matchScoreMap = <ShooterRating, RelativeMatchScore>{};
      for(var s in scores) {
        String num = s.shooter.memberNumber;

        scoreMap[knownShooter(num)] ??= s.total;
        matchScoreMap[knownShooter(num)] ??= s;
        changes[knownShooter(num)] ??= {};
        _encounteredMemberNumber(num);
      }

      var update = ratingSystem.updateShooterRatings(
        match: match,
        shooters: scoreMap.keys.toList(),
        scores: scoreMap,
        matchScores: matchScoreMap,
        matchStrengthMultiplier: matchStrength,
        connectednessMultiplier: connectednessMod,
      );

      for(var rating in scoreMap.keys) {
        var score = scoreMap[rating]!;
        // You only get one rating change per match.
        if (changes[rating]!.isEmpty) {
          changes[rating]![score] ??= ratingSystem.newEvent(
            rating: rating,
            match: match,
            score: score,
            info: update[rating]!.info,
          );

          changes[rating]![score]!.apply(update[rating]!);
        }
      }
    }
  }

  bool _isValid(RelativeScore score) {
    // Filter out badly marked classifier reshoots
    if(score.score.hits == 0 && score.score.time <= 0.1) return false;

    // The George Williams Rule
    if(score.stage != null && score.stage!.type != Scoring.fixedTime && score.score.getHitFactor() > 30) return false;

    // Filter out extremely short times that are probably DNFs or partial scores entered for DQs
    if(score.stage!.type != Scoring.fixedTime && score.score.time <= 0.5) return false;

    // The Jalise Williams rule: filter out subminor/unknown PFs
    if(score.score.shooter.powerFactor!.index > PowerFactor.minor.index) return false;

    return true;
  }

  bool _pubstomp(List<RelativeMatchScore> scores) {
    if(scores.length < 2) return false;

    var sorted = scores.sorted((a, b) => b.total.percent.compareTo(a.total.percent));

    var first = sorted[0];
    var second = sorted[1];

    var firstScore = first.total;
    var secondScore = second.total;

    var firstClass = first.shooter.classification ?? Classification.U;
    var secondClass = second.shooter.classification ?? Classification.U;

    var firstRating = maybeKnownShooter(first.shooter.memberNumber);
    var secondRating = maybeKnownShooter(second.shooter.memberNumber);

    // People entered with empty or invalid member numbers
    if(firstRating == null || secondRating == null) {
      // _log.d("Unexpected null in pubstomp detection");
      return false;
    }

    // if(processMemberNumber(first.shooter.memberNumber) == "68934" || processMemberNumber(first.shooter.memberNumber) == "5172") {
    //   _log.d("${firstScore.percent.toStringAsFixed(2)} ${(firstScore.relativePoints/secondScore.relativePoints).toStringAsFixed(3)}");
    //   _log.d("${firstRating.rating.round()} > ${secondRating.rating.round()}");
    // }

    // It's only a pubstomp if:
    // 1. The winner wins by more than 25%.
    // 2. The winner is M shooting against no better than B or GM shooting against no better than A.
    // 3. The winner's rating is at least 200 higher than the next shooter's.
    if(firstScore.percent >= 1.0
        && (firstScore.relativePoints / secondScore.relativePoints > 1.20)
        && firstClass.index <= Classification.M.index
        && secondClass.index - firstClass.index >= 2
        && firstRating.rating - secondRating.rating > 200) {
      // _log.d("Pubstomp multiplier for $firstRating over $secondRating");
      return true;

    }
    return false;
  }

  bool _dnf(RelativeMatchScore score) {
    if(score.shooter.powerFactor == PowerFactor.subminor || score.shooter.powerFactor == PowerFactor.unknown) {
      return true;
    }

    for(var stageScore in score.stageScores.values) {
      if(stageScore.stage!.type != Scoring.chrono && stageScore.score.time <= 0.01 && stageScore.score.hits == 0) {
        return true;
      }
    }

    return false;
  }

  String toCSV({List<ShooterRating>? ratings}) {
    var sortedShooters = ratings ?? uniqueShooters.sorted((a, b) => b.rating.compareTo(a.rating));
    return ratingSystem.ratingsToCsv(sortedShooters);
  }

  void _encounteredMemberNumber(String num) {
    _memberNumbersEncountered.add(num);
    var mappedNum = _memberNumberMappings[num];
    if(mappedNum != null && mappedNum != num) {
      _memberNumbersEncountered.add(num);
    }
  }

  double _strengthForClass(Classification? c) {
    switch(c) {
      case Classification.GM:
        return 10;
      case Classification.M:
        return 6;
      case Classification.A:
        return 4;
      case Classification.B:
        return 3;
      case Classification.C:
        return 2;
      case Classification.D:
        return 1;
      case Classification.U:
        return _strengthForClass(Classification.A);
      default:
        return 2.5;
    }
  }

  RaterStatistics? _cachedStats;
  RaterStatistics getStatistics({List<ShooterRating>? ratings}) {
    if(ratings != null) return _calculateStats(ratings);

    if(true || _cachedStats == null) {
      _cachedStats = _calculateStats(null);
    }

    return _cachedStats!;
  }

  RaterStatistics _calculateStats(List<ShooterRating>? ratings) {
    if(ratings == null) {
      ratings = knownShooters.values.toList();
    }

    var bucketSize = ratingSystem.histogramBucketSize(ratings.length, _matches.length);

    var count = ratings.length;
    var allRatings = ratings.map((r) => r.rating).toList()..sort();
    var allHistoryLengths = ratings.map((r) => r.ratingEvents.length).toList()..sort(
      (a, b) => a.compareTo(b)
    );

    var histogram = <int, int>{};
    var yearOfEntryHistogram = <int, int>{};

    for(var rating in ratings) {
      // Buckets 100 wide
      var bucket = (0 + (rating.rating / bucketSize).floor());

      var value = histogram.increment(bucket);

      var events = <RatingEvent>[];
      if(rating.emptyRatingEvents.isNotEmpty) events.add(rating.emptyRatingEvents.first);
      if(rating.ratingEvents.isNotEmpty) events.add(rating.ratingEvents.first);

      if(events.isEmpty) continue;

      var firstEvent = events.sorted((a, b) => a.match.date!.compareTo(b.match.date!)).first;
      yearOfEntryHistogram.increment(firstEvent.match.date!.year);
    }

    var averagesByClass = <Classification, double>{};
    var minsByClass = <Classification, double>{};
    var maxesByClass = <Classification, double>{};
    var countsByClass = <Classification, int>{};
    Map<Classification, Map<int, int>> histogramsByClass = {};
    Map<Classification, List<double>> ratingsByClass = {};

    for(var classification in Classification.values) {
      if(classification == Classification.unknown) continue;

      var shootersInClass = ratings.where((r) => r.lastClassification == classification);
      var ratingsInClass = shootersInClass.map((r) => r.rating);

      ratingsByClass[classification] = ratingsInClass.sorted((a, b) => a.compareTo(b));
      averagesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.average : 0;
      minsByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.min : 0;
      maxesByClass[classification] = ratingsInClass.length > 0 ? ratingsInClass.max : 0;
      countsByClass[classification] = ratingsInClass.length;

      histogramsByClass[classification] = {};
      for(var rating in ratingsInClass) {
        // Buckets 100 wide
        var bucket = (0 + (rating / bucketSize).floor());

        histogramsByClass[classification]!.increment(bucket);
      }
    }

    return RaterStatistics(
      shooters: count,
      averageRating: allRatings.average,
      medianRating: allRatings.median,
      minRating: allRatings.min,
      maxRating: allRatings.max,
      averageHistory: allHistoryLengths.average,
      medianHistory: allHistoryLengths.median,
      histogram: histogram,
      countByClass: countsByClass,
      averageByClass: averagesByClass,
      minByClass: minsByClass,
      maxByClass: maxesByClass,
      histogramsByClass: histogramsByClass,
      histogramBucketSize: bucketSize,
      ratingsByClass: ratingsByClass,
      yearOfEntryHistogram: yearOfEntryHistogram,
    );
  }

  @override
  String toString() {
    return "Rater for ${_matches.last.name} with ${filters.divisions}";
  }

  static Map<String, String> _processMemNumCache = {};
  static String processMemberNumber(String no) {
    if(_processMemNumCache.containsKey(no)) return _processMemNumCache[no]!;
    var no2 = no.toUpperCase().replaceAll(RegExp(r"[^FYTABLRD0-9]"), "").replaceAll(RegExp(r"[ATYF]{1,2}"), "");

    // If a member number contains no numbers, ignore it.
    if(!no2.contains(RegExp(r"[0-9]+"))) return "";

    // If a member number is all zeroes, ignore it.
    if(no2.contains(RegExp(r"^0+$"))) return "";

    _processMemNumCache[no] = no2;
    return no2;
  }
}

extension _StrengthBonus on MatchLevel {
  double get strengthBonus {
    switch(this) {
      case MatchLevel.I:
        return 1.0;
      case MatchLevel.II:
        return 1.15;
      case MatchLevel.III:
        return 1.3;
      case MatchLevel.IV:
        return 1.45;
    }
  }
}

class RaterStatistics {
  int shooters;
  double averageRating;
  double medianRating;
  double minRating;
  double maxRating;
  double averageHistory;
  int medianHistory;

  int histogramBucketSize;
  Map<int, int> histogram;

  Map<Classification, int> countByClass;
  Map<Classification, double> averageByClass;
  Map<Classification, double> minByClass;
  Map<Classification, double> maxByClass;

  Map<Classification, Map<int, int>> histogramsByClass;
  Map<Classification, List<double>> ratingsByClass;

  Map<int, int> yearOfEntryHistogram;

  RaterStatistics({
    required this.shooters,
    required this.averageRating,
    required this.medianRating,
    required this.minRating,
    required this.maxRating,
    required this.averageHistory,
    required this.medianHistory,
    required this.countByClass,
    required this.averageByClass,
    required this.minByClass,
    required this.maxByClass,
    required this.histogramBucketSize,
    required this.histogram,
    required this.histogramsByClass,
    required this.ratingsByClass,
    required this.yearOfEntryHistogram,
  });
}

enum _MemNumType {
  associate,
  lifetime,
  benefactor,
  regionDirector;

  bool betterThan(_MemNumType other) {
    return other.index > this.index;
  }

  static _MemNumType classify(String number) {
    if(number.startsWith("RD")) return _MemNumType.regionDirector;
    if(number.startsWith("B")) return _MemNumType.benefactor;
    if(number.startsWith("L")) return _MemNumType.lifetime;

    return _MemNumType.associate;
  }

  static List<String> targetNumber(Map<_MemNumType, List<String>> numbers) {
    for(var type in _MemNumType.values.reversed) {
      var v = numbers[type];
      if(v != null && v.isNotEmpty) return v;
    }

    throw ArgumentError("Empty map provided");
  }
}