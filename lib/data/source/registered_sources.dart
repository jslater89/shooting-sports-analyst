/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/ipsc.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/pcsl.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';

class MatchSourceRegistry {
  static MatchSourceRegistry? _instance;
  factory MatchSourceRegistry() {
    _instance ??= MatchSourceRegistry._();
    return _instance!;
  }

  MatchSourceRegistry._();

  MatchSource getByCode(String code, MatchSource fallback) {
    return sources.firstWhereOrNull((e) => e.handledCodes.contains(code)) ?? fallback;
  }

  MatchSource? getByCodeOrNull(String code) {
    return sources.firstWhereOrNull((e) => e.handledCodes.contains(code));
  }

  List<MatchSource> _sources = [
    PSv2MatchSource(),
    PractiscoreHitFactorReportParser(uspsaSport),
    PractiscoreHitFactorReportParser(ipscSport),
    PractiscoreHitFactorReportParser(pcslSport),
  ];
  List<MatchSource> get sources => _sources.where((element) => element.isImplemented).toList(growable: false);

  List<MatchSource> get practiscoreUrlSources => _sources.where((e) => e is PractiscoreHitFactorReportParser).toList();
}
