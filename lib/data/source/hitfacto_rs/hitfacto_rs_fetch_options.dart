/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class HitfactoRsMatchFetchOptions implements InternalMatchFetchOptions {
  final bool downloadScoreLogs;
  final Sport? parseAsSport;
  final bool ignoreUnknownDivisions;
  final bool fuzzyHitFactorDivisionMatching;

  const HitfactoRsMatchFetchOptions({
    this.downloadScoreLogs = false,
    this.parseAsSport,
    this.ignoreUnknownDivisions = false,
    this.fuzzyHitFactorDivisionMatching = false,
  });

  HitfactoRsMatchFetchOptions copyWith({
    bool? downloadScoreLogs,
    Sport? parseAsSport,
    bool? ignoreUnknownDivisions,
    bool? fuzzyHitFactorDivisionMatching,
  }) {
    return HitfactoRsMatchFetchOptions(
      downloadScoreLogs: downloadScoreLogs ?? this.downloadScoreLogs,
      parseAsSport: parseAsSport ?? this.parseAsSport,
      ignoreUnknownDivisions:
          ignoreUnknownDivisions ?? this.ignoreUnknownDivisions,
      fuzzyHitFactorDivisionMatching:
          fuzzyHitFactorDivisionMatching ?? this.fuzzyHitFactorDivisionMatching,
    );
  }
}
