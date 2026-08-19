/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/latent_log_configuration_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const latentLogHelpId = "latentLog";
const latentLogHelpLink = "?latentLog";
final helpLatentLog = HelpTopic(
  id: latentLogHelpId,
  name: "Latent log ratio rating system",
  content: _content,
);

const _content =
"""# Latent Log Ratio Rating System

The latent log ratio (LLR) rating system models each competitor's underlying performance as a
**latent log-ratio**: the natural log of their finish percentage relative to the field. Ratings
update through a Kalman-style filter that balances new match evidence against prior uncertainty.
The headline rating you see in the ratings list is an affine map of that internal state into
display points.

For help configuring Shooting Sports Analyst's LLR implementation, see the [Latent log ratio
configuration guide]($latentLogConfigHelpLink).

## Core Concepts

Each competitor carries four primary quantities:

* Rating - the system's best estimate of underlying performance in log space. Higher ratings
  indicate stronger competitors.
* Uncertainty (variance) - how confident the system is about the rating. High uncertainty means
  larger rating changes, but less influence on opponents.
* Dispersion - how much a competitor's performance tends to swing from event to event, beyond
  what the sport itself explains. Think of this as per-competitor consistency.
* Momentum - a signed trend term that tracks sustained improvement or decline. When momentum is
  active, the system temporarily widens the prior before updating, so ratings can follow a run
  of form without treating each match in isolation.

Unlike Elo and Glicko, LLR works directly in percentage space. A competitor who finishes at 90% of the
winner contributes ln(0.90) as score evidence. That makes the model a natural fit for practical
shooting sports, where match and stage scores are already expressed as percentages.

## How Updates Work

At each rating event, the system:

1. Converts finish percentages to log scores.
2. Estimates a field baseline—how hard the match was relative to expectations—using a
   precision-weighted average of rating residuals. Think of this as the rating that corresponds
   to the score the winner shot.
3. Blends in pairwise residuals from nearby opponents (by finish and by rating) to recover
   head-to-head information that a global baseline can miss. In particular, this helps validate
   that the global baseline is valid at all parts of the field, and provides some damping in the
   event that it isn't.
4. Computes an innovation (observed performance minus aged rating) and applies a Kalman gain
   to move the rating.
5. Adapts variance, dispersion, and momentum based on how surprising the result was.

Several layers of observation noise sit on top of the core Kalman update. These do not change
the raw log scores. They downweight evidence the system considers unreliable: deep-tail
finishes, tiny bottom-heavy fields, immature cohorts, and the like.

## Display Mapping

Internal ratings live in log units centered on a configurable starting value. Display ratings
are:

`display = internal × scale factor + scale offset`

The default settings of 100/100 yield a scale that runs from about 0 to 150 on USPSA data.

Variance and dispersion on rating rows use linear scaling: multiply internal variance by the
square of the scale factor, or take the square root and multiply by the scale factor for
standard-deviation display.

## Shooting Sports Adaptations

### Initial Ratings by Classification
Where a sport defines classification-based priors, new competitors start at a classification
mean in log space rather than the global center. USPSA uses empirically derived offsets for
each class, with tighter priors for higher classifications. When only generic rating
multipliers are available, the system applies a softened log-space shift (one third of the
full classification gap) rather than a hard jump.

### Pairwise Residuals
LLR is fundamentally a whole-field model, but practical shooting also has meaningful
head-to-head structure: losing to someone you were expected to beat, or beating someone you
were expected to lose to, carries information a field baseline alone may underweight. The
pairwise blend parameter controls how much local opponent comparisons contribute to the
observed performance.

### Robustness and Field Pathology
Shooting sports produce plenty of pathological fields: two-person locals, squads where half
the field shoots far below the winner, equipment failures masquerading as skill changes. LLR
includes several safeguards:

* Student-t downweighting of outlier innovations, with asymmetric cutoffs. Positive surprises
  are considered more trustworthy than negative ones: positive surprises generally mean skill
  gain, while negative surprises are more often gear issues.
* Huber-style baseline robustness to prevent small numbers of wild results from anchoring the
  field.
* Tail noise inflation for very poor finishes, which are observed to be noisy.
* Weak-field damping for small, bottom-heavy fields (the equivalent to Elo's pubstomp multiplier).
* Novelty variance for fields whose competitors' ratings have collectively not yet converged.

### Mean Reversion (Rust)
Competitors who stop shooting for extended periods see their committed rating drift back
toward the central rating, after a configurable grace period. This is separate from
variance growth from skill drift: rust moves the rating itself, while skill drift widens
uncertainty over time.

### Predictions
LLR supports percentage predictions. The system estimates each competitor's expected finish
ratio against a mixture of presumed winners, accounting for rating uncertainty, behavioral
dispersion, and sport noise. Prediction bands use a separate (typically smaller) sport-variance
parameter, because common-mode match difficulty cancels out in relative predictions.

## Rating Mode

By default, each match is one rating update; stages are counted for experience but not rated
separately. By-stage mode is available but will produce much more volatile ratings, similar to
the situation with Glicko-2.

## Tips

Uncertainty on the ratings list is the committed standard deviation, not the time-aged value.
Hover the uncertainty column to see the current (time-aged) figure.

Rating differences are in log space under the hood. On the default scale, a display difference
of roughly 10 points corresponds to about a 10% performance ratio, but the mapping is
logarithmic, not linear: a 10-point gap between two ratings means about 10% performance difference,
but a 20-point gap means about 18%.

The algorithm performs best when analyzing groups of competitors who frequently compete against
each other. Isolated groups may have ratings that are less reliable.

LLR defaults lean toward sharp predictions over perfectly calibrated uncertainty bands. That
tradeoff reflects one of the main uses of the system — driving the Prediction Game — but you
can tune toward softer bands through the prediction parameters if calibration matters more for
your project.""";
