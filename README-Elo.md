# USPSA Elo Rating System
Desktop builds of the result viewer contain an Elo rating system, which applies a modified
Elo algorithm to USPSA match results to attempt to determine the approximate rating of each
competitor.

## No web version?
The rating system code is not currently optimized to the point that it is feasible to include
in the web app. For large datasets, it processes hundreds of thousands of stage scores with
math not well-suited to browser JavaScript engines, consumes more than 10gb of RAM, and displays
thousands of shooter ratings, all of which are obstacles to 

## Usage
Download and unzip the files. No installation is necessary.

For Windows, you will need the latest [Visual C++ runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe),
which you likely already have installed.

To enter the Elo rater, click the bottom icon from the application's main screen.

### Configuration Screen

#### Main options
* **By stage?**: whether the rating algorithm runs after every stage, or after every match. After
  every stage is the default, and causes ratings to converge on the correct values more quickly,
  at the cost of more variance in the ratings.
* **Keep full history?**: by default, the application considers all selected matches, then generates
  one report. If checked, the application will consider one match, generate a report, consider two
  matches, generate a report, and so on until all matches have been processed. Enabling this option
  will dramatically increase both processing time and memory use! Use with caution.
* **Combine divisions**: if checked, these options will combine the named divisions. This is useful
  for low-participation divisions, so locap is checked by default, but not generally necessary for
  high-participation divisions.
* **K factor**: the K factor to be used by the Elo algorithm, which controls the volatility of
  ratings, increasing the speed at which they converge to their correct values at the cost of more
  noise in the ratings.
* **Scale factor**: the scale factor used by the Elo algorithm's probability calculator, which
  controls the output range of the ratings. A higher scale factor yields a larger difference in
  rating units for a given difference in skill.
* **Place/percent weight**: how much the Elo algorithm weights actual vs. expected performances in
  finish order and actual vs. expected performances in stage or match percentage. A mix of both
  parameters seems to yield the best results in empirical testing.

#### Match selection
Use the plus button to add matches, supplying Practiscore match result URLs to the resulting dialog. 
You can paste multiple match URLs into the dialog, one per line. The application will remove
duplicate URLs.

Use the minus button at the top of the match list to clear it. Use the minus button next to each
URL to remove it individually.

During match processing, matches are downloaded to a local cache. If a URL is already present in
the local cache, the match name will be displayed rather than the raw URL.

### Action bar items
* **Clear match cache**: removes all locally-cached matches. If launching the rating configuration
  screen becomes excessively slow, this will speed it up.
* **Export to file**: export the current settings to a file which can be shared between users.
* **Import from file**: import settings from a file.
* **Save/load**: save or load a project from the application's internal storage.

### Ratings Screen
Ratings are displayed in descending order of Elo. The tabs at the top of the screen select
the division or division group of interest. _Ratings, trends, variances, and connectednesses are
not comparable across division groups._

The dropdown below the tabs displaying a match name will be enabled if you have 'keep full history'
enabled in settings, and allows you to select a match after which you wish to view ratings.

The search box searches by member name (case-insensitive). The minimum stages/matches box allows you
to filter out competitors whose ratings are based on fewer than the given number of events.

Clicking a shooter name will display a chart of their rating change over time, along with a list of
all the events on which their rating is based.

The action button in the top right corner will export the currently-selected division group's ratings
to CSV, for analysis in other tools.

#### Metrics
Variance is the average of the absolute change in a competitor's rating over the past 30 rating
events. Trend is the average of the direction of their rating changes over the past 30 events (+1
for positive changes, -1 for negative changes). A high variance and a trend near +1 or -1 means the
system is still finding the correct rating for a shooter. A high variance and a trend near 0 means
a shooter's rating is approximately correct, but that he frequently overperforms or underperforms
the rating algorithm's predictions. A low variance means the rating system usually predicts a
shooter's performances correctly.

Connectedness is a measure of how much the shooter competes against other people in the dataset.
Competitors with low connectedness relative to others in their division or division group have not
recently competed against many other people in the dataset, indicating a lesser degree of confidence
in their rating.

## The algorithm in detail
The rating engine uses a version of the classic Elo rating system generalized to multiplayer games.

Classic Elo operates by predicting the probability that one competitor will beat another in a 
two-player game, based on the difference in their ratings.

Depending on the actual result, the players exchange rating points. If one player is favored and she
wins, she gains a small number of rating points from her opponent. If one player is an underdog and
he wins, he gains a large number of rating points from his opponent. If both players are evenly
matched, the winner gains a moderate number of points.

The winner always gains points, and the loser always loses points. For a free-for-all game like
USPSA, where there is one winner but there isn't one loser, this is obviously not appropriate.

[Generalizing Elo to multiplayer games](https://towardsdatascience.com/developing-a-generalized-elo-rating-system-for-multiplayer-games-b9b495e87802?gi=f06e5b58c1e)
produces a more suitable system. For each player, the algorithm looks at the ratings of every other
player in the field, and uses them to generate an expected score. Players gain rating points for
beating their expected score, and lose points for falling short.

Using this method allows the rating engine to correctly reward competitors for improving against
tough competition, without requiring them to win outright. It also prevents high-level talent from
stacking rating points by repeatedly beating beginners: in our particular use case, against soft
competition, the rating engine will expect good shooters to win by substantial margins to maintain
their ratings.

### Generating shooter rating from start to finish
* Seeded by class
* IP multiplier
* Per match...
  * Strength of schedule multiplier
    * Match level multiplier
  * Connectedness multiplier
  * In by-match mode, remove people who DQed or DNFed a stage.
* Per stage...
  * Zero multiplier
  * Stages you shoot before DQing count, in by-stage mode!
    * DNFs removed
  * Calculate actual score for both percent and place
    * Apply based on multipliers