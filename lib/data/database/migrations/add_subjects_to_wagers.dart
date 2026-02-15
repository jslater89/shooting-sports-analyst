import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/migrations/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/migration.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';

class AddSubjectsToWagers extends Migration {
  @override
  Future<void> doMigration(AnalystDatabase db) async {
    // resave all wagers to pick up the subject member numbers
    var wagers = await db.isar.dbWagers.where().findAll();
    for(var wager in wagers) {
      for(var leg in wager.legs) {
        var targetRating = await leg.target.getShooterRating(db);
        var underdogRating = await leg.underdog?.getShooterRating(db);

        if(targetRating != null) {
          leg.target.knownMemberNumbers = [...targetRating.knownMemberNumbers];
        }
        if(underdogRating != null) {
          leg.underdog!.knownMemberNumbers = [...underdogRating.knownMemberNumbers];
        }
      }

      await db.saveWager(wager);
    }
  }

  @override
  MigrationRecord get record => MigrationRecord(
    name: 'add_subjects_to_wagers',
    applied: DateTime.now(),
  );
}
