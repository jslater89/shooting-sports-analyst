import "package:shooting_sports_analyst/data/help/elo_configuration_help.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const eloHelpId = "elo";
const eloHelpLink = "?elo";
final helpElo = HelpTopic(
  id: eloHelpId,
  name: "Elo rating system",
  content: _content,
);

const _content =
"# Elo Rating System\n"
"\n"
"The Elo rating system, [originally developed for chess](https://en.wikipedia.org/wiki/Elo_rating_system), "
"predicts match outcomes by comparing the ratings of competitors. When actual results differ from predictions, "
"ratings are adjusted accordingly. For help configuring Shooting Sports Analyst's Elo implementation, see the "
"[Elo configuration guide]($eloConfigHelpLink).\n"
"\n"
"## Core Concepts\n"
"\n"
"* Higher ratings indicate stronger competitors\n"
"* Beating a higher-rated opponent gains more points than beating a lower-rated one\n"
"* The size of rating changes depends on how unexpected the result was\n"
"\n"
"## Shooting Sports Adaptations\n"
"\n"
"The system includes several modifications for shooting sports:\n"
"\n"
"### Initial Ratings by Classification\n"
"In shooting sports where members commonly enter classifications during match registration, "
"initial ratings are based on classification. In USPSA, the figures are as follows:\n"
"* D=800\n"
"* C or U=900\n"
"* B=1000\n"
"* A=1100\n"
"* M=1200\n"
"* GM=1300\n"
"\n"
"### Multiplayer Support\n"
"Whereas classical Elo compares competitors head-to-head, Shooting Sports Analyst's Elo "
"is a [multiplayer generalization](https://medium.com/towards-data-science/developing-a-generalized-elo-rating-system-for-multiplayer-games-b9b495e87802). "
"This allows the system to compare each competitor against the entire field holistically, "
"rather than in pairwise fashion against each other competitor.\n"
"\n"
"### Confidence Adjustments\n"
"The system employs several confidence-based adjustments to improve accuracy. New shooters experience larger "
"rating changes initially to help establish their proper skill level quickly. The system includes error tracking "
"that reduces rating changes when predictions have been consistently accurate. Additionally, competitors who face "
"a diverse range of opponents receive more weight in their rating adjustments through connectivity tracking. The "
"system also incorporates streak detection to better respond to shooters who are rapidly improving or declining "
"in performance.\n"
"\n"
"### Stage-Specific\n"
"Stage characteristics influence rating adjustments in several ways. Shorter stages have a slightly reduced "
"impact while longer stages carry more weight in calculations. When many shooters score zero on a stage, its "
"impact on ratings is reduced. The system can also combine both stage and match results to balance between "
"responsive rating changes and rating stability based on match results.\n"
"\n"
"## Tips\n"
"\n"
"When interpreting ratings, keep in mind that they cannot be directly compared across different divisions. "
"Rating differences of 50-100 points should be considered relatively minor. The algorithm performs best "
"when analyzing groups of competitors who frequently compete against each other. Isolated groups of competitors "
"may have ratings that are less reliable.";
