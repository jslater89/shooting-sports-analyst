import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:shooting_sports_analyst/console/repl.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/classifier_import.dart';
import 'package:shooting_sports_analyst/data/source/classifiers/icore_export_converter.dart';
import 'package:shooting_sports_analyst/util.dart';

import 'base.dart';

class AnalyzeIcoreDumpCommand extends DbOneoffCommand {
  AnalyzeIcoreDumpCommand(AnalystDatabase db) : super(db);

  @override
  final String key = "AID";
  @override
  final String title = "Analyze Icore Dump";
  @override
  List<MenuArgument> get arguments => [
    StringMenuArgument(
      label: "file",
      description: "Path to an ICORE DB JSON dump to analyze",
      required: true,
    ),
  ];

  @override
  Future<void> executor(Console console, List<MenuArgumentValue> arguments) async {
    var path = arguments.first.value;
    var file = File(path);
    if(!file.existsSync()) {
      console.print("File does not exist: ${file.path}");
      return;
    }
    await _analyzeIcoreDump(db, console, file);
  }
}

Future<void> _analyzeIcoreDump(AnalystDatabase db, Console console, File file) async {
  var masterScores = IcoreClassifierExport.fromFile(file);
  var analystScores = masterScores.toAnalystScores();

  Map<DateTime, Map<String, List<ClassifierScore>>> scoresByDateDivision = {};
  for(var score in analystScores) {
    var monthDate = DateTime(score.date.year, score.date.month, 1);
    var monthMap = scoresByDateDivision[monthDate] ?? {};
    monthMap.addToList(score.division, score);
    scoresByDateDivision[monthDate] = monthMap;
  }

  for(var date in scoresByDateDivision.keys.sorted((a, b) => b.compareTo(a))) {
    var monthMap = scoresByDateDivision[date]!;
    console.print("${programmerYmdFormat.format(date)}:");
    for(var division in monthMap.keys.sorted((a, b) => a.compareTo(b))) {
      var scores = monthMap[division]!;
      Map<String, List<ClassifierScore>> scoresByClassifier = {};
      for(var score in scores) {
        scoresByClassifier.addToList(score.classifierCode, score);
      }
      var withEnoughScores = scoresByClassifier.values.where((e) => e.length >= 4);
      console.print("\t${division}: ${scores.length} (${withEnoughScores.length} eligible)");
    }
  }
}
