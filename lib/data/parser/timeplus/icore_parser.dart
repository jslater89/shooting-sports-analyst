import 'package:uspsa_result_viewer/data/match/timeplus/timeplus_match.dart';

TimePlusMatch parseIcoreMatch(String matchId, String indexHtml, List<String> stageHtml) {
  TimePlusMatch match = TimePlusMatch();

  // TODO: match info from indexHtml

  for(var stagePage in stageHtml) {
    var stageLines = stagePage.split("\n");

    for(var line in stageLines) {
      if(line.contains("Stage Results - ")) {
        // parse stage name
      }
      else if(line.contains('<td class="name_cell">')) {
        // parse score line
      }
    }
  }

  return match;
}