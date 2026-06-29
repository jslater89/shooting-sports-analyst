import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";

class AdminConsoleContext {
  final AnalystDatabase db;
  DbRatingProject? ratingContext;

  AdminConsoleContext(this.db);

  int get ratingContextId => ratingContext?.id ?? -1;
}
