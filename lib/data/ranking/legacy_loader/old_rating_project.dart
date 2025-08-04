/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';

class OldRatingProjectSettings {
  // All of the below are serialized
  bool get byStage => algorithm.byStage;
  bool preserveHistory;

  /// If true, ignore data entry errors for this run only.
  bool transientDataEntryErrorSkip;

  bool checkDataEntryErrors;
  List<OldRaterGroup> groups;
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
  Map<String, String> memberNumberMappingBlacklist;

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

  OldRatingProjectSettings({
    this.preserveHistory = false,
    this.checkDataEntryErrors = true,
    this.transientDataEntryErrorSkip = false,
    this.groups = const [OldRaterGroup.open, OldRaterGroup.limited, OldRaterGroup.pcc, OldRaterGroup.carryOptics, OldRaterGroup.locap],
    required this.algorithm,
    this.memberNumberWhitelist = const [],
    this.shooterAliases = defaultShooterAliases,
    this.userMemberNumberMappings = const {},
    this.memberNumberMappingBlacklist = const {},
    this.hiddenShooters = const [],
    this.recognizedDivisions = const {
      "433b1840-0e57-4397-8dae-1107bfe468a7": [Division.production, Division.pcc],
    },
    MemberNumberCorrectionContainer? memberNumberCorrections
  }) {
    if(memberNumberCorrections != null) this.memberNumberCorrections = memberNumberCorrections;
    else this.memberNumberCorrections = MemberNumberCorrectionContainer();
  }

  static List<OldRaterGroup> groupsForSettings({bool combineOpenPCC = false, LimLoCoCombination limLoCo = LimLoCoCombination.none, bool combineLocap = true}) {
    var groups = <OldRaterGroup>[];

    if(combineOpenPCC) groups.add(OldRaterGroup.openPcc);
    else groups.addAll([OldRaterGroup.open, OldRaterGroup.pcc]);

    groups.addAll(limLoCo.groups());

    if(combineLocap) groups.add(OldRaterGroup.locap);
    else groups.addAll([OldRaterGroup.production, OldRaterGroup.singleStack, OldRaterGroup.revolver, OldRaterGroup.limited10]);

    return groups;
  }
}

enum LimLoCoCombination {
  none,
  limCo,
  limLo,
  loCo,
  all;

  List<OldRaterGroup> groups() {
    switch(this) {
      case LimLoCoCombination.none:
        return [
          OldRaterGroup.limited,
          OldRaterGroup.carryOptics,
          OldRaterGroup.limitedOptics,
        ];
      case LimLoCoCombination.limCo:
        return [
          OldRaterGroup.limitedCO,
          OldRaterGroup.limitedOptics,
        ];
      case LimLoCoCombination.limLo:
        return [
          OldRaterGroup.limitedLO,
          OldRaterGroup.carryOptics,
        ];
      case LimLoCoCombination.loCo:
        return [
          OldRaterGroup.limOpsCO,
          OldRaterGroup.limited,
        ];
      case LimLoCoCombination.all:
        return [
          OldRaterGroup.limLoCo,
        ];
    }
  }

  static LimLoCoCombination fromGroups(List<OldRaterGroup> groups) {
    if(groups.contains(OldRaterGroup.limLoCo)) {
      return LimLoCoCombination.all;
    }
    else if(groups.contains(OldRaterGroup.limOpsCO)) {
      return LimLoCoCombination.loCo;
    }
    else if(groups.contains(OldRaterGroup.limitedLO)) {
      return LimLoCoCombination.limLo;
    }
    else if(groups.contains(OldRaterGroup.limitedCO)) {
      return LimLoCoCombination.limCo;
    }
    else {
      return none;
    }
  }

  String get uiLabel {
    switch(this) {

      case LimLoCoCombination.none:
        return "All separate";
      case LimLoCoCombination.limCo:
        return "Combine LIM/CO";
      case LimLoCoCombination.limLo:
        return "Combine LIM/LO";
      case LimLoCoCombination.loCo:
        return "Combine LO/CO";
      case LimLoCoCombination.all:
        return "Combine all";
    }
  }
}
