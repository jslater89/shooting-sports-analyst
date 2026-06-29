import "package:shooting_sports_analyst/console/repl.dart";

import "context.dart";

abstract class AdminConsoleCommand extends MenuCommandClass {
  final AdminConsoleContext ctx;

  AdminConsoleCommand(this.ctx);
}
