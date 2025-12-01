/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/glicko2_configuration_help.dart";
import "package:shooting_sports_analyst/data/help/entries/openskill_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const glicko2HelpId = "glicko2";
const glicko2HelpLink = "?glicko2";
final helpGlicko2 = HelpTopic(
  id: glicko2HelpId,
  name: "Glicko2 rating system",
  content: _content,
);

const _content = """# Glicko2 Rating System

The Glicko-2 rating system is an evolution of the earlier Glicko rating system, both of which
were developed to improve on Elo in its original chess application. Glicko-2 has a few features
which make it attractive for application to the shooting sports.

## General Description
Glicko-2 replaces Elo's single parameter (rating) with three:

* Rating, the top-line number that we think of as a competitor's actual strength.
* Rating deviation or RD, a measure of the system's uncertainty about a competitor's
  rating.
* Volatility, a measure of how much a competitor's rating has fluctuated in the past.

Rating deviation influences the rate of rating change on both sides: if you have a high rating
deviation, your rating will change faster to reflect the uncertainty in the measurement; if
your opponent has a high rating deviation, your rating will change more slowly, because his
rating has less informational content. Rating deviation goes down when you attend matches
(as you build up recent information about your rating) and up over time, by an amount
determined by volatility and the length of the rating period.

Volatility changes based on the likelihood of results: the more unlikely, the higher volatility
goes. In the ratings list, volatility is reported as the amount by which a very low RD
(25 in the default scaling) will increase per rating period.

Since Glicko-2 is a head-to-head rating system, a 'game' for the purposes of the Shooting
Sports Analyst implementation is a comparison between two competitors at the same match.
Although Glicko rating systems have periodic rating updates as a central tenet, the
Shooting Sports Analyst implementation works like Elo in that ratings update whenever a match
is added. The system records each competitor's last activity and calculates the correct
'current' rating deviation on demand based on a match's timestamp. Since Glicko-2 expects
multiple 'games' per rating period, the combination of head-to-head comparisons between
competitors, real-time calculation of current rating deviation, and ratings commits after
each match meets the requirements of the algorithm.

Some additional information can be found in the [configuration help]($glicko2ConfigHelpLink),
in particular on aspects of the algorithm upon which the settings bear.

## Pros and Cons
Unlike [OpenSkill]($openskillHelpLink), which shares some of its features (specifically a
built-in uncertainty measure), Glicko-2 is actually quite promising as a practical shooting
rating system.

First off, it is solidly grounded in theory. While Shooting Sports Analyst Elo has many of
the same features (our Elo error is a combination of uncertainty and volatility), Glicko-2
has mathematical rigor for these features, whereas they are more heuristically derived in Elo.

Second, it appears to be highly responsive without being noisy.
It moves quickly when performances differ, and stays stable when performances are similar.
Relatedly, this means it is robust for small sample sizes—two matches is often enough to
get a rating that remains stable over time.

Third, it is fast (with a caveat). Calculations are consistently 5-10x faster than Elo.

On the opposite site of the ledger, it is fast because it only operates in by-match mode.
Because the core conceit of the rating system is that some moderate number of head-to-head
comparisons occur for each competitor per rating commit, the use of stage-by-stage results
can overwhelm the algorithm and produce highly unstable ratings.

Also, the algorithm is much more complicated than Elo, to the point that I would have
a hard time explaining exactly how it works. This is not necessarily a problem, but it does
mean that modifications to more directly support the shooting sports (as Analyst has for
Elo) are more difficult to reason about.""";