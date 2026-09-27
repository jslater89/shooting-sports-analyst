/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport_link.dart';

final uspsaToIpscLink = SportLink(
  sourceSport: uspsaSport,
  targetSport: ipscSport,
  canIngest: true,
  canPredict: true,
  divisionLinks: [
    DivisionLink(
      sourceDivisions: [uspsaOpen],
      targetDivision: ipscOpen,
    ),
    DivisionLink(
      sourceDivisions: [uspsaLimited],
      targetDivision: ipscStandard,
    ),
    DivisionLink(
      sourceDivisions: [uspsaPcc],
      targetDivision: ipscPccOptics,
    ),
    DivisionLink(
      sourceDivisions: [uspsaLimitedOptics],
      targetDivision: ipscOptics,
    ),
    DivisionLink(
      sourceDivisions: [uspsaCarryOptics],
      targetDivision: ipscProductionOptics,
    ),
    DivisionLink(
      sourceDivisions: [uspsaProduction],
      targetDivision: ipscProduction,
    ),
    DivisionLink(
      sourceDivisions: [uspsaSingleStack],
      targetDivision: ipscClassic,
    ),
    DivisionLink(
      sourceDivisions: [uspsaRevolver],
      targetDivision: ipscRevolver,
    ),
    // There is no IPSC Limited 10
  ],
);