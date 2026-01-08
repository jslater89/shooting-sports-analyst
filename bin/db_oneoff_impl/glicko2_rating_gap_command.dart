import 'package:dart_console/src/console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/glicko2/glicko2_rater.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class Glicko2RatingGapCommand extends DbOneoffCommand {
  Glicko2RatingGapCommand(AnalystDatabase db) : super(db);

  @override
  List<MenuArgument> get arguments => [
    IntMenuArgument(label: "Rating 1", required: true),
    IntMenuArgument(label: "Rating 2", required: true),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var rating1 = arguments.firstWhere((argument) => argument.argument.label == "Rating 1").value as int;
    var rating2 = arguments.firstWhere((argument) => argument.argument.label == "Rating 2").value as int;
    var project = await db.getRatingProjectByName("ICORE Regionals + Classifiers");

    if(project == null) {
      console.print("Rating project not found");
      return;
    }

    var betterRating = rating1 > rating2 ? rating1 : rating2;
    var worseRating = rating1 > rating2 ? rating2 : rating1;

    var algorithm = project.settings.algorithm as Glicko2Rater;
    var expectedScore = algorithm.glickoExpectedScore(betterRating.toDouble(), worseRating.toDouble(), 40);
    var perfectVictoryMargin = algorithm.settings.perfectVictoryDifference;

    var expectedPercentageGap = lerpAroundCenter(
      value: expectedScore,
      center: 0.5,
      rangeMin: 0.0,
      rangeMax: 1.0,
      minOut: -perfectVictoryMargin,
      centerOut: 0.0,
      maxOut: perfectVictoryMargin,
    );

    console.print("Rating $betterRating vs. $worseRating wins by ${expectedPercentageGap.asPercentage(decimals: 1, includePercent: true)}");
    console.print("100% vs. ${(1 - expectedPercentageGap).asPercentage(decimals: 1, includePercent: true)}");
    if(expectedScore > (1 - algorithm.settings.eLinearRegion) || expectedScore < algorithm.settings.eLinearRegion) {
      console.print("Caution: expected score ${expectedScore.toStringWithSignificantDigits(3)} is outside the linear region");
      return;
    }
  }

  @override
  String get key => "GRG";

  @override
  String get title => "Glicko2 Rating Gap";
}