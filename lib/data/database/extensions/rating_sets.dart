/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_set.dart';

extension RatingSetDatabase on AnalystDatabase {
  Future<List<RatingSet>> getRatingSets() async {
    return await isar.ratingSets.where().sortByDisplayName().findAll();
  }

  List<RatingSet> getRatingSetsSync() {
    return isar.ratingSets.where().sortByDisplayName().findAllSync();
  }

  Future<void> saveRatingSet(RatingSet set) async {
    await isar.writeTxn(() async {
      await isar.ratingSets.put(set);
    });
  }

  void saveRatingSetSync(RatingSet set) {
    isar.writeTxnSync(() {
      isar.ratingSets.putSync(set);
    });
  }

  Future<void> deleteRatingSet(RatingSet set) async {
    await isar.writeTxn(() async {
      await isar.ratingSets.where().idEqualTo(set.id).deleteAll();
    });
  }

  void deleteRatingSetSync(RatingSet set) {
    isar.writeTxnSync(() {
      isar.ratingSets.where().idEqualTo(set.id).deleteAllSync();
    });
  }
}
