/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/source/prematch/search.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class PSWebMatchSearchSource extends SearchSource {
  @override
  bool get isImplemented => false;
  @override
  String get code => "ps_web_stub";

  @override
  String get name => "PS Web Stub";

  @override
  List<Sport> get supportedSports => [];
}
