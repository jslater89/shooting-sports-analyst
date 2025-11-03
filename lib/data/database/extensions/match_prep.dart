/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';

extension MatchPrepDatabase on AnalystDatabase {
  Future<void> saveFutureMatch(FutureMatch match, {List<MatchPrepLinkTypes> updateLinks = MatchPrepLinkTypes.values}) async {
    await isar.writeTxn(() async {
      await isar.futureMatchs.put(match);
      if(updateLinks.contains(MatchPrepLinkTypes.registrations)) {
        await match.registrations.save();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.mappings)) {
        await match.mappings.save();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.dbMatch)) {
        await match.dbMatch.save();
      }
    });
  }

  void saveFutureMatchSync(FutureMatch match, {List<MatchPrepLinkTypes> updateLinks = MatchPrepLinkTypes.values}) {
    isar.writeTxnSync(() {
      isar.futureMatchs.putSync(match);
      if(updateLinks.contains(MatchPrepLinkTypes.registrations)) {
        match.registrations.saveSync();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.mappings)) {
        match.mappings.saveSync();
      }
      if(updateLinks.contains(MatchPrepLinkTypes.dbMatch)) {
        match.dbMatch.saveSync();
      }
    });
  }
}

enum MatchPrepLinkTypes {
  registrations,
  mappings,
  dbMatch,
}
