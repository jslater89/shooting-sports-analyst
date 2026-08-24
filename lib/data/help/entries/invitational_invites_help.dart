/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/help_topic.dart";

const invitationalInvitesHelpId = "invitational-invites";
const invitationalInvitesHelpLink = "?invitational-invites";

final helpInvitationalInvites = HelpTopic(
  id: invitationalInvitesHelpId,
  name: "Invitational invites",
  content: _content,
);

const _content =
"""# Invitational Invites

This screen builds an invitational invite list from a rating project: finish-order slots from
selected matches, then remaining slots filled by rating. Rating fills ignore competitors who have
never received a calculated rating update (`hasNonzeroRatingChanges` is false)—classification
seeds and shooters with only DQ/DNF no-op events.

Configs are stored separately from rating projects. You can reuse a config with a different project.
If groups or match source IDs are missing from the current project, you will see a warning,
but generation is still allowed. Unresolved groups and IDs are skipped.

TOML import and export allow using projects across multiple instances of Analyst.

## Take Rate

**Take rate** is the expected fraction of invitees who will accept. If a group has 20 slots and take rate is 0.6,
the engine generates invitations for `20 / 0.6`, rounded, then marks the top 20 as main slots and the rest as fallback,
so that a match can be filled even if some invitees decline.

The same over-invite applies to reserved lady, junior, and senior pools: the engine invites `reserved / takeRate`
people in that category. The reserved seat count stays the main-set floor; the extra names are fallback so registration
staff have a same-category list to walk if invitees decline.

## Reserved Lady Slots

When enabled, finish-order processing runs a second pass over lady-only scores. Remaining reserved lady slots are filled
from lady ratings. Reserved lady invites that would otherwise fall below the main-slot cutoff are kept as non-fallback
slots. Extra take-rate lady invites are fallback unless they independently make the general cutoff.

## Reserved Junior And Senior Slots

Junior and senior reserved slots work the same way as lady slots, using the sport's age categories. A category is **junior**
if its oldest competitors are 21 or under. A category is **senior** if its youngest competitors are 50 or over.

USPSA Junior, Senior, Super Senior, and Distinguished Senior all match these rules, as do the equivalent ICORE and
IPSC categories.

These options are hidden for sports that have no matching age categories.

## Multiple Division Rating Qualification

If a competitor is already invited by any means, and would qualify for another division by rating, enabling this setting
records the rating-qualified division on that competitor's invitation record. (Match finish invitations are always recorded.)

## Combined Scoring For Multi-Division Groups

If enabled, invitations for multi-division groups will use combined scoring, not per-division scoring.

## Finish-Order Rules

Each rule awards slots from matches that match its identification:

- An optional **Name** is a short label for crowded configs; it does not affect generation.
- **Scope** controls which invite-engine pass the rule runs on:
  - **General**: overall (unfiltered) division scores only. Category competitors can still qualify
    here if they place high enough overall.
  - **Lady** / **Junior** / **Senior**: the matching reserved-category pass only (requires that
    reserved slot option to be enabled).
  - **Categories**: every enabled reserved pass (lady / junior / senior), but not the overall pass.
  - **All**: the overall pass and every enabled reserved pass (legacy default when scope is omitted
    from a TOML config).
- The **Matches** section picks specific matches from the current project.
- **Include name patterns** are regular expressions; if any are set, all of them must match the match name.
- **Exclude name patterns** reject a match if any of them match.
- If both source IDs and include patterns are set, a match must satisfy both.

Rule types:

- **Top N**: the first N finishers
- **Above N%**: anyone above that match percentage
- *Either*: either top N or above N% qualifies
- *Both*: only top N as well as above N% qualifies

Typical pattern for separate category awards: one **general** top-3 rule plus a **lady** top-1 rule
(and similar junior/senior rules as needed), instead of a single **all**-scoped top-3 rule.

Higher **priority** values run first. Within a priority, matches are processed newest first. **Minimum competitors**
skips small fields.

New rules created in the UI default to **general** scope. Imported configs without a scope field keep
**all** so existing behavior is unchanged.

## Excluded Groups

An excluded-group rule skips listed rating groups at matches identified the same way as finish-order rules
(source IDs and/or name patterns), which can be used to e.g. prevent a bumped-to-Open winner from securing
an invite in Open from a match that doesn't recognize Open. A match on any name pattern will also exclude a
match.

## Results

The Results tab can filter the list with Fallback, Lady, Junior, Senior, and Reserved dropdowns.
Each is Any, Yes, or No, and they combine. Fallback Yes plus Lady Yes shows lady fallbacks for registration staff
to walk. Lady Yes plus Junior No hides junior ladies who only qualified on the junior list. The refresh icon clears
all filters back to Any. CSV export is unfiltered.

Invitation detail shows how each qualification was earned. Match qualifications include a **Pass**
column (General, Lady, Junior, Senior, or Age for combined junior/senior). Rating qualifications
show the same category labels for the rating-fill path that produced them. Reserved-floor and
reserved take-rate overflow rating fills both record their category; the final overall rating fill
is General.
""";
