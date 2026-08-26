# Single-Match Fantasy

Implementation notes for event-scoped fantasy leagues: a small unique draft of competitors at one match, scored by match percent or by the existing fantasy-points calculator.

Season-long fantasy remains the original design (`schema.md`, `League`/`LeagueSeason`/`LeagueMonth`). Single-match is a second `LeagueFormat` on the same collections, not a parallel schema and not a degenerate calendar month.

Related code:

- Schema: `lib/data/database/schema/fantasy/`
- Manager / processor: this directory
- Player lookup: `lib/data/database/extensions/fantasy.dart`
- Scoring: `lib/data/sport/scoring/fantasy_scoring_calculator.dart`
- Match pool: `MatchPrep` / `FutureMatch` / `MatchRegistration`
- Closest existing “game on a major” UX: prediction games (`PredictionGame.matchPreps`)

## Why this first

Season-long processing is unfinished (`FantasyManager.createSeason` / `createSchedule` throw; `FantasyProcessor.processMonth` stops after discovering matches). The scoring calculator, `FantasyPlayer`, and `PlayerMatchPerformance` already work per match.

A major is a bounded, high-interest event with a registration list we already maintain. Building draft + roster + live scoreboard against that event proves infrastructure season-long will need (especially drafting) without finishing monthly H2H, best-of-month, or all-time aggregation.

## Current season coupling (do not reuse as-is)

`League` is March–October (`startMonth` / `endMonth`). `LeagueMonth` derives `startDate`/`endDate` from a calendar month, accumulates `matchPointers`, and scores **best of month** via `PlayerMonthlyPerformance`. `MonthlyRoster` copies pending assignments at month start. `SlotScore` is keyed on `(playerId, monthId)`. `LeagueScoringSettings` only describes H2H vs all-play **league** points, not how a shooter is scored.

A Nationals weekend can be jammed into one season / one month / one pointer, but every API will keep saying “month,” and live scoring during the match is not “scan the rating project for new matches this month.”

Do not special-case `LeagueMonth` so the season processor “just works.” The processor is not done, and the input path is match-prep + live/completed results.

## Format

Add `LeagueFormat` (name flexible) on `League`:

- `season` — existing calendar product
- `singleEvent` — one match, one roster, one standings table

Single-event leagues:

- Link to one `MatchPrep` (player pool, dates, eventual `DbShootingMatch`) **in addition to** `ratingProject` (ratings / `FantasyPlayer` identity).
- Have one scoring period with stored start/end (match weekend), not calendar-month math.
- Score `PlayerMatchPerformance` directly. Skip `PlayerMonthlyPerformance` when the period has one match.
- Rank teams all-play by roster total. Skip H2H, season standings, and all-time standings for this format unless a series (below) asks for them later.
- Lock rosters at match start, or at first posted stage if we want last-second scratches.

Reuse as-is: `FantasyUser`, `Team`, `FantasyPlayer`, `PlayerMatchPerformance`, slot types / `RosterAssignment`, calculator / `DbFantasyStats`, all-play ranking of roster sums.

New: draft + picks, player scoring mode (`percent` vs fantasy points), `MatchPrep` link, event standing type (or a format-aware standing that is not month/season/all-time).

## Player identity

`FantasyPlayer` identity stays **per rating group** (sport + group UUID + member number + project). People almost always appear in one group at a match. Drafting the same competitor in a second group is an acceptable high-risk play (“maybe they change at registration”). Do not collapse group out of the ID.

## Player pool

Default pool: `MatchRegistration`s on the linked `MatchPrep` / `FutureMatch`, resolved to ratings via existing registration mapping, then `FantasyPlayer.fromRating` / `getPlayerFor`.

Registrations are incomplete. Allow `FantasyPlayer`s (or ratings) that **do not** appear in the registration list, as an explicit override/confirm step at draft time or in a commissioner tool. Treat that as “this person might still show up,” not as automatic inclusion of the whole rating project.

Late adds: if the draft has not started, they join the pool. After the draft, waiver / free-agent rules can wait; an override pick during the draft is enough for v1.

Filter the board the way prediction games filter wager eligibility if useful (group size, recency, history). Seed snake order by rating.

## Ownership

**Single ownership per league:** a given `FantasyPlayer` (group-scoped) may be on at most one team in that league. This is the draft worth proving; season-long preseason drafts will share it.

DFS-style shared ownership is out of scope. Uniqueness is per `FantasyPlayer` id, so the same person in two groups is two assets.

## Draft

Nothing in the current schema is a draft. This is the main new infrastructure.

Suggested shape (names flexible):

- `Draft` — league, type (snake/linear; auction later), status, current pick, optional clock
- `DraftPick` — draft, team, player, slot, pick number, timestamp

On complete, write `RosterAssignment`s. After that, single-match and season-long differ only in how long the roster lives.

v1: unique snake, small roster (~4–6), real slot types even if most slots are “any division” plus one constrained slot (ladies, a specific group, etc.). `FantasyRosterSlotProvider` / `FantasyRosterSlotType` exist but have no sport implementations yet — single-match is a reason to add them.

## Scoring

Extend `LeagueScoringSettings` with a **player** scoring mode. Today that object only knows league points from all-play rank and H2H.

- **Fantasy points** — default for “draft anyone at the match.” Use `FantasyScoringCalculator` and existing category weights. Cross-division percent is a bad game unless slots force comparable fields.
- **Match percent** — `DbFantasyStats.finishPercentage` (already computed). Decide division percent vs overall up front; division percent is the right default if the league is group-scoped. A percent-only league can keep the same calculator and zero the other categories, or a thin path that only reads finish percentage.

DNS / DNF / DQ: drafted competitor who does not post a usable score is zero (or a league setting later). Do not silently substitute another entry.

Live updates: recompute from the live or completed match as stages post. That is a different loop from `FantasyProcessor`’s monthly `matchPointers` scan. Event leagues should score from the linked `DbShootingMatch`, not from walking the rating project by date.

## Series (later)

Grouping `singleEvent` leagues into a series (Area championships, a Nationals + satellite, a club’s major weekend) is optional and not required for v1.

If added, keep each event as its own league (own draft, own roster, own scoreboard). A series is a thin parent: shared teams/users if desired, plus aggregated standings. Do not turn a series into a `LeagueSeason` of calendar months. Reuse all-play / season-standing *ideas* only after event leagues work.

## Proof-out path

1. `LeagueFormat.singleEvent` on `League`, link to one `MatchPrep`.
2. Small all-play league, unique snake draft, ~4–6 slots.
3. Pool from registrations; commissioner/draft override for ratings not on the list.
4. Score from the live/completed match through the existing calculator; leaderboard is sum of slot scores.
5. Add percent as a scoring-mode flag once the board and lock work.

That proves identity, roster constraints, draft UX, lock, registration overrides, and the live scoring loop. Season-long then becomes N scoring periods plus monthly aggregation, using the same draft and the same `PlayerMatchPerformance` rows.

## Schema edit reminders

Any new `@collection` or persistent field must follow the Isar contract: register in `analyst_database.dart`, add a migration, keep links/backlinks aligned, update `lib/data/database/extensions/fantasy.dart` if queries change. Do not edit `*.g.dart`.

`FantasyManager.createLeague` currently persists only the `League` row and drops the season/months it constructs. Single-event creation should persist the format, `MatchPrep` link, scoring mode, slots, and (when ready) an empty draft in one transaction.
