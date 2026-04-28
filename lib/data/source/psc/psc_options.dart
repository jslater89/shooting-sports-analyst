/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

enum PscMatchType implements InternalMatchType {
  /// USPSA, IPSC, or PCSL matches
  hitFactor,
  /// IDPA-like matches, including 'outlaw IDPA' that use the
  /// PractiScore IDPA template
  idpaLike,
  /// ICORE-like matches, with A/B/C/M/NS hits and time+points down
  /// scoring
  icoreLike,
  /// Generic time plus matches, with a time field, a 'bons' list, and
  /// a 'pens' list.
  genericTimePlus,
  /// Untimed points matches.
  points;
  // TODO: steel challenge

  static PscMatchType? fromString(String value) {
    return switch(value) {
      "uspsa_p" => PscMatchType.hitFactor,
      "idpa" => PscMatchType.idpaLike,
      "icore" => PscMatchType.icoreLike,
      "timeplus" => PscMatchType.genericTimePlus,
      "timeplus_p" => PscMatchType.genericTimePlus,
      "precisionrifle" => PscMatchType.points,
      String() => null,
    };
  }
}

class PscMatchFetchOptions implements InternalMatchFetchOptions {
  final bool downloadScoreLogs;
  final Sport? parseAsSport;
  final bool ignoreUnknownDivisions;
  final bool fuzzyHitFactorDivisionMatching;

  const PscMatchFetchOptions({
    this.downloadScoreLogs = false,
    this.parseAsSport,
    this.ignoreUnknownDivisions = false,
    this.fuzzyHitFactorDivisionMatching = false,
  });

  PscMatchFetchOptions copyWith({
    bool? downloadScoreLogs,
    Sport? parseAsSport,
    bool? ignoreUnknownDivisions,
    bool? fuzzyHitFactorDivisionMatching,
  }) {
    return PscMatchFetchOptions(
      downloadScoreLogs: downloadScoreLogs ?? this.downloadScoreLogs,
      parseAsSport: parseAsSport ?? this.parseAsSport,
      ignoreUnknownDivisions: ignoreUnknownDivisions ?? this.ignoreUnknownDivisions,
      fuzzyHitFactorDivisionMatching: fuzzyHitFactorDivisionMatching ?? this.fuzzyHitFactorDivisionMatching,
    );
  }
}