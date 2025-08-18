
import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/labeled_progress_bar.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/match/hydrated_cache.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class TomCastroCommand extends DbOneoffCommand {
  TomCastroCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "TC";
  @override
  final String title = "How Good Is Tom Castro?";
  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    await _howGoodIsTomCastro(db, console);
  }
}

Future<void> _howGoodIsTomCastro(AnalystDatabase db, Console console) async {
  var project = (await db.getRatingProjectByName("L2s Main"))!;
  var pccGroup = await project.groupForDivision(uspsaPcc).unwrap();
  var coGroup = await project.groupForDivision(uspsaCarryOptics).unwrap();
  Set<String> memberNumbers = {};
  var pccTom = await project.getRatingsByDeduplicatorName(pccGroup!, "tomcastro").unwrap();
  var coTom = await project.getRatingsByDeduplicatorName(coGroup!, "tomcastro").unwrap();
  memberNumbers.addAll(pccTom.map((e) => e.allPossibleMemberNumbers).flattened);
  memberNumbers.addAll(coTom.map((e) => e.allPossibleMemberNumbers).flattened);
  var tomMatches = await db.getMatchesByMemberNumbers(memberNumbers.toList());
  console.print("Tom matches: ${tomMatches.length}");

  List<int> tomPccFinishes = [];
  List<int> tomCoFinishes = [];
  List<String> matchNamesThatCount = [];
  List<int> pccMatchSizes = [];
  List<int> coMatchSizes = [];
  var matchProgressBar = LabeledProgressBar(maxValue: tomMatches.length, initialLabel: "Processing matches...");
  for(var match in tomMatches) {
    if(match.eventName.toLowerCase().contains("fipt") || match.eventName.toLowerCase().contains("f.i.p.t.")) continue;
    if(match.eventName.toLowerCase().contains("side match")) continue;
    if(match.eventName.toLowerCase().contains("richmond hotshots")) continue;
    if(match.matchEventLevel == uspsaLevel1
      && !match.eventName.toLowerCase().contains("national")
      && !match.eventName.toLowerCase().contains("area")
      && !match.eventName.toLowerCase().contains("championship")
      && !match.eventName.toLowerCase().contains("sectional")
      && !match.eventName.toLowerCase().contains("ipsc")) continue;
    for(var entry in match.shooters) {
      if(memberNumbers.contains(entry.memberNumber)) {
        var division = uspsaSport.divisions.lookupByName(entry.divisionName);
        if(division == uspsaPcc) {
          if(entry.precalculatedScore == null) {
            tomPccFinishes.add(await _getTomPlace(match, entry));
          }
          else {
            tomPccFinishes.add(entry.precalculatedScore!.place);
          }
          pccMatchSizes.add(match.shooters.where((e) => e.divisionName == entry.divisionName).length);
          matchNamesThatCount.add(match.eventName);
        }
        else if(division == uspsaCarryOptics) {
          if(entry.precalculatedScore == null) {
            tomCoFinishes.add(await _getTomPlace(match, entry));
          }
          else {
            tomCoFinishes.add(entry.precalculatedScore!.place);
          }
          matchNamesThatCount.add(match.eventName);
          coMatchSizes.add(match.shooters.where((e) => e.divisionName == entry.divisionName).length);
        }
        else {
          print("Tom competed in ${entry.divisionName}");
        }
      }
    }
    matchProgressBar.tick();
  }
  matchProgressBar.complete();

  var pccWins = tomPccFinishes.where((e) => e == 1).length;
  var coWins = tomCoFinishes.where((e) => e == 1).length;
  console.print("Match names that count: \n${matchNamesThatCount.join("\n")}");
  console.print("PCC wins: $pccWins/${tomPccFinishes.length}");
  console.print("CO wins: $coWins/${tomCoFinishes.length}");
  console.print("PCC average finish: ${tomPccFinishes.average.toStringAsFixed(2)}/${pccMatchSizes.average.toStringAsFixed(2)}");
  console.print("CO average finish: ${tomCoFinishes.average.toStringAsFixed(2)}/${coMatchSizes.average.toStringAsFixed(2)}");
}

Future<int> _getTomPlace(DbShootingMatch match, DbMatchEntry entry) async {
  var matchRes = await HydratedMatchCache().get(match);
  if(matchRes.isErr()) {
    throw ArgumentError();
  }
  var division = uspsaSport.divisions.lookupByName(entry.divisionName);
  if(division == null) {
    throw ArgumentError();
  }
  var scores = matchRes.unwrap().getScoresFromFilters(FilterSet(uspsaSport, divisions: [division]));
  return scores.entries.firstWhere((e) => e.key.memberNumber == entry.memberNumber).value.place;
}
