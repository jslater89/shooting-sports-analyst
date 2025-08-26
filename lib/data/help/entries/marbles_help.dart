/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/help/entries/marbles_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/help_topic.dart';

const marblesHelpId = "marbles_help";
const marblesHelpLink = "?$marblesHelpId";

final helpMarbles = HelpTopic(
  id: marblesHelpId,
  name: "Marble game",
  content: _content,
);

const _content =
"""# Marble Game

The marble game is a rating algorithm originally designed by Twitter user
[@iowahawkblog](https://x.com/iowahawkblog/status/931947718628593664) to rank college
football teams, as an alternative to polls. It turns out that, with a few small tweaks
to fit multiplayer games, it works surprisingly well for shooting sports.

## The Original Marble Game

As applied to college football, and leaving aside some of the football-specific
details, the marble game goes like this:

* You start with 100 marbles.
* If you beat another team at home, take 20% of their marbles.
* If you beat another team on the road, take 25% of their marbles.

## The Shooting Sports Marble Game

Shooting Sports Analyst's implementation is an adaptation that attempts to hew as
closely as possible to the original. It goes like this:

* You start with 200 marbles.
* Whenever you enter a match, you stake 20% of your marbles. All stakes from all
  competitors go into the match pot.
    * If you have 5 or fewer marbles, your stake is 0.
* According to some function of your finish percentage or place, you receive marbles
  from the match pot.

Combining ideas from football and piracy, all of the currently-available functions for
marble distribution operate on the idea of shares: competitors finishing in higher positions
or percentages receive more shares than competitors finishing lower in the order. The match
pot is then divided by the total number of shares to determine the number of marbles each share
is worth, and competitors receive shares based on their finish percentage or place. (Shares are
often decimal numbers.)

You can read about the marble distribution functions and their configuration parameters in
the [marble configuration help]($marblesConfigHelpLink).
""";
