/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
This is the PractiScore registration source stub.
 */

import 'package:shooting_sports_analyst/closed_sources/ps_registration/ps_registration_code.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

/*
This is a stub file. The full PractiScore registration source is implemented elsewhere.
 */
class PSRegistrationSource extends FutureMatchSource {
  @override
  String get name => "PractiScore Registration";

  @override
  String get code => psRegistrationCode;

  @override
  bool get isImplemented => false;

  @override
  bool get canSearchByName => false;

  @override
  bool get canFilterSearchesBySport => false;

  @override
  List<SportType> get supportedSports => [
    SportType.uspsa,
    SportType.ipsc,
    SportType.idpa,
    SportType.pcsl,
  ];

  Future<Result<void, MatchSourceError>> downloadMatchMeta(String raw) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }
}
