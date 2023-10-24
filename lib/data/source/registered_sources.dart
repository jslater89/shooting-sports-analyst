/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:uspsa_result_viewer/data/source/practiscore_report.dart';
import 'package:uspsa_result_viewer/data/source/psv2/psv2_source.dart';
import 'package:uspsa_result_viewer/data/source/source.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/ipsc.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';

class MatchSourceRegistry {
  static MatchSourceRegistry? _instance;
  factory MatchSourceRegistry() {
    _instance ??= MatchSourceRegistry._();
    return _instance!;
  }

  MatchSourceRegistry._();

  List<MatchSource> _sources = [
    PSv2MatchSource(),
    PractiscoreHitFactorReportParser(uspsaSport),
    PractiscoreHitFactorReportParser(ipscSport),
  ];
  List<MatchSource> get sources => _sources.where((element) => element.isImplemented).toList(growable: false);
}