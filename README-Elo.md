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

### Obtaining quality results
The rating algorithm is not perfect, and there are some things you can do to increase the quality
of your results.

The first, and most important, is to use the minimum stages/minimum matches filter on the results
screen. Start with about 10 stages or 2 matches per year: this will filter out people who are on
the periphery of the dataset, who would otherwise cause noise in the results.

### Configuration screen

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

#### Action bar items
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

### "Classic Elo" refresher
Classic Elo operates by predicting the probability that one competitor will beat another in a 
two-player game, based on the difference in their ratings.

Depending on the actual result, the players exchange rating points. If one player is favored and she
wins, she gains a small number of rating points from her opponent. If one player is an underdog and
he wins, he gains a large number of rating points from his opponent. If both players are evenly
matched, the winner gains a moderate number of points.

The winner always gains points, and the loser always loses points. For a free-for-all game like
USPSA, where there is one winner but there isn't one loser, this is obviously not appropriate.

### Multiplayer Elo
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
The rating engine operates by division group: if a shooter has recorded performances in multiple
divisions in a dataset, he receives a rating in each of those divisions.

It can also operate in one of two modes: by stage, or by match. Internally, these are referred to
as _rating events_. In by-stage mode, a rating event is a stage. In by-match mode, a rating event
is a match. This section will refer to both stages and matches as rating events, except where
behavior differs between by-stage and by-match mode.

#### Initial ratings
When the engine encounters a shooter for the first time, he receives an initial rating: 800 for D
or U, 900 for C, 1000 for B, 1100 for A, 1200 for M, and 1300 for GM. Classification has no direct
effect on a shooter's rating after the initial rating. Note that the average Elo in a dataset will
generally be less than 1000, because C, D, and U shooters outnumber A, M, and GM shooters in most
sets.

For his first 10 rating events, a shooter's rating changes more rapidly, with a K factor multiplier
that scales from 2.5 down to 1.0, to increase the speed of initial placement.

#### Strength of schedule
When evaluating each match, the rating engine calculates a strength of schedule modifier used to
adjust K, using a weighted average of the classifications of the shooters present: GM counts for 10,
M for 6, A for 4, B for 3, C for 2, and D/U for 1. The match's strength of schedule ranges between
50% and 150% based on the difference between the average and 4. The strength of schedule modifier is
further adjusted by a multiplier for match level: L1 matches count for 100%, L2 matches for 115%,
and L3 matches for 130%.

### Connectedness
The engine also calculates a connectedness multiplier for each match. In an ideal world, every
competitor would shoot against everyone else the same number of times. (An ideal world for
determining ratings, at least.) In the real world, shooters compete at varying times and in
varying places; some shooters travel widely in a region, and some stick to a few matches.

A shooter's connectedness is 1% of the sum of the connectednesses of the 40 best-connected shooters
he has competed against in the last 60 days, updated when he shoots a match. (That is, connections
will not expire unless a shooter is competing actively.) The purpose of connectedness is to measure
the degree to which a shooter's current rating derives from the ratings of a broad range of other
shooters in the dataset, even if he doesn't shoot against them directly. Highly connected shooters
are rating carriers: their ratings account for performance against many other shooters, so matches
that include them yield more reliable results.

The rating engine determines the expected connectedness of a match by taking the average
connectedness of all shooters at a match, and comparing it to the median of the connectednesses of
all known shooters who have completed more than 30 stages or 5 matches. Matches more connected than
the median receive a K multiplier of up to 120%. Matches less connected than the median receive a
multiplier of down to 80%.

#### Match-specific processing
In match mode, the engine removes anyone with a DQ on record, or anyone who did not finish
one or more stages. (The engine assumes a stage was a DNF if it has zero time and zero scoring
events—i.e., hits, scored misses, penalties, or NPMs.)

#### Stage processing
In stage mode, the engine ignores DNFed stages, but _includes_ stages a disqualified shooter
completed before disqualifying.

By-stage mode also examines the scores for each stage, and applies a negative modifier to K if
more than 10% of shooters zeroed it, from 100% K at 10% to 34% K at 30%.

#### Final calculations
Finally, having determined the above modifiers, the engine moves on to changing ratings. For each
shooter, the engine calculates an expected score between 0 and 1 for the shooter, based on the
ratings of other shooters at the match. 0 corresponds to last place, and 1 corresponds to a stage
win. In percentage terms, the expected score may exceed 100%: the algorithm expects the shooter to
not only win, but win by a particular margin.

The shooter's actual percentage and place are both normalized to values between 0 and 1.
Additionally, for the winning shooter, the actual percentage is adjusted to account for his margin
of victory.

The ratio between actual score and expected score determines the amount of rating adjustment, scaled
by the percentage weight and placement weight from the engine's settings. Rating changes for all
competitors are calculated prior to applying any changes to the data used for calculation.