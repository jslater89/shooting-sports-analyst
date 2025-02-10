import "package:shooting_sports_analyst/data/help/elo_help.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart";

const eloConfigHelpId = "elo_config";
const eloConfigHelpLink = "?elo_config";
final helpEloConfig = HelpTopic(
  id: eloConfigHelpId,
  name: "Elo configuration",
  content: _content,
);

const _content =
"# Elo Configuration\n"
"\n"
"The Elo rating system can be fine-tuned through several parameters. This guide explains each setting and its effects. "
"For general information on the Elo rating system, see the [Elo help entry]($eloHelpLink).\n"
"\n"
"### Basic Parameters\n"
"**K factor** controls how quickly ratings change, and is the maximum unadjusted rating change per rating event. "
"Higher values mean larger rating adjustments after each rating event, while lower values produce more stable ratings. "
"The **Scale** parameter sets the rating difference that makes one shooter more likely to win, while **Probability base** "
"determines the likelihood per scale rating difference. For example, with a scale of 400 and probability base of 10, "
"a shooter rated 400 points higher is 10 times more likely to win.\n"
"\n"
"### Scoring Weights\n"
"**Place weight** and **Percent weight** balance the importance of ordinal finishing position versus percentage finish. "
"Higher place weight emphasizes winning events outright, while higher percent weight rewards consistent "
"high-percentage finishes even without wins. In by-stage rating mode, **Match blend** controls a weighted averaging of "
"a competitor's match results into the results of each stage. Match blend rewards consistency and more directly "
"predicts a competitor's match performance, but reduces the responsiveness of the rating system.\n"
"\n"
"## Adaptive K-Factor\n"
"\n"
"### Error-Aware K\n"
"**Error-aware K** reduces rating changes when the system's predictions are consistently accurate, suggesting it "
"has found the correct rating. When a competitor's error is between **Zero value** and **Min threshold**, the K factor "
"will be multiplied by a value between 1.0 and **Lower multiplier**. When a competitor's erorr is between **Max threshold** "
"and **Upper value**, the K factor will be multiplied by a value between 1.0 and **Upper multiplier**.\n"
"\n"
"### Streak Settings\n"
"Streak settings control how the K factor is adjusted during streaks of consistent rating improvement or decline. "
"**Streak limit** determines what constitues a streak: if streak limit is 0.40, then a competitor is on a positive streak "
"if their direction is greater than +40, or a negative streak if their direction is less than -40. When **Ignore "
"error-aware K** is enabled, error-aware K adjustments will be ignored when the competitor is on a streak. "
"**Direction-aware K** adjusts K when a user is on a streak, between 1.0 and **On-streak multiplier** when direction is "
"positive and between the streak limit and +100 (or 1.0), and between 1.0 and **Off-streak multiplier** when direction is "
"negative and between the streak limit and +100 (or -1.0).\n"
"\n"
"### Bomb Protection\n"
"**Bomb protection** reduces the impact of unusually poor performances, which often result from equipment problems "
"or other non-skill-related factors. This helps prevent large rating drops from isolated bad stages while still "
"allowing ratings to decrease when performance consistently declines. By default, it only applies to competitors "
"with a high expected finish, since one bad performance causes a substantial rating drop at that level, whereas "
"the rating changes from good performances are much smaller, since the expected finish is high.\n"
"\n"
"**Bomb minimum K reduction** and **Bomb maximum K reduction** control the magnitude of the adjustment to the K " 
"factor. **Bomb threshold** specifies the minimum rating loss, as a factor of the base K factor, where bomb "
"protection will activate, applying the minimum K reduction. **Bomb maximum** specifies the rating loss, as a "
"factor of the base K factor, where bomb protection applies the maximum K reduction.\n"
"\n"
"**Bomb minimum percentage** and **Bomb maximum percentage** limit bomb protection to competitors with high "
"expected finishes. Bomb protection will apply at 0% strength for competitors with an expected finish at or below "
"the minimum percentage, and at maximum strength for competitors with an expected finish at or above the maximum "
"percentage.";

