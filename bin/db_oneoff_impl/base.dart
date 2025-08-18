import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';

abstract class DbOneoffCommand extends MenuCommandClass {
  final AnalystDatabase db;
  DbOneoffCommand(this.db);
}
