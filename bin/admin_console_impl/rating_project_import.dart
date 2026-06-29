import "dart:convert";
import "dart:io";

import "package:collection/collection.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/util.dart";

Future<Result<DbRatingProject, StringError>> importRatingProjectFromJsonFile(
  AnalystDatabase db,
  String path, {
  required bool overwrite,
}) async {
  final file = File(path);
  if(!file.existsSync()) {
    return StringError.result("File does not exist: $path");
  }

  final imported = jsonDecode(file.readAsStringSync());
  if(imported is! Map<String, dynamic>) {
    return StringError.result("Invalid project file, root is: ${imported.runtimeType}");
  }

  DbRatingProject project;
  try {
    project = DbRatingProject.fromJson(imported);
  }
  catch(e, st) {
    return StringError.result("Invalid project file, root is: ${imported.runtimeType}, error: ${e.toString()}, stackTrace: ${st.toString()}");
  }

  final existingProject = await db.getRatingProjectByName(project.name);
  if(existingProject != null && !overwrite) {
    return StringError.result("Project already exists: ${project.name}");
  }

  if(existingProject != null) {
    List<MatchPointer> usedMatches = [];
    var sortedMatches = project.matchesToUse().sorted((a, b) => a.date!.compareTo(b.date!));
    for(var match in sortedMatches) {
      if(existingProject.matchPointers.contains(match)) {
        usedMatches.add(match);
      }
    }
    project.lastUsedMatches = usedMatches;
    project.completedFullCalculation = existingProject.completedFullCalculation;
  }

  await db.saveRatingProject(project);
  return Result.ok(project);
}
