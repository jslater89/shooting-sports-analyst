/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

const _keepHistoryKey = "keepHistory";
const _whitelistKey = "memNumWhitelist";
const _aliasesKey = "aliases";
const _memberNumberMappingsKey = "numMappings";
const _memberNumberMappingBlacklistKey = "numMapBlacklist";
const _hiddenShootersKey = "hiddenShooters";
const _memberNumberCorrectionsKey = "memNumCorrections";
const _recognizedDivisionsKey = "recDivs";
const _checkDataEntryKey = "checkDataEntry";

class RatingProjectSettings {
  // All of the below are serialized
  bool get byStage => algorithm.byStage;
  bool preserveHistory;

  /// If true, ignore data entry errors for this run only.
  bool transientDataEntryErrorSkip;

  bool checkDataEntryErrors;
  List<String> memberNumberWhitelist;
  late MemberNumberCorrectionContainer memberNumberCorrections;

  RatingSystem algorithm;
  /// A map of shooter name changes, used to backstop automatic shooter number change detection.
  ///
  /// Number change detection looks through a map of shooters-to-member-numbers after adding
  /// shooters, and tries to determine if any name maps to more than one member number. If it
  /// does, the rater combines the two ratings.
  Map<String, String> shooterAliases;

  /// A map of user-specified member number mappings. Should be in [Rater.processMemberNumber] format.
  ///
  /// Mappings may be made in either direction, but will preferentially be made from key to value:
  /// map[A1234] = L123 will try to map A1234 to L123 first. If L123 has rating events but A1234 doesn't,
  /// when both numbers are encountered for the first time, it will make the mapping in the other direction.
  Map<String, String> userMemberNumberMappings;

  /// A map of member number mappings that should _not_ be made automatically.
  ///
  /// If a candidate member number change appears in this map, in either direction
  // ignore: deprecated_new_in_comment_reference
  /// (i.e., map[old] = new or map[new] = old), the shooter ratings corresponding
  /// to those numbers will not be merged.
  ///
  /// Should be in [Rater.processMemberNumber] format.
  Map<String, List<String>> memberNumberMappingBlacklist;

  /// A list of shooters to hide from the rating display, based on member number.
  ///
  /// They are still used to calculate ratings, but not shown in the UI or exported
  /// to CSV, so that users can generate e.g. a club or section leaderboard, without
  /// having a bunch of traveling L2 shooters in the mix.
  ///
  /// Should be in [Rater.processMemberNumber] format.
  List<String> hiddenShooters;

  /// A list of match IDs that only recognize certain divisions, mapped to the divisions
  /// they recognize.
  ///
  /// If a match ID occurs in the keys of this map, then only the divisions in the associated
  /// entry will be used for rating updates. Use it so JJ doesn't get a huge Open boost from
  /// winning Open at Prod/PCC Nationals, or other similar cases.
  ///
  /// Match IDs should be PracticalMatch.practiscoreId.
  Map<String, List<Division>> recognizedDivisions;

  RatingProjectSettings({
    this.preserveHistory = false,
    this.checkDataEntryErrors = true,
    this.transientDataEntryErrorSkip = false,
    required this.algorithm,
    this.memberNumberWhitelist = const [],
    this.shooterAliases = defaultShooterAliases,
    this.userMemberNumberMappings = const {},
    this.memberNumberMappingBlacklist = const {},
    this.hiddenShooters = const [],
    this.recognizedDivisions = const {
      "433b1840-0e57-4397-8dae-1107bfe468a7": [uspsaProduction, uspsaPcc],
    },
    MemberNumberCorrectionContainer? memberNumberCorrections
  }) {
    if(memberNumberCorrections != null) this.memberNumberCorrections = memberNumberCorrections;
    else this.memberNumberCorrections = MemberNumberCorrectionContainer();
  }

  void encodeToJson(Map<String, dynamic> map) {
    map[_checkDataEntryKey] = checkDataEntryErrors;
    map[_keepHistoryKey] = preserveHistory;
    map[_whitelistKey] = memberNumberWhitelist;
    map[_aliasesKey] = shooterAliases;
    map[_memberNumberMappingsKey] = userMemberNumberMappings;
    map[_memberNumberMappingBlacklistKey] = memberNumberMappingBlacklist;
    map[_hiddenShootersKey] = hiddenShooters;
    map[_memberNumberCorrectionsKey] = memberNumberCorrections.toJson();
    map[_recognizedDivisionsKey] = <String, dynamic>{}..addEntries(recognizedDivisions.entries.map((e) =>
        MapEntry(e.key, e.value.map((e) => e.name).toList())
    ));

    /// Alg-specific settings
    algorithm.encodeToJson(map);
  }

  factory RatingProjectSettings.decodeFromJson(Sport sport, RatingSystem algorithm, Map<String, dynamic> encodedProject) {
    Map<String, List<Division>> recognizedDivisions = {};
    var recDivJson = (encodedProject[_recognizedDivisionsKey] ?? <String, dynamic>{}) as Map<String, dynamic>;
    for(var key in recDivJson.keys) {
      var divisions = ((recDivJson[key] ?? []) as List<dynamic>).map((s) => sport.divisions.lookupByName(s as String)).whereNotNull();
      recognizedDivisions[key] = []..addAll(divisions);
    }

    return RatingProjectSettings(
      algorithm: algorithm,
      checkDataEntryErrors: (encodedProject[_checkDataEntryKey] ?? true) as bool,
      preserveHistory: encodedProject[_keepHistoryKey] as bool,
      memberNumberWhitelist: ((encodedProject[_whitelistKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      shooterAliases: ((encodedProject[_aliasesKey] ?? defaultShooterAliases) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      userMemberNumberMappings: ((encodedProject[_memberNumberMappingsKey] ?? <String, dynamic>{}) as Map<String, dynamic>).map<String, String>((k, v) =>
        MapEntry(k, v as String)
      ),
      memberNumberMappingBlacklist: _decodeMemberNumberMappingBlacklist(encodedProject),
      hiddenShooters: ((encodedProject[_hiddenShootersKey] ?? []) as List<dynamic>).map((item) => item as String).toList(),
      memberNumberCorrections: MemberNumberCorrectionContainer.fromJson((encodedProject[_memberNumberCorrectionsKey] ?? []) as List<dynamic>),
      recognizedDivisions: recognizedDivisions,
    );
  }

  factory RatingProjectSettings.fromOld(OldRatingProject project) {
    var sport = uspsaSport;
    var oldMap = jsonDecode(project.toJson());
    var algorithmName = oldMap[DbRatingProject.algorithmKey];
    var algorithm = RatingSystem.algorithmForName(algorithmName, oldMap);
    var recognizedDivisions = Map.fromEntries(project.settings.recognizedDivisions.entries.map((e) =>
      MapEntry(e.key, e.value.map((d) => sport.divisions.lookupByName(d.name)!).toList())
    ));
    return RatingProjectSettings(
      algorithm: algorithm,
      checkDataEntryErrors: project.settings.checkDataEntryErrors,
      preserveHistory: project.settings.preserveHistory,
      memberNumberWhitelist: project.settings.memberNumberWhitelist,
      shooterAliases: project.settings.shooterAliases,
      userMemberNumberMappings: project.settings.userMemberNumberMappings,
      memberNumberMappingBlacklist: Map.fromEntries(project.settings.memberNumberMappingBlacklist.entries.map((e) =>
        MapEntry(e.key, [e.value])
      )),
      hiddenShooters: project.settings.hiddenShooters,
      memberNumberCorrections: project.settings.memberNumberCorrections,
      recognizedDivisions: recognizedDivisions,
    );
  }

  /// Add a user-specified member number mapping, or update an existing mapping.
  ///
  /// If the source number already has a mapping, it, as well as its preexisting
  /// target number, will be updated to point to the new target number.
  ///
  /// Returns true if the mapping was added or updated, or false if the requested
  /// mapping already exists.
  bool addUserMapping(String sourceNumber, String targetNumber) {
    var existingTarget = userMemberNumberMappings[sourceNumber];
    if(existingTarget == targetNumber) {
      return false;
    }
    userMemberNumberMappings[sourceNumber] = targetNumber;
    if(existingTarget != null) {
      userMemberNumberMappings[existingTarget] = targetNumber;
    }
    return true;
  }

  /// Add a member number mapping blacklist entry from source to target.
  ///
  /// Returns true if the entry was added, or false the blacklist already
  /// contains an entry from source to target.
  bool addBlacklistEntry(String sourceNumber, String targetNumber) {
    return memberNumberMappingBlacklist.addToListIfMissing(sourceNumber, targetNumber);
  }
}

Map<String, List<String>> _decodeMemberNumberMappingBlacklist(Map<String, dynamic> encodedProject) {
  var memberNumberMappingBlacklist = <String, List<String>>{};
  var blacklistJson = (encodedProject[_memberNumberMappingBlacklistKey] ?? <String, dynamic>{}) as Map<String, dynamic>;
  for(var key in blacklistJson.keys) {
    var value = blacklistJson[key];
    if(value is String) {
      memberNumberMappingBlacklist[key] = [value];
    }
    else {
      memberNumberMappingBlacklist[key] = (value as List<dynamic>).map((item) => item as String).toList();
    }
  }
  return memberNumberMappingBlacklist;
}
