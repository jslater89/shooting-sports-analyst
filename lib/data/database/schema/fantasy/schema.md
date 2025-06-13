# Fantasy League Schema Documentation

## Overview
The fantasy league system is designed to manage competitive fantasy leagues for shooting sports. It supports both head-to-head and all-play formats, with configurable seasons, rosters, and scoring systems.

## Core Entities

### League
The top-level entity representing a fantasy league.

- **Properties**:
  - `id`: Auto-incrementing unique identifier
  - `sportName`: Name of the sport
  - `startMonth`: Month when the season begins (default: March)
  - `endMonth`: Month when the season ends (default: October)
  - `headToHeadPerMonth`: Number of head-to-head matchups per month
  - `creationDate`: When the league was created
  - `state`: Current league state (offseason, preseason, active, finished)

- **Relations**:
  - `rosterSlots`: Available roster positions
  - `teams`: Teams in the league
  - `currentSeason`: Active season
  - `seasons`: All seasons in league history
  - `allTimeStandings`: Cumulative standings for all teams

### LeagueSeason
Represents a single season within a league.

- **Properties**:
  - `id`: Auto-incrementing unique identifier
  - `name`: Season name
  - `startDate`: Season start date
  - `endDate`: Season end date

- **Relations**:
  - `league`: Parent league
  - `standings`: Season standings
  - `months`: Months in the season

### LeagueMonth
Represents a calendar month within a season.

- **Properties**:
  - `id`: Auto-incrementing unique identifier
  - `month`: Calendar month (UTC)
  - `started`: Whether month processing has begun
  - `completed`: Whether month processing is complete

- **Relations**:
  - `season`: Parent season
  - `nextMonth`: Next month in sequence
  - `previousMonth`: Previous month in sequence
  - `matchups`: Head-to-head matchups
  - `allPlayRosters`: All-play format rosters
  - `allRosters`: All rosters for the month
  - `standings`: Monthly standings

### Team
Represents a fantasy team.

- **Properties**:
  - `id`: Auto-incrementing unique identifier
  - `name`: Team name

- **Relations**:
  - `league`: Parent league
  - `players`: Team's fantasy players
  - `rosterAssignments`: Pending roster assignments

### FantasyPlayer
Represents a player in the fantasy league system.

- **Properties**:
  - `id`: Auto-incrementing unique identifier

- **Relations**:
  - `rating`: Link to the player's shooter rating
  - `teams`: Teams the player is on
  - `leagues`: Leagues the player participates in

- **Methods**:
  - `getRating()`: Retrieves the player's shooter rating
  - `getProject()`: Gets the rating project hosting the player's rating
  - `getMatches(LeagueMonth)`: Gets all matches for the player in a given month

### PlayerMonthlyPerformance
Tracks a player's performance in a specific month.

- **Properties**:
  - `id`: Composite ID based on player and month
  - `playerId`: ID of the player
  - `monthId`: ID of the month
  - `matchPerformances`: List of match performances
  - `bestPerformance`: Best performance for scoring

- **Relations**:
  - `player`: Link to the fantasy player
  - `month`: Link to the league month
  - `usedInRosters`: Rosters using this player

### LeagueStanding
Tracks team standings at different levels (monthly, seasonal, all-time).

- **Properties**:
  - `id`: Composite ID based on team, league, and optional season/month
  - `teamId`: ID of the team
  - `leagueId`: ID of the league
  - `seasonId`: Optional ID of the season
  - `monthId`: Optional ID of the month
  - `finalized`: Whether standings are final
  - `type`: Type of standing (month, season, all-time)
  - Various scoring and performance metrics:
    - `leaguePointsFor`: Total league points
    - `allPlayLeaguePoints`: Points from all-play format
    - `headToHeadLeaguePoints`: Points from head-to-head format
    - `fantasyPointsFor`: Total fantasy points scored
    - Win/loss/tie counts for both formats

- **Relations**:
  - `team`: Link to the team
  - `league`: Link to the league
  - `season`: Optional link to the season
  - `month`: Optional link to the month
  - Various matchup links for tracking wins/losses/ties

### Matchup
Represents a head-to-head matchup between two teams in a specific month.

- **Properties**:
  - `id`: Auto-incrementing unique identifier
  - `homeWins`: Whether the home team won (null if not completed)
  - `marginOfVictory`: Point difference between teams
  - `completed`: Whether the matchup has been resolved

- **Relations**:
  - `month`: The league month this matchup belongs to
  - `homeRoster`: The home team's roster for this matchup
  - `awayRoster`: The away team's roster for this matchup

### SlotScore
Tracks the performance of a specific roster slot in a matchup.

- **Properties**:
  - `slotIndex`: The position in the roster
  - `playerId`: ID of the player in this slot
  - `monthId`: ID of the league month

## Processing Flow

1. **League Processing**:
   - The `FantasyProcessor` handles league processing
   - Processing is idempotent - successful operations won't duplicate work
   - Leagues can be in different states: offseason, preseason, active, or finished

2. **Season Management**:
   - Seasons have defined start and end dates
   - Each season contains multiple months
   - Months are processed sequentially

3. **Monthly Processing**:
   - Months track both head-to-head and all-play formats
   - Processing status is tracked via `started` and `completed` flags
   - Standings are updated as matches are processed

4. **Player Performance**:
   - Player performances are tracked monthly
   - Best performances are used for scoring
   - Matches are linked to player ratings

5. **Standings Calculation**:
   - Standings are maintained at multiple levels (month, season, all-time)
   - Both all-play and head-to-head results are tracked
   - Points are calculated based on league scoring rules

## Data Flow

### Match Score Processing Flow

1. **Match Entry**
   - A match is added to the rating project
   - The match contains scores for shooters in various divisions
   - Each score includes raw performance data (hits, time, etc.)

2. **Player Performance Tracking**
   - The `FantasyProcessor` identifies matches within a league month's date range
   - For each match:
     - Player performances are calculated using `FantasyScoringCalculator`
     - Scores are stored in `PlayerMonthlyPerformance.matchPerformances`
     - The best performance is identified and stored in `bestPerformance`

3. **Roster Processing**
   - Each team's roster for the month is processed
   - For each player on the roster:
     - Their best performance for the month is retrieved
     - If no performance exists, they score zero points
     - Scores are aggregated to create team totals
   - For head-to-head matchups:
     - `SlotScore` objects are created for each roster position
     - Scores are tracked per slot for matchup resolution

4. **Standings Updates**
   - **All-Play Format**:
     - All team scores are compared
     - Teams are ranked based on total points
     - `allPlayRank` is assigned
     - Win/loss/tie counts are updated
     - `allPlayLeaguePoints` are awarded based on rank

   - **Head-to-Head Format**:
     - Teams are matched according to league rules
     - Matchups are processed:
       - Home and away rosters are compared
       - `homeWins` is set based on total scores
       - `marginOfVictory` is calculated
       - `completed` status is updated
     - Win/loss/tie records are updated
     - `headToHeadLeaguePoints` are awarded based on results

5. **Standings Aggregation**
   - Monthly standings are updated with:
     - Total fantasy points
     - All-play and head-to-head records
     - League points from both formats
   - Season standings are updated by aggregating monthly results
   - All-time standings are updated with the new results

### Example Flow

1. A match is added to the rating project on March 15th
2. The `FantasyProcessor` runs and:
   - Identifies the match falls within March's date range
   - Calculates fantasy scores for each shooter
   - Updates `PlayerMonthlyPerformance` records
3. Team rosters are processed:
   - Team A has Player X who shot the match
   - Player X's score is added to Team A's total
   - For head-to-head matchups:
     - `SlotScore` objects track each player's performance
     - Matchup results are determined by comparing totals
4. Standings are updated:
   - Team A's total is compared to other teams for all-play
   - Team A's total is compared to their head-to-head opponent
   - Monthly standings are updated
   - Season standings are updated
   - All-time standings are updated

### Key Points

- Processing is idempotent: running the processor multiple times won't duplicate scores
- Scores are always processed in the context of a specific month
- Best performances are used for scoring, not all performances
- Standings are maintained at multiple levels (month, season, all-time)
- The system supports both all-play and head-to-head formats simultaneously
- Head-to-head matchups track both overall results and per-slot performance
- Matchup completion status is tracked separately from the month's completion status

## Notes

- The system uses Isar for persistence
- All dates are stored in UTC
- Roster assignments are maintained separately from active rosters
- The schema supports both head-to-head and all-play scoring formats
- League state transitions are managed through the `FantasyProcessor`
- Player performances are tracked at the match level with detailed scoring
- Standings use composite IDs to ensure uniqueness across different time periods
