/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/rating_event_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const openskillHelpId = "openskill";
const openskillHelpLink = "?openskill";
final helpOpenSkill = HelpTopic(
  id: openskillHelpId,
  name: "OpenSkill rating system",
  content: _content,
);

const _content = """# OpenSkill Rating System

OpenSkill is a modern, Bayesian rating system based on Microsoft's TrueSkill™, designed for multiplayer competitions.
Unlike Elo, which tracks a single rating number, OpenSkill maintains two values for each competitor: Mu (μ), which
represents the estimated skill level, and Sigma (σ), which represents the uncertainty in that estimate.

## How It Works

OpenSkill assumes that a competitor's performances follow a normal distribution. After each [rating
event]($ratingEventHelpLink), Mu moves up or down based on performance while Sigma decreases as more data is gathered.
The displayed rating is calculated as μ - 3σ, which provides a conservative estimate that will gradually increase as
uncertainty decreases. This means new shooters start with high uncertainty (high σ) and their ratings become more stable
over time as σ decreases.

Shooting Sports Analyst's implementation of OpenSkill uses the Plackett-Luce model to calculate rating changes. Other
models may be implemented in the future, but OpenSkill development is largely paused on the basis of a lack of promise in
initial tests with OpenSkill generally.

## Disadvantages

In testing, the OpenSkill system is very slow to converge, on the scale of competition shooting: whereas 100 matches
might be a reasonable number of events to expect in an online game, essentially nobody in the shooting sports has a
career of 100 or more major matches in a single sport. There are likely knobs to tweak how quickly OpenSkill reacts, but
locating them has not been a priority given that Elo converges relatively quickly.

## Advantages

OpenSkill does, however, have a few advantages. It is slightly faster to calculate than Elo, it is more mathematically
rigorous than the Shooting Sports Analyst flavor of Elo, and it has a built-in error mechanism. It may be further
improved in the future.

## Initial Ratings

OpenSkill does not currently use classification to seed initial ratings. Instead, all competitors start with the same
uncertainty level (σ = 25/3) and the same mu (25.0).

## Settings

The OpenSkill settings are as follows:

### Beta
The beta parameter controls the natural variability of ratings. When a competitor's sigma drops below beta, beta will be
used instead. The default value is half of sigma: 4.167.

### Tau
The tau parameter is a small amount to add to sigma at every rating event, which allows fluidity in ratings as player
skill changes. The default value is 1/30 of beta: 0.139.""";
