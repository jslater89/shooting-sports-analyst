import "package:shooting_sports_analyst/console/repl.dart";

class BackMenuCommand extends MenuCommand {
  @override
  final String key = "B";

  @override
  final String title = "Back";
}

class QuitMenuCommand extends MenuCommand {
  @override
  final String key = "Q";

  @override
  final String title = "Quit";
}

class SubMenuCommand extends MenuCommand {
  SubMenuCommand({required this.key, required this.title});

  @override
  final String key;

  @override
  final String title;
}
