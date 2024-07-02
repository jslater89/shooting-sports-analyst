# Elo Rating System
Desktop builds of the result viewer contain an Elo rating system, which applies a modified
Elo algorithm to shooting match results to attempt to determine the approximate rating of each
competitor.

## FAQ
**Where's the web version?**
The rating system code is not currently optimized to the point that it is feasible to include
in the web app. For large datasets, it processes hundreds of thousands of stage scores with
math not well-suited to browser JavaScript engines, which makes it too slow for most cases.

Shooting Sports Analyst also saves match results locally, since downloading files is the slowest
part of the rating process, and to avoid hammering PractiScore too hard, and browser storage is
not up to the task.

**Why do the tooltips in some shooter details say the expected place is 2nd or below, but the
expected percentage is greater than 100%?**
The long version is too long for a FAQ, but the short version is that the rating points up for
grabs for percent finishes are spread more evenly among all competitors than the rating points
for place finishes. Put another way, finishing well in percentage terms can only take you so 
far: eventually, you'll need to start placing well in absolute terms to gain rating points.

See the "percent vs. placement" header in the algorithm explainer section of this document for a
somewhat deeper treatment.

**Why are the ratings wrong, in general?**
For one, there's still substantial testing and improvement to be done (though this version is
really quite good compared to its predecessors).

For another, try using a value of about 10 stages (or 2 matches) in the 'minimum stages' box in the
results view per 75 stages/15 matches in your dataset. The engine does an okay job of placing people
quickly, but it does a much better job comparing people above a minimum threshold of data.

Lastly, try adjusting the settings. The default settings are a compromise between the speed at which
an established shooter new to the dataset can reach the correct rating, and the amount of noise in
the ratings of shooters already present in the set.

**Why are the ratings wrong, in that someone worse than me has a higher rating?**
There are a few reasons why this might be.

The first is that it takes a relatively large difference in rating before the algorithm expects
one person to consistently beat another. A rating difference of 50 or 100 points doesn't matter 
very much, so if the better shooter is within that margin, you can more or less ignore the
difference.

The second is that Elo rewards volume, to a point. The algorithm makes an effort to minimize this
effect, but it is still present. Given equal skill, the person shooting 100 matches will likely be
rated more closely to their actual skill than the person shooting 10.

The third is that the algorithm strongly rewards consistency: it's easy to lose a lot of points by
bombing a stage, but hard to climb back up. 

The fourth possibility is that you are classified M or GM and shoot mostly against much weaker
competition. The algorithm contains a modifier that prevents highly-classed shooters from gaining
large amounts of rating points in such situations, applied when they win a match by 20% or more
against a second-place opponent two or more classes down.

## Usage
Download and unzip the files. No installation is necessary.

For Windows, you will need the latest [Visual C++ runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe),
which you likely already have installed.

To enter the Elo rater, click the bottom right from the application's main screen.

### Obtaining quality results
The rating algorithm is not perfect, and there are some things you can do to increase the quality
of your results.

The first, and most important, is to use the minimum stages/minimum matches filter on the results
screen. Start with about 10 stages or 2 matches per year: this will filter out people who are on
the periphery of the dataset, who would otherwise cause noise in the results.

The second is to choose your dataset well. The algorithm works best on highly networked shooters,
many of whom encounter many others frequently. Examples of datasets that have produced good
results include all of the matches in the Western PA section, area matches and Nationals, and a
combined western PA/eastern PA/Maryland/Northern Virginia/Delaware set.

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
* **Error compensation**: if checked, the algorithm will consider its estimated error when adjusting
  a shooter's rating. Ratings with low error (i.e., high confidence) will be adjusted more slowly.
  Ratings with high error (low confidence) will be adjusted more quickly.
* **Rating engine**: choose from three rating engines. Elo is the default and best option. OpenSkill
  is a Bayesian rating system similar to Microsoft TrueSkill, which unfortunately seems to converge
  too slowly for shooting analysis. Points series provides several ways to run a club or regional
  points series.

##### Elo settings
* **K factor**: the K factor to be used by the Elo algorithm, which controls the volatility of
  ratings, increasing the speed at which they converge to their correct values at the cost of more
  noise in the ratings.
* **Probability base**: the base of the exponent in the Elo probability algorithm. A probability 
  base of 5 means that a shooter whose rating is better than another rating by the scale factor is
  probability-base times more likely to finish ahead in score.
* **Scale factor**: the scale factor used by the Elo algorithm's probability calculator, which
  controls the output range of the ratings. A higher scale factor yields a larger difference in
  rating units for a given difference in skill.
* **Match blend**: in by-stage mode, a factor controlling how much to blend match results into stage
  results. Values greater than zero calculate a shooter's score per stage as:
  ((1 - blend) * stage) + (blend * match).
* **Place/percent weight**: how much the Elo algorithm weights actual vs. expected performances in
  finish order and actual vs. expected performances in stage or match percentage. A mix of both
  parameters seems to yield the best results in empirical testing.
* **Error-aware K**: a modification to the Elo algorithm that adjusts the K factor per shooter when
  a shooter's error is high or low. Shooters with high error get a larger K factor, so that the
  algorithm can find their correct rating more quickly, while shooters with low error get a smaller
  K factor, to reduce the volatility of their ratings.
* **Error-aware K options**: *Lower multiplier* is the multiplier applied to K factor for shooters
  with low error. It interpolates from 1.0, at *min threshold*, to *lower multiplier*, at
  *zero value*. *Upper multiplier* is the multiplier applied to K factor for shooters with high
  error. It interpolates from 1.0, at *upper threshold*, to *upper multiplier* at *scale factor*.

##### Points series settings
* **Model**: how to distribute points. F1-style gives out points to the top 10 finishers according
  to the 2022 Formula 1 rules. Inverse place gives shooters one point for each person they beat.
  Percent finish gives shooters points equal to their finishing percentage. Decaying point gives
  the winner *decay start* points, 2nd place *decay start* × *decay factor* points, 3rd place
  *decay start* × *decay factor* × *decay factor*, and so on.

#### Match selection
During match processing, matches are downloaded to a local cache. If a URL is already present in
the local cache, the match name will be displayed rather than the raw URL.

Matches may be added to projects from the match cache, or by URL.

#### Action bar items
* **Create a new project**: clear all matches, restore settings to default, and reset the project
  name.
* **Clear match cache**: removes all locally-cached matches. If launching the rating configuration
  screen becomes excessively slow, this will speed it up.
* **Export to file**: export the current settings to a file which can be shared between users.
* **Import from file**: import settings from a file.
* **Save/load**: save or load a project from the application's internal storage.
* **Hide shooters**: enter a list of shooters who will be used for ratings, but not displayed. This
  can be used to hide traveling shooters at major matches from local ratings.
* **Fix data entry errors**: provide corrections for incorrectly-entered member numbers.
* **Map member numbers**: define pairs of member numbers that map to the same shooter, in the event
  that automatic member number mapping fails.
* **Number mapping blacklist**: define pairs of member numbers that should not be mapped together,
  in the event that two shooters share the same name and are caught by the member number mapper.
* **Member whitelist**: define member numbers that will be included in the ratings even if their
  shooters fail validation in some way. (Most commonly, this happens when a shooter who enters a 
  match twice enters a name ending in '2', or analogous cases.)

### Ratings Screen
Ratings are displayed in descending order of Elo. The tabs at the top of the screen select
the division or division group of interest. _Ratings, trends, variances, and connectivities are
not comparable across division groups._

The dropdown below the tabs displaying a match name will be enabled if you have 'keep full history'
enabled in settings, and allows you to select a match after which you wish to view ratings.

The search box searches by member name (case-insensitive). The minimum stages/matches box allows you
to filter out competitors whose ratings are based on fewer than the given number of events. The
maximum age box allows you to filter out competitors who have not been seen for more than the given
number of days.

Clicking a shooter name will display a chart of their rating change over time, along with a list of
all the events on which their rating is based.

The action button in the top right corner will export the currently-selected division group's
ratings to CSV, for analysis in other tools.

#### Metrics
Error is the average error in the algorithm's prediction of a shooter's performances over the past
45 events, normalized to account for the number of competitors in each rating event and scaled to
very roughly the same scale as ratings. For Elo and/or statistics nerds, the formula is as follows,
where Es is expected score, Ea is actual score, N is number of participants, and S is the scale
parameter to the Elo algorithm. 

```(mean squared error of ((E_a - E_s) * N)) * S```

The initial error for all shooters is S / 2.

High error indicates that the algorithm has recently missed predictions of the shooter's stage
performances by larger amounts. Low error indicates that the algorithm's recent predictions for the
shooter have been accurate.

Trend is the sum of a shooter's rating changes over the past 30 rating events.

Connectivity is a measure of how much the shooter competes against other people in the dataset.
Competitors with low connectivity relative to others in their division or division group have not
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
When the engine encounters a shooter for the first time, he receives an initial rating: 800 for D,
900 for C or U, 1000 for B, 1100 for A, 1200 for M, and 1300 for GM. Classification has no direct
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

The engine also applies a 'pubstomp multiplier' to high-level shooters shooting exclusively against
low-level competition. If a shooter is classified at least M, is shooting against shooters no closer
than two classifications down, wins a rating event by at least 20%, and has a rating at least 200
greater than the second-place finisher, K is reduced by 75% for the winner only.

#### Connectivity
The engine also calculates a connectivity multiplier for each match. In an ideal world, every
competitor would shoot against everyone else the same number of times. (An ideal world for
determining ratings, at least.) In the real world, shooters compete at varying times and in
varying places; some shooters travel widely in a region, and some stick to a few matches.

A shooter's connectivity is 1% of the sum of the connectivities of the 40 best-connected shooters
he has competed against in the last 60 days, updated when he shoots a match. (That is, connections
will not expire unless a shooter is competing actively.) The purpose of connectivity is to measure
the degree to which a shooter's current rating derives from the ratings of a broad range of other
shooters in the dataset, even if he doesn't shoot against them directly. Highly connected shooters
are rating carriers: their ratings account for performance against many other shooters, so matches
that include them yield more reliable results.

The rating engine determines the expected connectivity of a match by taking the average
connectivity of all shooters at a match, and comparing it to the median of the connectivities of
all known shooters who have completed more than 30 stages or 5 matches. Matches more connected than
the median receive a K multiplier of up to 120%. Matches less connected than the median receive a
multiplier of down to 80%.

#### Error compensation
If error compensation is enabled, the algorithm applies a modifier to K based on the shooter's
rating error. Using the default settings, if the error in a shooter's rating is greater than 40,
K is increased by up to 300% at an error of 400. If the error in a shooter's rating is less than
10, K is decreased by up to 20% at an error of 0.

#### Match-specific processing
In match mode, the engine removes anyone with a DQ on record, or anyone who did not finish
one or more stages. (The engine assumes a stage was a DNF if it has zero time and zero scoring
events—i.e., hits, scored misses, penalties, or NPMs.)

Additionally, a shooter's match score is ignored if his time on any non-fixed-time stage is less
than tenth of a second, on the theory that this is always a data entry error.

#### Stage-specific processing
In stage mode, the engine ignores DNFed stages, but _includes_ stages a disqualified shooter
completed before disqualifying.

Observation suggests that stages that many shooters zero do not provide much usable information
about the relative performances between shooters. As such, by-stage mode also examines the scores
for each stage, and applies a negative modifier to K if more than 10% of shooters zeroed it, from
100% K at 10% to 34% K at 30%.

A shooter's stage score will not be counted if the time is less than a tenth of a second on a
non-fixed-time course of fire, as this typically indicates a data entry error.

Finally, by-stage mode applies a modifier of between -20% and 10% of K, based on the maximum
points of the stage. An 8-round stage multiplies K by 80%, a 24-round stage applies no modifier,
and a 32-round stage multiplies K by 110%. Stages shorter than 8 rounds or longer than 32 are
treated as 8 or 32, respectively.

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

#### Percent vs. placement
In its current form, it isn't unusual to see the engine say that a shooter's expected position is,
for instance, 3rd, but his expected percentage is over 100%. This is an artifact of the different
score distribution functions used for percentage and placement.

For placement, actual score (in the Elo sense) is distributed in a linearly descending manner: last
place gets zero points, and the remaining points are divided up so that the intervals between actual
scores for the remaining places are constant, according to the formula below, where _n_ is the
number of shooters.
                            (n)(n-1)
actualScore = (n - place) * --------
                               2

For percentage, each competitor receives points proportional to their finish. See below, where
matchPoints is the score a shooter earned on a stage, and totalMatchPoints is the sum of all scores
on the stage.

actualScore = matchPoints / totalMatchPoints

Consider a brief example of three shooters, with match points on a given rating event of 100, 95,
and 60. They receive 0.666..., 0.333..., and 0 actual score from placement, and .392, .372, and
.235 actual score from percentage. If each component is weighted equally, their combined actual
scores are 0.529, 0.353, and 0.118. Without percentage mixed in, the shooter in last place will
always lose rating points, whether he finishes with 60 points, 20 points, or 94 points. With
percentage, a shooter who competes primarily against higher-rated shooters still has a way to make
positive adjustments to his rating, without having to beat them heads-up or seek out similarly-
skilled competition elsewhere.

It also provides a brake on the ratings of good shooters who mostly shoot against weak competition.
Due to the manner in which the engine calculates win probability, a shooter will always gain points
for placing first in a rating event; probability of win approaches 100% as the rating gap increases
but never quite gets there. Expected percentage, on the other hand, can (and does) rise above what
a shooter is able to obtain.

### Predictions
Only the Elo rating engine supports predictions at present.

The engine generates predictions using a Monte Carlo simulation. Following the Elo assumption that
player performances follow a Gumbel distribution, the engine generates 1000 'true ratings' for each
player, using the engine rating as mu and a scaled, reduced dynamic range rating error as beta.
These parameters were hand-tuned.

Each player's win probability is calculated for each possible true rating, and these probabilities
become the prediction. Predictions are converted to percentages by assuming that the predicted
winner's 5th octile probability is 100%, and that zero win probability corresponds to a 25% finish.
Again, these parameters were hand-tuned.