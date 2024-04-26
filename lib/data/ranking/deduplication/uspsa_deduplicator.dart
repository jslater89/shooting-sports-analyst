import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as strdiff;
import 'package:shooting_sports_analyst/logger.dart';

var _log = SSALogger("USPSADeduplicator");

class USPSADeduplicator extends ShooterDeduplicator {
  const USPSADeduplicator();

  @override
  RatingResult deduplicateShooters({
    required Map<String, DbShooterRating> knownShooters,
    required Map<String, String> shooterAliases,
    required Map<String, String> mappingBlacklist,
    required Map<String, String> userMappings,
    required Map<String, String> currentMappings,
    bool checkDataEntryErrors = true,
    bool verbose = false
  }) {
    Map<String, List<String>> namesToNumbers = {};
    Map<String, String> detectedUserMappings = {};
    Map<String, List<DbShooterRating>> ratingsByName = {};

    for(var num in knownShooters.keys) {
      var userMapping = userMappings[num];
      if(userMapping != null) {
        detectedUserMappings[num] = userMapping;
      }

      var shooter = knownShooters[num]!;
      var name = ShooterDeduplicator.processName(shooter);

      var finalName = shooterAliases[name] ?? name;

      namesToNumbers[finalName] ??= [];
      namesToNumbers[finalName]!.add(num);
      if(userMapping != null) namesToNumbers[finalName]!.add(userMapping);

      ratingsByName[finalName] ??= [];
      ratingsByName[finalName]!.add(shooter);

      currentMappings[num] ??= num;
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
            if(bestCandidate != null && mappingBlacklist[n] == bestCandidate) {
              numbers[_MemNumType.classify(bestCandidate)]!.remove(bestCandidate);
            }
          }

          nList = []..addAll(numbers[type]!);
          if(nList.length <= 1) continue;

          // To have >1 number in the same type and still be able to map
          // automatically, it must be part of a valid user mapping.
          Set<String> legalValues = {};
          for(var n in nList) {
            var userMapping = userMappings[n];
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
            if(mappingBlacklist[n1] == n2 || mappingBlacklist[n2] == n1) {
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
            var m = userMappings[n];
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
            if (currentMappings[n] == bestNumber) {
              unmapped = true;
            }
            else {
              var target = currentMappings[n];
              if (!numbers.values.flattened.contains(target)) crossMapped = true;
              if (mappingBlacklist[n] == target) {
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
        List<DbShooterRating> withHistory = [];
        for(var n in numbers.values) {
          var rating = knownShooters[n];
          if(rating != null && rating.length > 0) withHistory.add(rating);
        }

        if(withHistory.length > 1) {
          if(verbose) _log.w("Ignoring $name with numbers $list: ${withHistory.length} ratings have history: $withHistory");
          Map<DbShooterRating, List<DbShooterRating>> accomplices = {};

          for(var culprit in withHistory) {
            accomplices[culprit] = []..addAll(ratingsByName[ShooterDeduplicator.processName(culprit)]!);
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
            _mapRatings(
              knownShooters: knownShooters,
              currentMappings: currentMappings,
              target: target,
              source: source,
            );
          }
          else {
            // Otherwise, source was previously mapped, so just update the source->target
            // entry in the map to point to the new true rating.
            currentMappings[n] = bestNumber;
          }
        }
      }
    }

    return RatingResult.ok();
  }

  /// Map ratings from one shooter to another. [source]'s history will
  /// be added to [target].
  void _mapRatings({
    required Map<String, ShooterRating> knownShooters,
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