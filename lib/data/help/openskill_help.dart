import "package:shooting_sports_analyst/data/help/rating_event.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const openskillHelpId = "openskill";
const openskillHelpLink = "?openskill";
final helpOpenSkill = HelpTopic(
  id: openskillHelpId,
  name: "OpenSkill rating system",
  content: _content,
);

const _content =
"# OpenSkill Rating System\n"
"\n"
"OpenSkill is a modern, Bayesian rating system based on Microsoft's TrueSkill™, designed for multiplayer competitions. "
"Unlike Elo, which tracks a single rating number, OpenSkill maintains two values for each competitor: Mu (μ), "
"which represents the estimated skill level, and Sigma (σ), which represents the uncertainty in that estimate.\n"
"\n"
"## How It Works\n"
"\n"
"OpenSkill assumes that a competitor's performances follow a normal distribution. After each [rating event]($ratingEventHelpLink), "
"Mu moves up or down based on performance while Sigma decreases as more data is gathered. The displayed "
"rating is calculated as μ - 3σ, which provides a conservative estimate that will gradually increase as "
"uncertainty decreases. This means new shooters start with high uncertainty (high σ) and their ratings "
"become more stable over time as σ decreases.\n"
"\n"
"Shooting Sports Analyst's implementation of OpenSkill uses the Plackett-Luce model to calculate rating changes. "
"Other models may be implemented in the future, but OpenSkill development is largely paused on the basis of "
"a lack of promise in initial tests with OpenSkill generally.\n"
"\n"
"## Advantages\n"
"\n"
"The OpenSkill system offers several advantages over traditional rating methods. It handles multiplayer "
"competitions more naturally and explicitly tracks rating uncertainty. The mathematical framework is more "
"rigorous than Elo, leading to faster initial convergence on a shooter's true skill level. The system "
"can also better account for variations in performance and the relative strength of the competitive field.\n"
"\n"
"## Initial Ratings\n"
"\n"
"OpenSkill does not currently use classification to seed initial ratings. Instead, all competitors start "
"with the same uncertainty level (σ = 25/3) and the same mu (25.0).\n"
"\n"
"## Settings\n"
"\n"
"The OpenSkill settings are as follows:\n"
"\n"
"### Beta\n"
"The beta parameter controls the natural variability of ratings. When a competitor's sigma drops below beta, "
"beta will be used instead. The default value is half of sigma: 4.167.\n"
"\n"
"### Tau\n"
"The tau parameter is a small amount to add to sigma at every rating event, which allows fluidity in ratings as player skill changes. "
"The default value is 1/30 of beta: 0.139.";
