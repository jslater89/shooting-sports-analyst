/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport_link.dart';

final ipscToUspsaLink = SportLink(
  sourceSport: ipscSport,
  targetSport: uspsaSport,
  canIngest: true,
  canPredict: true,
  divisionLinks: [
    DivisionLink(
      sourceDivisions: [ipscOpen],
      targetDivision: uspsaOpen,
    ),
    DivisionLink(
      sourceDivisions: [ipscStandard],
      targetDivision: uspsaLimited,
    ),
    DivisionLink(
      sourceDivisions: [ipscPccOptics],
      targetDivision: uspsaPcc,
    ),
    DivisionLink(
      sourceDivisions: [ipscOptics],
      targetDivision: uspsaLimitedOptics,
    ),
    DivisionLink(
      sourceDivisions: [ipscProductionOptics],
      targetDivision: uspsaCarryOptics,
    ),
    DivisionLink(
      sourceDivisions: [ipscProduction],
      targetDivision: uspsaProduction,
    ),
    DivisionLink(
      sourceDivisions: [ipscClassic],
      targetDivision: uspsaSingleStack,
    ),
    DivisionLink(
      sourceDivisions: [ipscRevolver],
      targetDivision: uspsaRevolver,
    ),
    // There is no IPSC Limited 10
  ],
);