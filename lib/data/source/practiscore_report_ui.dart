import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/practiscore_parser.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/practiscore_report.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/source/source_ui.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/util.dart';

class PractiscoreReportUI extends SourceUI {
  @override
  Widget getDownloadMatchUIFor({
    required MatchSource source,
    required void Function(ShootingMatch) onMatchSelected,
    void Function(ShootingMatch)? onMatchDownloaded,
    required void Function(MatchSourceError) onError,
    String? initialSearch,
  }) {
    source as PractiscoreHitFactorReportParser;
    return Builder(builder: (context) {
      var onSubmitted = (String value) async {
        var matchId = await processMatchUrl(value);
        if(matchId != null) {
          var matchResult = await source.getMatchFromId(matchId, sport: source.sport);
          if(matchResult.isErr()) {
            onError(matchResult.unwrapErr());
          }
          else {
            onMatchSelected(matchResult.unwrap());
          }
        }
        else {
          onError(FormatError(StringError("Match ID not found in URL")));
        }
      };
      var controller = TextEditingController(text: initialSearch);
      return Column(
        children: [
          Text("Enter a link to a match and press Enter."),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: "https://practiscore.com/results/new/...",
                suffixIcon: IconButton(
                  color: Theme.of(context).buttonTheme.colorScheme?.primary,
                  icon: Icon(Icons.search),
                  onPressed: () {
                    onSubmitted(controller.text);
                  },
                )
            ),
            onSubmitted: onSubmitted,
          ),
        ],
      );
    });
  }
}
