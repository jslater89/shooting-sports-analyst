/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/search.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

class PSWebMatchSearchSource extends SearchSource {
  @override
  bool get isImplemented => false;
  @override
  String get code => "ps_web_stub";

  @override
  String get name => "PS Web Stub";

  @override
  List<Sport> get supportedSports => [];

  final String downloadSourceCode;

  PSWebMatchSearchSource({required this.downloadSourceCode});

  @override
  Future<SearchSourceResult> searchByName(String name, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }
}
