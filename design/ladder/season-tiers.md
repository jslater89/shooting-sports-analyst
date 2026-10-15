# Season Tiers

Rating tiers for the website, scored on the L2s Main LLR rating project. The customer is someone hungry who shoots a couple of majors a year. Every match in that project is a major, so local-match noise is out of scope.

This is the system we settled on after the 2023–2026 research pass. The research command is `dart run bin/db_oneoffs.dart TIER` in `bin/db_oneoff_impl/season_tier_command.dart`. The product sidecar described at the end is not built yet.

Counts are division rating rows, not unique people. A shooter with an Open row and a Carry Optics row can hold a tier in each. Only single-division rating groups are in scope.

## Ladder

The website ladder is the wide one. Rank I is the first, lower step. Rank II is the next step up.

| Tier | Percentile floor |
| --- | ---: |
| Diamond | 97 |
| Ruby | 95 |
| Emerald | 92.5 |
| Sapphire | 90 |
| Gold II | 85 |
| Gold I | 80 |
| Silver II | 75 |
| Silver I | 70 |
| Bronze II | 65 |
| Bronze I | 60 |

A shooter holds the highest floor they have cleared. The displayed rating is the project's usual scale (`formatNumericRating`, about 100 + 100 times the internal rating).

Thin divisions drop tiers. The tiers that remain keep their percentiles and their names. Nothing is renamed or slid down to fill a gap.

The field size is the prior year's cutoff population (defined below).

| Prior-year cutoff field | Tiers awarded |
| --- | --- |
| 300 or more | Full ladder |
| 150 to 299 | Ruby 95, Sapphire 90, Gold I 80, Silver I 70, Bronze I 60 |
| 40 to 149 | Sapphire 90, Gold I 80, Silver I 70, Bronze I 60 |
| Under 40 | No percentile tiers |

On a collapsed ladder the 10-point metal is rank I (Gold I is 80, not a separate "Gold"). Rank II is not awarded. Challenger still applies when the percentile ladder is empty.

On the October 2026 research run, Open, PCC, Limited Optics, and Carry Optics were on the full ladder for 2026. Limited, Production, and Single Stack were on the Ruby ladder. Revolver was on the Sapphire ladder. Limited 10 was under 40 and had no percentile tiers. Those assignments will move as fields change. Hysteresis around 40, 150, and 300 was discussed and not adopted. Revisit it if a division flickers across a boundary from one season to the next.

An older seven-step ladder (Bronze 60, Silver 70, Gold 75, Sapphire 80, Emerald 85, Ruby 90, Diamond 95) remains available in the research command with Wide Tiers off. It ignores field size. It is not the website ladder.

## Who sets a bar, and who can earn a tier

Cutoffs for season Y come from the cutoff field at the end of year Y−1. A rating row is in that field when both of these are true through Dec 31 of Y−1:

- At least 3 distinct career matches.
- At least 1 match in Y−1.

A rating row can earn a tier in season Y when both of these are true:

- At least 2 distinct career matches through Dec 31 of Y.
- At least 1 match in Y.

Career matches are distinct match ids, walked in year order. The rating used for a year is `newRating` on the last event dated in that year. Anyone with a match in the year has not rusted by Dec 31 relative to that match, so the cutoff is the last-event rating, not an aged-to-Dec-31 rating.

The percentile is linear interpolation at position `(n − 1) * p` (the same type-7 convention as NumPy and R). A row clears a floor only when its rating is strictly above the cutoff. Equal to the cutoff is not enough.

The bars for a season are frozen from the prior year. Scoring more matches during 2026 does not move the 2026 cutoffs. A "next year pending" figure is a separate preview: the percentiles of the current year's cutoff field if the season ended today. That preview moves as majors are added. It is not the bar anyone is being scored against.

We looked at blending the last two years of cutoffs and left the one-year bar in place. A blend would lag a real strengthening of a division, and it would prop up a top line that had fallen because the cutoff field got deeper rather than because the scale moved. The 2026 research pass showed the drop concentrated in the right tail: Bronze floors did not fall with Diamond, which is a poor fit for a global scale change. The Diamond pool did not inflate uniformly either. Revisit a blend only if a later season shows the top cutoff and the Diamond count moving together, or a division yo-yos across the 300-shooter ladder boundary.

## Shield

Shield is the hold rule.

Each tier is independent. The rating entering the season is the `oldRating` on the shooter's first event of the year, which already includes grace. If that rating is above a floor, the floor starts the year confirmed.

After that, only match-end ratings count. Stages inside one match collapse to the rating after the match's last stage, ordered by that stage's `dateAndStageNumber`.

- A match-end rating above a floor promotes to that floor immediately.
- Two match-end ratings in a row at or below a floor drop that floor.
- The displayed tier is the highest floor still held.

One match under a held floor does not drop it. That is the grace a two-major season needs: a single off weekend does not take the rank back.

With two or more majors this season, the hold on every floor is fixed by the last two match-end ratings:

- Last match above the line: holding.
- Last match at or below, the one before it above: still holding.
- Both at or below: not holding.

A shooter with one major this season is the exception. Above the line promotes. At or below, the floor survives only when the entering rating was already above it. Zero majors this season earns no tier.

We also scored a Series rule: two consecutive majors over a line to promote, and two under to drop. With exactly two majors the two rules demote the same people. They differ on promotion. Series confirms only when both majors are over the line, so a breakthrough on the last major of the season stays unconfirmed until next year. That is the wrong delay for this customer. Series is not the website rule.

## Challenger

Challenger is a finish, not a rating percentile. It does not take a shooter out of a rating tier.

It is a division finish of at least 95 percent at USPSA Nationals or US IPSC Nationals. The score is `precalculatedScore.percentage` on the 0–100 scale. The hold runs from that match through December 31 of the next calendar year.

USPSA Nationals is a match whose name contains "national", excluding names that contain "ipsc" or "shooting international". Open is stricter: the name also has to contain one of "open", "hi-cap", "hicap", "racegun", or "race gun", so a bump to Open at another division's nationals does not count.

US IPSC Nationals is an IPSC match whose name matches `U.S. IPSC` plus either `Nationals` or `National Championship`. Those matches count for every group. The entry still has to map into the group. The IPSC-to-USPSA sport link is the map: Open to Open, Standard to Limited, Production Optics to Carry Optics, Optics to Limited Optics, Classic to Single Stack, PCC Optics to PCC, Production to Production, Revolver to Revolver. PCC Irons is not in that link. The Open name-marker filter does not apply to US IPSC, so an Open finish there does count.

## Sidecar

The website copy should be a sidecar on the rating project, not a replay of the research scan. A full historical pass spends almost all of its time reading rating events (about 15 seconds for 2023–2026 on a desktop). The percentile math after that is a sort per division per year.

Write the sidecar during the walk `RatingProjectLoader` already does.

- A full calculation drops the sidecar and rewrites it as events are processed. Historical `oldRating` and `newRating` change on a full recalculation, so a cache from before that pass is wrong.
- While a year is open, keep each rating row's year-end rating, career match count, and Shield hold. An append updates the rows for competitors in the new match, in the same pass that writes their rating events.
- When a match lands in a year whose bars are not written yet, freeze the previous year from the stored year-end ratings and career counts. That is a query of sidecar rows, not another event walk.
- Appending a major does not change bars that are already frozen. Rebuilding every percentile because one match was added is the full scan again, and the live rank does not need it.

Rows worth storing:

- Per division per closed year: the ladder that field size selected, and one cutoff rating per tier.
- Per rating row per year: year-end rating, career match count, and the Shield hold bits.
- Challenger: the nationals match, the division, the percentage, and the expiry date.

With the hold bits stored, a page view reads one row. The two-match lookback is how a missing row gets rebuilt, and it is enough because Shield only remembers the previous match. The career count and the Challenger flag are not in those two matches, so they stay stored.

An append-time deduplication that merges two rating rows has to rebuild the surviving row. A normal append does not.

The live rank reads the frozen bars and the current hold. The pending-next-year preview is optional. It is the only field-wide number that changes on every append, and only for the people who shot.

## Public profiles

Public profile pages are a website feature. They are keyed by member number and rating project. The page can show wins, match count, current rating, and badge history. Badge history is the sidecar: which tiers the rating rows held, and when.

The identity search that fills the page belongs in this repo. A profile starts from one person, found by member number or by a name search the user selects. From that seed, gather every rating row in the project, in any group, that shares one of the seed's `allPossibleMemberNumbers`. A shared name does not merge anyone. The name search only chooses the seed.

That set is the person across divisions. Open and Carry Optics stay separate rows, with their own ratings and badges, and they appear together because their possible member numbers intersect.
