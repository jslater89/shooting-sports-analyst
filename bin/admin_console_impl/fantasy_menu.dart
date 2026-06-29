import "package:dart_console/dart_console.dart";
import "package:shooting_sports_analyst/console/repl.dart";
import "package:shooting_sports_analyst/server/fantasy/cli/calculate_annual_stats.dart";
import "package:shooting_sports_analyst/server/fantasy/cli/lookup_competitor_scores.dart";
import "package:shooting_sports_analyst/server/fantasy/cli/show_fantasy_leaders.dart";
import "package:shooting_sports_analyst/server/fantasy/cli/show_valid_groups.dart";

import "context.dart";
import "menu_helpers.dart";

Future<void> fantasyMenuLoop(Console console, AdminConsoleContext ctx) async {
  int ratingContextId() => ctx.ratingContextId;

  await menuLoop(console, [
    _FantasyUsageStatsCommand(),
    _FantasyCalculateStatsForYearCommand(ratingContextId),
    _FantasyShowGroupsCommand(),
    _FantasyShowLeadersCommand(),
    _FantasyLookupCompetitorScoresCommand(),
    BackMenuCommand(),
  ],
    menuHeader: "Fantasy Menu",
    commandSelected: (command) async {
      if(command.command is BackMenuCommand) {
        return false;
      }
      return true;
    },
  );
}

class _FantasyUsageStatsCommand extends MenuCommand {
  @override
  final String key = "1";

  @override
  final String title = "Usage Stats";

  @override
  CommandExecutor? get execute => notYetImplementedExecutor;
}

class _FantasyCalculateStatsForYearCommand extends MenuCommand {
  _FantasyCalculateStatsForYearCommand(this._ratingContextId);

  final int Function() _ratingContextId;

  @override
  final String key = "2";

  @override
  final String title = "Calculate Stats for Year";

  @override
  List<MenuArgument> get arguments => [
    IntMenuArgument(label: "Year", required: true),
    IntMenuArgument(label: "Ratings Context", defaultValueFactory: _ratingContextId),
  ];

  @override
  CommandExecutor? get execute => calculateAnnualStats;
}

class _FantasyShowGroupsCommand extends MenuCommand {
  @override
  final String key = "3";

  @override
  final String title = "Show Valid Groups";

  @override
  CommandExecutor? get execute => showValidGroupsForFantasyProject;
}

class _FantasyShowLeadersCommand extends MenuCommand {
  @override
  final String key = "4";

  @override
  final String title = "Show Fantasy Scoring Leaders";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "Group", required: true),
    IntMenuArgument(label: "Year", required: true),
    StringMenuArgument(label: "Month", description: "A numeric month, or 'all' to print monthly stats for the full year"),
  ];

  @override
  CommandExecutor? get execute => showFantasyScoringLeaders;
}

class _FantasyLookupCompetitorScoresCommand extends MenuCommand {
  @override
  final String key = "5";

  @override
  final String title = "Lookup Competitor Scores";

  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(label: "Group", required: true),
    StringMenuArgument(label: "Name", required: true),
  ];

  @override
  CommandExecutor? get execute => lookupCompetitorScores;
}
