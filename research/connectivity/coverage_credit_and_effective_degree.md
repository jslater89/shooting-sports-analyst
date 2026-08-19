# Coverage Credit And Effective Degree

## Objective

Connectivity is intended to measure attachment to the global rating network, not merely activity or
the number of competitors at recent matches.

That distinction matters. A competitor can accumulate a large amount of internally useful evidence
by repeatedly competing in one isolated population while providing little information about how
that population aligns with the rest of the rating network. Conversely, a traveler can carry rating
scale between populations even without attending the largest matches.

The two measures in this document address different parts of that problem:

- **Effective degree** measures the breadth and concentration of a competitor's direct, recent
  opponent relationships.
- **Coverage credit** measures how much external network reach a competitor contributes in the
  context of a particular match.

Neither is a complete global centrality algorithm. They are deliberately local, causal, and
economical enough to update while processing matches chronologically.

## Notation And Temporal Rules

Let `F` be the set of competitors at the match currently being rated.

For each competitor `i`, let `N_i` be the set of opponents in that competitor's recent match
window. A five-match window is the current default.

All connectivity used to rate a match should be calculated from information available **before**
the current match. The current field must not be inserted into `N_i` until after the match's rating
changes have been calculated.

This keeps connectivity causal and matches its intended use as an input to the Elo update.

## Effective Degree

### Definition

For one competitor, count how many times each distinct opponent appears in the recent match
window:

```text
c_v = number of encounters with opponent v
```

Then define:

```text
T = sum_v(c_v)
```

`T` is total opponent encounters, including repeats.

Define each opponent's share of those encounters:

```text
p_v = c_v / T
```

The effective degree is:

```text
D_eff = 1 / sum_v(p_v^2)
```

Equivalently:

```text
D_eff = T^2 / sum_v(c_v^2)
```

This is the inverse Simpson concentration, also called the Hill number of order 2. It answers:

> How many equally frequent opponents would produce the observed concentration of encounters?

### Interpretation

Effective degree is bounded by:

```text
1 <= D_eff <= U
```

where `U` is the number of distinct opponents.

- `D_eff = U` when every opponent appears equally often.
- `D_eff` approaches 1 when almost all encounters are concentrated on one opponent.
- Repeated encounters with a small core reduce `D_eff`.
- New, non-overlapping fields increase `D_eff`.

Unlike a raw unique count, effective degree distinguishes encounter distributions with the same
`U` and `T`.

### Example: Repeated Club Versus Disjoint Fields

Suppose both competitors have 200 opponent encounters in five matches.

Competitor A sees the same 40 people five times:

```text
T = 200
sum(c_v^2) = 40 * 5^2 = 1000
D_eff = 200^2 / 1000 = 40
```

Competitor B sees five disjoint fields of 40:

```text
T = 200
sum(c_v^2) = 200 * 1^2 = 200
D_eff = 200^2 / 200 = 200
```

In this clean example, a unique-opponent count already distinguishes the competitors. Effective
degree becomes more useful in mixed cases.

### Example: A Repeated Core Plus One-Off Opponents

Suppose a competitor sees 20 core opponents five times each and 100 other opponents once:

```text
T = 20 * 5 + 100 = 200
U = 120
sum(c_v^2) = 20 * 25 + 100 = 600
D_eff = 200^2 / 600 = 66.67
```

The raw unique count says 120. Effective degree says the encounter distribution behaves more like
67 equally represented opponents because a substantial fraction of the evidence is concentrated
on the 20-person core.

### Combining Effective Degree With Encounter Volume

Effective degree measures breadth, not total evidence. A competitor with one 20-person match should
not necessarily equal a competitor with sustained broad participation.

A direct replacement for the current square-root product is:

```text
breadthScore = sqrt(T * D_eff)
```

The current score is:

```text
currentScore = sqrt(T * U)
```

Replacing `U` with `D_eff` preserves the geometric-mean interpretation while penalizing
concentrated encounter histories.

A more general family is:

```text
breadthScore = D_eff^alpha * T^(1 - alpha)
```

where:

- `alpha = 0.5` gives equal geometric weight to breadth and volume.
- `alpha > 0.5` favors novel or broadly distributed opponents.
- `alpha < 0.5` favors total evidence.

The exponent should be selected against an empirical target rather than by aesthetics.

### Optional Field-Size Damping

An `n`-person match contributes `n - 1` encounters to every participant. This is reasonable if a
large field genuinely supplies proportionally more rating information, but it makes field size a
dominant predictor.

To give large matches sublinear weight, assign every opponent in a match of size `n` the edge
weight:

```text
edgeWeight = g(n - 1) / (n - 1)
```

Possible choices include:

```text
g(x) = sqrt(x)
g(x) = log(1 + x)
```

Then `c_v` becomes a sum of fractional edge weights rather than an integer count. The effective
degree formula remains unchanged.

This is a policy choice. Damping should only be introduced if real-data validation shows that field
size overwhelms the desired global-attachment signal.

### What Effective Degree Does Not Measure

Effective degree remains a one-hop measure.

It cannot distinguish:

- 100 opponents who all belong to one isolated population, and
- 100 opponents distributed across several globally connected populations.

It improves the direct-breadth term, but it does not identify bridges by itself.

## Coverage Credit

### Match-Level External Reach

For the current field `F`, define each participant's external recent neighborhood:

```text
E_i = N_i \ F
```

`E_i` contains people whom competitor `i` encountered recently but who are not in the current
field.

The field's external coverage is:

```text
C_F = |union_i(E_i)|
```

This measures how many distinct external competitors the current field reaches through its
participants' recent histories.

External coverage is a direct two-hop quantity:

```text
current field -> recent participant -> external opponent
```

It is more graph-specific than recent field-size variance or skewness.

### The Credit Allocation Problem

Raw external coverage describes the match, but it does not identify the rating carriers.

Giving every participant the same `C_F` bonus is incorrect:

- A local competitor with no external relationships receives the same bonus as the traveler who
  imported them.
- A participant's stored score becomes dominated by the type of match attended most recently.
- The same reach is repeatedly credited to everyone in the field.

Coverage credit allocates the field's external reach to the participants who brought it.

### Definition

For every external competitor `v`, count how many current-field participants reach that person:

```text
m_v = number of E_i sets containing v
```

Then competitor `i` receives:

```text
Q_i = sum over v in E_i of 1 / m_v
```

An external person reached by:

- one field participant contributes `1` to that participant;
- two field participants contributes `0.5` to each;
- ten field participants contributes `0.1` to each.

The credits exactly partition external coverage:

```text
sum_i(Q_i) = C_F
```

No external person is double-counted across the field.

### Why This Is A Shapley Value

Consider a cooperative game in which each field participant contributes the set `E_i`, and the
value of any coalition is the number of distinct external people it covers:

```text
value(S) = |union over i in S of E_i|
```

For one external person `v`, all participants who reach `v` are interchangeable contributors. In a
random ordering of the participants, each has probability `1 / m_v` of being the first contributor
who covers `v`.

Therefore that person's unit value is divided equally among the `m_v` contributors. Summing over
external people gives `Q_i`.

Coverage credit is consequently the exact Shapley value of this set-coverage game, without the
usual exponential cost of calculating general Shapley values.

### Example: One Traveler In A Local Field

Suppose three local competitors all reach the same four external people:

```text
E_L1 = {a, b, c, d}
E_L2 = {a, b, c, d}
E_L3 = {a, b, c, d}
```

A traveler reaches three additional people:

```text
E_T = {x, y, z}
```

The external coverage is:

```text
C_F = 7
```

Each shared local connection has multiplicity 3, so:

```text
Q_L1 = Q_L2 = Q_L3 = 4 / 3
Q_T = 3
```

The credits sum to:

```text
4/3 + 4/3 + 4/3 + 3 = 7 = C_F
```

The traveler receives full credit for the three external people only they imported. The locals
share credit for their redundant reach.

### Example: Two Travelers With The Same Network

If two travelers both reach `{x, y, z}`, each external person has multiplicity 2:

```text
Q_T1 = Q_T2 = 3 / 2
```

Together they still receive total credit 3. Adding a redundant carrier does not falsely double the
field's external reach.

If the travelers reach disjoint sets of three, each receives 3 and total external coverage
increases by 6.

### Match Attachment And Shooter Attachment

Coverage produces two related but distinct outputs:

```text
C_F = match-level external reach
Q_i = participant i's contribution to that reach
```

For the Elo connectivity multiplier, `C_F` can be used directly as a pre-match attachment feature.

For a persistent shooter connectivity score, store `Q_i` for each recent match and aggregate the
last several values, for example with recency weights. This prevents the score from being only a
property of the most recently attended field.

One possible decomposition is:

```text
directBreadth_i = sqrt(T_i * D_eff_i)
carrierContribution_i = recency-weighted mean of recent Q_i
```

These should initially remain separate diagnostic columns. Combining them too early makes it
difficult to determine which signal is useful.

### Normalizing Match Coverage

Raw `C_F` generally increases with:

- field size;
- participants' prior activity;
- the size of the rating population;
- the length of the recent-match window.

That is not automatically a defect. A large match containing many independently connected
competitors really is attached to more of the graph.

However, raw coverage cannot distinguish absolute reach from unexpectedly broad reach for a field
of its size. Useful companion quantities are:

```text
D_F = sum_i(|E_i|)
coverageEfficiency = C_F / D_F
```

`D_F` is external edge mass with duplicates. `coverageEfficiency` is high when participants bring
non-overlapping external networks and low when everyone reaches the same outsiders.

Neither quantity should replace `C_F` alone:

- `C_F` rewards substantial absolute attachment.
- `C_F / D_F` rewards nonredundancy but strongly favors small fields or a lone traveler.

Another option is an online expected-coverage model:

```text
expectedLogCoverage =
    E[log(1 + C_F) | field size, total external degree]

coverageResidual =
    log(1 + C_F) - expectedLogCoverage
```

This asks whether a match reaches more of the graph than expected given its size and participants'
prior degrees. Expected coverage could be maintained using coarse field-size and degree buckets
rather than a fitted model.

A practical match score could retain both absolute and residual information:

```text
matchAttachment =
    beta * standardizedLogCoverage
    + (1 - beta) * standardizedCoverageResidual
```

The correct `beta` depends on whether larger, broadly attended matches should inherently receive
stronger Elo updates.

### Effective Number Of Carriers

Coverage can also reveal whether attachment depends on one person or is distributed across the
field.

Normalize participant credits:

```text
r_i = Q_i / C_F
```

Then calculate:

```text
effectiveCarrierCount = 1 / sum_i(r_i^2)
```

This is another inverse concentration:

- approximately 1 when one traveler supplies nearly all external reach;
- larger when several participants independently connect the field outward.

This should be diagnostic initially. A match connected by one genuine carrier is still connected;
whether distributed attachment deserves additional weight is a rating-policy decision.

### Weighted Coverage

Unweighted coverage treats every external competitor equally. It therefore distinguishes graph
reach, but not the quality of the network reached.

A weighted form assigns an external value `w_v`:

```text
weightedCoverage = sum over covered v of w_v

weightedQ_i = sum over v in E_i of w_v / m_v
```

Possible weights include a compressed version of the external competitor's effective degree:

```text
w_v = log(1 + D_eff_v)
```

This introduces practical and conceptual costs:

- It requires access to data for competitors outside the current match.
- It can become recursively self-reinforcing.
- High-degree members of one isolated clique may still look globally valuable.
- Snapshotting weights at encounter time makes the result historical but less current.

The unweighted version should be validated first.

## Relationship Between The Measures

Effective degree and coverage credit answer different questions:

```text
Effective degree:
How broad and non-concentrated are this shooter's direct recent encounters?

Coverage credit:
How much distinct external reach does this shooter contribute to this field?
```

A competitor can have:

- high effective degree and low coverage credit by repeatedly attending large matches within one
  already shared circuit;
- modest effective degree and high coverage credit by being the only traveler linking two
  populations;
- high values for both by competing broadly and repeatedly carrying independent network reach;
- low values for both by repeatedly attending one stable local club.

This two-axis description is more informative than immediately collapsing everything into one
number.

## Economical Calculation

### Effective Degree

For each shooter:

1. Iterate over opponent IDs in the recent match windows.
2. Build `Map<opponentId, encounterWeight>`.
3. Accumulate `T` and `sum(c_v^2)`.
4. Calculate `D_eff`.

Complexity is:

```text
Time:   O(total opponent entries in the shooter's window)
Memory: O(distinct opponents in the shooter's window)
```

### Coverage Credit

For one current match:

1. Build the current-field ID set `F`.
2. For each participant, build or retrieve the unique recent neighborhood `N_i`.
3. Remove current-field IDs to obtain `E_i`.
4. First pass: increment `m_v` for every `v` in every `E_i`.
5. Second pass: calculate each `Q_i` by summing `1 / m_v`.
6. The number of keys in the multiplicity map is `C_F`.

Complexity is:

```text
Time:   O(sum_i |N_i|)
Memory: O(C_F + sum_i |E_i|) if all E_i are retained
```

The retained-set memory can be avoided by traversing each already stored `N_i` again during the
second pass.

This is the same broad complexity class as the two-hop union already exercised by
`connectivity_simulation.dart`. The existing simulation's result—approximately 12.5 seconds
extrapolated to 200,000 entries while calculating several candidates—is encouraging, although it is
not a production end-to-end benchmark.

## Integration Constraints

### Calculate Match Attachment Before Updating Windows

The production sequence should be:

1. Load current competitors and their previous connectivity windows.
2. Calculate pre-match `C_F`, `Q_i`, and any match connectivity.
3. Rate the match using the pre-match connectivity multiplier.
4. Add the current field to each participant's windows.
5. Update persistent shooter breadth and recent carrier-credit history.

Calculating match connectivity after step 4 leaks the current match into the feature used to weight
that same match.

### Avoid Per-Shooter Reconstruction Of Shared Data

The following data is common to the entire match and should be built once:

- current-field ID set;
- each participant's external neighborhood;
- external multiplicity map;
- field coverage and normalization statistics.

The current calculator interface updates one rating at a time. A production coverage implementation
would benefit from a per-match context object or a prepare/finalize phase rather than reconstructing
the same maps for every participant.

### Recency And Inactivity

A five-match window means connectivity only expires when a shooter competes again. This is the
current behavior, but it is not equivalent to time decay.

If global attachment should fade during inactivity, apply an age multiplier when the score is read:

```text
agedScore = storedScore * decay(days since last match)
```

This avoids mutating every inactive rating while keeping stale carriers from permanently affecting
the baseline.

### Rollback

Effective degree can be reconstructed exactly from surviving opponent windows.

Historical coverage credit is contextual: `Q_i` depends on everyone else who attended that match
and their pre-match windows. Exact rollback therefore requires either:

- retaining the historical credit with the match window; or
- replaying connectivity from an earlier checkpoint.

Storing the historical scalar is sufficient if rollback only needs to restore the score that was
known at that point. It is not sufficient to recalculate a counterfactual history in which earlier
matches were absent.

## Research Plan

### Synthetic Micrographs

Before using a large stochastic simulation, verify exact behavior on small deterministic cases:

1. One repeated clique.
2. Five disjoint fields of equal size.
3. Two cliques joined by one traveler.
4. Two cliques joined by several redundant travelers.
5. One large isolated component and one smaller globally bridged component.
6. Equal field sizes and activity counts with only mixing behavior changed.

These tests should have obvious expected ordering and expose normalization artifacts.

### Improved Stochastic Simulation

The stochastic simulation should:

- calculate match scores before inserting the current match;
- use the exact intended production match aggregator;
- keep truly local competitors out of most national matches;
- keep the isolated population isolated except for explicitly controlled bridges;
- analyze currently living and stale competitors separately;
- use tie-aware Spearman ranks;
- run several random seeds;
- compare populations matched on field size and activity.

### Real-Data Validation

Synthetic labels can reject obviously unsuitable measures, but they cannot identify the best
modifier. The target should reflect global rating alignment.

Useful tests include:

#### Withheld Bridge Matches

Remove selected cross-region matches, rerun ratings, and measure regional rating offsets. A useful
connectivity score should identify the matches and competitors whose removal causes the largest
global misalignment.

#### Future Cross-Population Residuals

Calculate connectivity using only past data, then evaluate competitors when they next attend a
different regional population. Higher connectivity should predict smaller systematic rating
residuals after controlling for rating uncertainty and activity.

#### Bootstrap Stability

Resample or omit matches and rerun ratings. Connectivity should predict the stability of global
rating level, not merely the number of observations.

#### Elo Ablation

Compare:

- no connectivity multiplier;
- current square-root connectivity;
- effective-degree breadth;
- coverage-based match attachment;
- a combined model.

Evaluate future prediction error and calibration, not only whether known majors receive larger
multipliers.

## Initial Recommendation

Treat the first implementation as two diagnostic signals:

```text
Shooter breadth:
sqrt(T * D_eff)

Pre-match field attachment:
C_F = |union_i(N_i \ F)|

Shooter carrier contribution:
Q_i = sum over v in (N_i \ F) of 1 / m_v
```

Do not initially weight coverage by recursive connectivity, and do not assign the same two-hop
multiplier to every field participant.

After validating the independent signals, decide whether:

- Elo should use direct pre-match field coverage;
- persistent shooter connectivity should blend breadth with recent coverage credit;
- field-size or expected-coverage normalization is necessary;
- distributed carrier support should matter beyond absolute external reach.

The central advantage of this approach is that every quantity has a concrete graph interpretation:
direct breadth, distinct external reach, and a nonredundant allocation of that reach to the people
who supplied it.

## Simulation Results: Seed 42, August 18, 2026

### Test Configuration

The revised simulation used:

```text
Matches:                1,800
Match entries:          169,706
Living competitors:     4,390
Retired competitors:    1,467 (excluded from final shooter analysis)
Recent window:          5 matches
Ordinary regions:       7
Clubs per region:       5
Isolated population:    region 0, with 280 initial isolated-high competitors
Random seed:            42
```

The generator produced four match types:

```text
Club:             1,107 matches, mean field 53
Isolated mega:      177 matches, mean field 188
Area:               382 matches, mean field 125
National:           134 matches, mean field 229
```

The isolated population attended only isolated-mega matches. Travelers attended all eight
non-isolated population labels represented by the generator and shot nationals heavily. Ordinary
local competitors mixed club, area, and occasional national participation.

The revised simulation also corrected several validity problems from the first experiment:

- Match connectivity is calculated before inserting the current match into participant windows.
- The production carrier match score uses its arithmetic-mean aggregator.
- The square-root and research scores use sorted median/maximum aggregation.
- Retired competitors are separated from living competitors.
- Tied Spearman ranks receive their average rank.
- Match generation cannot overfill the requested field size.
- Regional clubs repeatedly draw from smaller club populations.
- The isolated population no longer receives travelers or national competitors.
- Deterministic self-tests verify Effective Degree examples and Coverage Credit conservation.

### Runtime

The complete in-memory calculation included:

- current square-root connectivity;
- production Rating Carrier connectivity;
- Effective Degree;
- two-pass Coverage Credit;
- all associated match diagnostics.

The measured time was:

```text
169,706 entries:       16.56 seconds
Per entry:             97.60 microseconds
Projected 200,000:     19.52 seconds
```

This is within the desired 30-second mathematical budget. It is not an end-to-end production
benchmark: database work and rating calculations are excluded. Conversely, a production
implementation would not need every research candidate and every diagnostic.

Coverage Credit currently allocates several temporary sets and maps per match. Reusing buffers and
precomputing recent neighborhoods once per participant should provide additional margin.

### Generator Sanity

The living competitor archetypes had the following activity:

```text
Local high:
  23.9 lifetime matches on average
  Recent windows: 43% club, 44% area, 13% national

Local low:
  20.0 lifetime matches on average
  Recent windows: 55% club, 36% area, 8% national

Traveler:
  95.3 lifetime matches on average
  Recent windows: 9% club, 22% area, 69% national

Isolated high:
  115.1 lifetime matches on average
  Recent windows: 100% isolated mega
```

Traveler and isolated-high activity and field sizes are reasonably comparable. The local
populations remain less active, so direct comparisons involving locals still contain an activity
confound.

### Effective Degree Results

The archetype means were:

```text
               U       T     D_eff   D_eff/U   sqrt score   effective score
Local high    481     591     416.9     0.858       532.5             495.0
Local low     392     496     336.2     0.847       439.3             405.9
Traveler      702   1,050     561.5     0.802       856.4             764.2
Isolated      271     959     252.1     0.929       509.9             491.5
```

The Effective Degree score and current square-root score had a shooter rank correlation of:

```text
Spearman(sqrt, effective) = 0.997
```

Effective Degree therefore adds little rank information in this particular simulation.

This is not an implementation failure. The result clarifies what Effective Degree measures:
encounter concentration, not global attachment.

The isolated population has the highest `D_eff / U` ratio. Its competitors repeatedly sample a
large fraction of the same 280-person population, so encounter counts are distributed fairly evenly
across nearly every available opponent. That history is isolated but not especially concentrated
within its component.

Travelers have the lowest `D_eff / U` ratio. They see many people, but repeated national attendance
creates a core of recurring opponents mixed with a long tail of less frequent opponents. Effective
Degree correctly identifies that concentration and penalizes travelers more than isolated-high
competitors:

```text
Traveler effective / traveler sqrt:       0.892
Isolated effective / isolated sqrt:       0.964
```

Consequently, replacing `U` with `D_eff` actually reduces the traveler-versus-isolated contrast:

```text
Traveler / isolated, sqrt:       1.68
Traveler / isolated, effective:  1.55
```

The conclusion is:

> Effective Degree is a defensible refinement of direct breadth, but it is not a substitute for a
> global-attachment measure.

It may still be useful when real histories contain a repeated club core plus irregular travel. Its
incremental value should be measured on real data because the stochastic generator produces mostly
large, relatively even opponent sets.

### Rating Carrier Results

The production Rating Carrier score remained primarily a field-size measure:

```text
Shooter score correlation with mean field size:  0.926
Shooter score correlation with Coverage Credit: -0.018
```

At the match level:

```text
Isolated mega carrier score: 472.7
National carrier score:      449.2
National / isolated:          0.95
```

The isolated population is deliberately disconnected, but the field-size-moment score rates its
matches slightly above nationals. This is direct evidence that match-size variance and skewness do
not recover global graph attachment.

The carrier score may still describe participation in varied field sizes, but its bridge
interpretation is unsupported.

### Direct Coverage Results

Pre-match external coverage was:

```text
Club:             2,263
Isolated mega:       90
Area:              3,255
National:          3,888
```

The national-versus-isolated contrast was:

```text
National / isolated external coverage: 42.98
```

Coverage's rank correlation with field size was:

```text
Spearman(coverage, field size) = 0.353
```

That is materially lower than the field-size dependence of the aggregate-statistics carrier score.
Coverage also produces a sensible ordering in this generated world:

```text
National > Area > Club >>> Isolated mega
```

The club result is informative. A 53-person club reaches 2,263 external competitors on average
because a small number of travelers and area-connected locals import substantial outside history.
The club is small but not isolated. That is precisely the distinction a graph-attachment feature
should be capable of making.

### Coverage Efficiency Results

Coverage efficiency was:

```text
Club:             0.155
Area:             0.079
National:         0.039
Isolated mega:    0.006
```

Its field-size correlation was:

```text
Spearman(coverage efficiency, field size) = -0.908
```

This strong inverse relationship is expected:

- A small club with one traveler has little duplicated external reach.
- A national contains many competitors who share the same external networks.
- The isolated mega has extensive repetition inside a small closed population.

Coverage efficiency is useful as a redundancy diagnostic, but it should not be used alone as an Elo
match multiplier. Doing so would systematically favor small fields.

### Effective Carrier Count Results

The effective number of carriers was:

```text
Club:               26.0
Area:               75.2
National:          167.1
Isolated mega:     169.5
```

The isolated mega and national have almost identical effective carrier counts despite radically
different external coverage.

This is not contradictory. Effective carrier count measures how evenly the available coverage is
allocated, not how much coverage exists. The isolated field's small amount of external reach is
distributed across most of its participants, producing a large effective count.

Therefore:

> Effective carrier count is only meaningful alongside absolute coverage.

It may distinguish reliance on one bridge from broadly distributed attachment, but it says nothing
about whether the total attachment is substantial.

### Persistent Coverage Credit Results

The recency-weighted five-match Coverage Credit means were:

```text
Local high:       39.7
Local low:        27.4
Traveler:         32.1
Isolated high:     0.5
```

The traveler-versus-isolated contrast was:

```text
Traveler / isolated Coverage Credit: 70.10
```

Coverage Credit was almost orthogonal to the existing volume-oriented measures:

```text
Spearman(credit, sqrt):       0.156
Spearman(credit, carriers):  -0.018
Spearman(credit, effective):  0.147
```

This is encouraging because it indicates that credit supplies a genuinely different signal rather
than rescaling activity or field size.

Coverage Credit by participant and match context explains why travelers do not have the highest
overall mean:

```text
                         Club    Area    National
Local high                54.2    28.2       32.4
Local low                 33.9    19.5       25.2
Traveler                 158.6    45.7       11.8
```

Travelers receive enormous credit when attending a club because they import external opponents no
one else reaches. At nationals, travelers are numerous and have overlapping histories, so they
divide credit among themselves.

This behavior is desirable under the Shapley interpretation. Coverage Credit does not label
someone a permanent carrier merely because the generator calls them a traveler. It measures their
marginal network contribution in the field where they actually appear.

Local-high competitors can also earn substantial credit. A local competitor with recent area or
national history may be the person carrying outside rating information back to a club. That is a
real carrier behavior, not a false positive.

The top 20 persistent credit scores contained:

```text
Travelers:     50%
Local high:    50%
Isolated:       0%
Local low:      0%
```

### Historical Credit As A Match Score

Aggregating participants' pre-match persistent Coverage Credit produced:

```text
Club:             38.9
Area:             48.9
National:         61.3
Isolated mega:     0.6
```

Its field-size correlation was only:

```text
Spearman(match credit, field size) = 0.187
```

This is the cleanest ordering among the tested participant scores:

```text
National > Area > Club >>> Isolated mega
```

However, historical credit and direct coverage answer slightly different questions:

```text
Direct C_F:
How much external reach does this field bring right now?

Aggregated historical Q_i:
How much marginal reach have these participants tended to contribute recently?
```

A traveler who usually attends nationals may have modest historical credit because their network
is redundant there, while being uniquely valuable at today's club. Direct pre-match coverage sees
that current context immediately. Historical credit does not receive the large club contribution
until after the club match.

For Elo, direct pre-match coverage is therefore the more immediate match feature. Historical credit
is useful for persistent shooter display and as a complementary prior.

### The Most Important Limitation

The 42.98 national-versus-isolated coverage ratio is not pure evidence that unweighted two-hop
coverage detects disconnected components.

The isolated population begins with only 280 people, while an isolated match averages 188
participants. Before a match, the maximum available external population is consequently only about
92 people. The observed mean coverage of 90 follows almost directly from that finite pool.

The non-isolated population contains thousands of people, so national participants can cover
thousands of external IDs.

This means the experiment currently combines two effects:

1. global versus isolated mixing;
2. large versus small component population.

If the isolated component contained 4,000 active competitors attending random 188-person matches,
raw external coverage could become very large despite the component remaining completely
disconnected.

More generally, no purely structural centrality measure can distinguish two isomorphic disconnected
components as "global" and "local" without one of:

- a designated anchor population;
- metadata defining the populations;
- an objective that treats larger component size itself as greater global attachment;
- observed bridge paths connecting one component to the designated global network.

Coverage Credit solves redundant allocation of two-hop reach. It does not, by itself, define which
external people belong to the globally relevant component.

### What The Simulation Establishes

The current run supports these claims:

1. Field-size moments are not a reliable proxy for graph attachment.
2. Current square-root connectivity is mostly a breadth-and-volume measure.
3. Effective Degree is a valid concentration correction but remains a one-hop breadth measure.
4. External coverage is computationally affordable and reacts to current match context.
5. Shapley Coverage Credit allocates that reach correctly without double counting.
6. Coverage Credit contains information largely independent of field size and direct breadth.
7. Coverage efficiency and effective carrier count are useful diagnostics but unsuitable standalone
   match scores.

The run does **not** yet establish:

1. that raw coverage remains valid when disconnected components have equal population sizes;
2. that the synthetic ordering predicts real rating stability;
3. that one seed is representative;
4. that the current five-match window is optimal;
5. that raw, residualized, or weighted coverage is the best Elo modifier;
6. that Effective Degree improves predictions enough to justify replacing unique degree.

### Provisional Design Direction

Keep the signals separate during the next research phase:

```text
Direct breadth:
sqrt(T * U)

Concentration-adjusted breadth:
sqrt(T * D_eff)

Current match external reach:
C_F

Current participant contribution:
Q_i

Persistent participant contribution:
recency-weighted recent Q_i
```

For the Elo match multiplier, test direct pre-match `C_F` first. Apply logarithmic compression and
compare it with a baseline appropriate to the rating population:

```text
compressedCoverage = log(1 + C_F)
```

Do not multiply by coverage efficiency. Its severe inverse field-size bias would make small clubs
systematically dominate nationals.

Do not use effective carrier count without absolute coverage. A widely distributed amount of
negligible reach is still negligible.

Do not blend Effective Degree and Coverage Credit until each has demonstrated independent
predictive value.

### Required Next Stress Tests

#### Equal-Size Disconnected Components

Vary isolated population size while holding match size and activity constant:

```text
Isolated population sizes:
280, 500, 1,000, 2,000, 4,000
```

Plot or print raw coverage, efficiency, credit, and participant-score ordering. This directly tests
whether current success is caused by the isolated population cap.

#### Controlled Bridge Sweep

Start with two disconnected populations and vary:

```text
Number of travelers:             0, 1, 5, 20, 100
Traveler cross-population rate:  0%, 10%, 25%, 50%, 100%
```

Coverage should increase when bridge history actually enters a field. Credit should accrue to the
specific bridge participants and divide correctly when their reach becomes redundant.

#### Activity-Matched Archetypes

Give traveler, local, and isolated archetypes identical:

- match counts;
- field-size distributions;
- retirement rates;
- recent-window maturity.

Change only population mixing. This isolates graph attachment from activity and match-size effects.

#### Window-Length Sweep

Test windows of:

```text
3, 5, 8, 12 matches
```

Measure runtime, score stability, bridge detection, and saturation. Larger windows may improve
coverage but cause most active fields to reach nearly the entire population.

#### Multiple Seeds

Run at least 20 seeds and report means plus dispersion for:

- national/isolated coverage ratio;
- traveler/isolated credit ratio;
- field-size correlations;
- method rank correlations;
- projected 200,000-entry runtime.

#### Real-Data Validation

The decisive tests remain withheld bridge matches, future cross-population residuals, bootstrap
rating stability, and Elo prediction/calibration ablations.

### Current Bottom Line

Coverage Credit is the most promising new idea from this experiment because it:

- has a precise graph and cooperative-game interpretation;
- identifies marginal bridge contribution;
- avoids double counting shared external reach;
- is largely independent of existing field-size and breadth scores;
- fits within the computational target.

Direct external coverage is the most promising immediate match-level feature.

Effective Degree is mathematically sound but is currently a secondary refinement. Its near-identity
with square-root connectivity and its weaker traveler/isolated contrast show that encounter
concentration is not the same thing as global network attachment.

The next experiment must equalize disconnected-component population size before raw coverage can be
considered validated as a global-attachment measure.

## Isolated-Component Population Sweep

### Purpose

The first simulation gave nationals 42.98 times as much direct coverage as isolated megas, but the
isolated population contained only 280 people. This follow-up experiment isolates component
population size from field size and competitor activity.

Every tested population is completely disconnected. There are no travelers, cross-population
matches, or bridge paths. If a metric increases across the sweep, that increase cannot represent
improved attachment to another global component.

### Configuration

For each population size:

```text
Field size:                     188
Target matches per competitor:  100
Warmup matches per competitor:   20
Recent connectivity window:       5 matches
Match selection:                  uniform random sample from the component
External connections:             none
```

The tested component populations were:

```text
280, 500, 1,000, 2,000, 4,000
```

The number of matches scales with population so every competitor retains approximately the same
activity. This removes the activity collapse that would occur if a fixed number of match entries
were spread across increasingly large populations.

Run the experiment with:

```text
dart run research/connectivity/connectivity_simulation.dart --isolated-sweep
```

### Results

```text
Population:                    280      500    1,000    2,000    4,000
Matches:                       149      266      532    1,064    2,128
Matches per competitor:      100.0    100.0    100.0    100.0    100.0

External coverage:            92.0    312.0    812.0  1,811.9  3,811.3
Coverage / maximum:          1.000    1.000    1.000    1.000    1.000
Coverage efficiency:        0.005    0.006    0.008    0.014    0.025
Effective carrier count:    188.0    187.9    187.8    187.6    187.4

Historical match credit:      0.5      1.7      4.4      9.9     20.9
Persistent shooter credit:    0.5      1.7      4.3      9.6     20.3

Unique recent opponents:       278      451      645      777      852
Effective degree:            254.8    374.2    535.0    682.5    787.8

Projected 200k runtime:      20.3s    22.7s    30.2s    32.2s    34.5s
```

### Coverage Saturates The Component

For field size `F` and component population `P`, the largest possible external coverage is:

```text
maximum external coverage = P - F
```

Every population reached essentially exactly that maximum:

```text
coverage / (P - F) = 1.000
```

With 188 participants, each carrying five recent fields, the union of their recent neighborhoods
covers virtually every person in a uniformly mixed component. The two-hop coverage calculation has
therefore saturated.

In this regime:

```text
C_F approximately equals component population minus current field size
```

Raw coverage is acting as a local component-size estimator, not a bridge or global-attachment
measure.

At population 4,000, the completely disconnected component produces coverage 3,811—almost the same
as the prior mixed-world national value of 3,888. The earlier national/isolated contrast disappears
once component population is equalized.

This falsifies the strongest interpretation of the first result:

> Unweighted two-hop coverage does not, by itself, distinguish a large disconnected component from
> a globally mixed component.

### Coverage Credit Also Scales With Component Size

Coverage Credit exactly partitions coverage:

```text
sum_i(Q_i) = C_F
```

In the uniformly mixed disconnected fields, coverage is distributed almost perfectly evenly over
all 188 participants. Each participant's expected credit is consequently approximately:

```text
Q_i approximately equals C_F / 188
```

For population 4,000:

```text
3,811 / 188 = 20.27
observed persistent shooter credit = 20.3
```

Thus Coverage Credit behaves correctly mathematically while inheriting the value definition of the
coverage game. If every covered external ID is worth one unit, a larger disconnected component
contains more units to allocate.

The Shapley allocation is not the failed part. The failed assumption is:

```text
value(external competitor) = 1
```

for every external competitor regardless of which component or community that person represents.

Persistent credit in the disconnected 4,000-person component reaches 20.3. For comparison, the
prior mixed simulation produced:

```text
Local low:       27.4
Traveler:        32.1
Local high:      39.7
```

A large disconnected population therefore receives a substantial carrier score despite having no
global bridge at all.

### Effective Carrier Count Is Purely Distributional

Effective carrier count remains approximately 188 at every population size:

```text
188.0, 187.9, 187.8, 187.6, 187.4
```

This is nearly the complete field size. Every participant contributes a similar share of the
component-wide coverage.

The metric is behaving exactly as defined:

```text
effectiveCarrierCount = 1 / sum_i((Q_i / C_F)^2)
```

It reports that coverage is evenly distributed. It cannot report whether the coverage has any
global value.

This confirms the previous conclusion that effective carrier count must never be interpreted
without both absolute and qualitative information about the coverage being distributed.

### Effective Degree Also Grows In A Disconnected Component

Unique recent opponents and Effective Degree both rise as the component supplies more available
opponents:

```text
Population 280:
  U = 278
  D_eff = 254.8

Population 4,000:
  U = 852
  D_eff = 787.8
```

The five-match window bounds direct encounters to at most:

```text
5 * (188 - 1) = 935
```

As component population grows, overlap between recent fields declines and both `U` and `D_eff`
approach that window-imposed ceiling. Effective Degree correctly reports broad, evenly distributed
direct encounters inside the component.

It cannot determine that those encounters are disconnected from the rest of the dataset. This is a
second demonstration that Effective Degree is a local breadth measure rather than global
attachment.

### Coverage Efficiency Does Not Solve The Problem

Coverage efficiency rises from 0.005 to 0.025 as the disconnected component grows. Larger
components produce less overlap among participant neighborhoods, so more of the external edge mass
resolves to distinct people.

The 4,000-person disconnected value approaches the prior national value:

```text
Disconnected population 4,000: 0.025
Prior national:                 0.039
```

Efficiency still distinguishes these particular cases, but not categorically. A still larger or
more sparsely mixed disconnected component could continue closing the gap.

Efficiency describes neighborhood redundancy. It does not establish attachment to a designated
global network.

### Runtime Scaling

Projected 200,000-entry runtime rises with component population:

```text
Population 280:      20.3 seconds
Population 500:      22.7 seconds
Population 1,000:    30.2 seconds
Population 2,000:    32.2 seconds
Population 4,000:    34.5 seconds
```

Coverage complexity is not solely a function of match entries. It also depends on recent
neighborhood size:

```text
O(sum over current participants of recent unique-neighborhood size)
```

The ordinary mixed simulation remained under budget because its average neighborhoods were smaller
and fields included many less-active competitors. Dense mature components cross the 30-second
target with the allocation-heavy research implementation.

This does not rule out exact Coverage Credit, but production work would need optimization:

- calculate each participant's recent neighborhood once per update;
- avoid rebuilding the same sets for score and diagnostic calculations;
- reuse external-ID frequency maps between matches;
- avoid retaining per-participant external sets when a second traversal is possible;
- benchmark a coverage-only implementation without research metrics;
- consider a capped or sketched neighborhood if exact processing remains too expensive.

### Revised Interpretation

The sweep separates two claims that were previously conflated:

1. **Coverage Credit is a correct allocation of a set-coverage value.**
2. **Unweighted external-ID coverage is a valid definition of global attachment.**

The first claim remains true. The second is false in general.

Coverage Credit still has value as a framework:

```text
Q_i = sum over external elements v of value(v) / multiplicity(v)
```

The research problem moves to defining the external elements and their values so that they represent
independent global attachment rather than raw people in the same component.

### A Structural Impossibility

Suppose two disconnected components have identical graph structure and equal population. Without
metadata or an explicitly designated anchor, a graph-only algorithm must assign corresponding nodes
the same score. There is no structural fact making one component "global" and the other "local."

Therefore a global-attachment metric must define at least one of:

- attachment to the largest connected component;
- attachment to a designated anchor set;
- attachment across detected communities;
- attachment to a representative sample of the complete dataset;
- expected stability of ratings under future cross-component encounters.

A finite-hop count of unweighted people cannot supply that definition.

### Coverage Credit Remains Useful For Bridge Identification

The sweep fields distribute credit uniformly:

```text
Q_i / (C_F / |F|) approximately equals 1
```

In the mixed simulation, a traveler at a club received mean credit 158.6 while the field-wide
uniform allocation was approximately:

```text
C_F / |F| = 2,263 / 53 = 42.7
```

That traveler contributed roughly 3.7 times the uniform expectation.

This suggests a revised use for Coverage Credit:

```text
relativeCarrierCredit_i = Q_i / (C_F / |F|)
```

or:

```text
excessCarrierCredit_i = max(0, Q_i - C_F / |F|)
```

In a uniformly mixed component, participants cluster around 1 relative credit or zero excess
credit, regardless of component size. A unique bridge receives substantially more.

This identifies **who is unusually responsible for the field's reach**. It still does not tell
whether the reached population is globally valuable, but it removes raw component size from the
individual carrier label.

Equivalent field-level diagnostics include:

- maximum relative credit;
- mean of the top several relative credits;
- credit concentration;
- effective carrier count relative to field size.

These measure bridge concentration rather than global attachment and should be named accordingly.

### Candidate Next Definitions

#### Anchored Coverage Credit

Assign each external competitor a nonnegative anchor value `a_v`:

```text
anchoredCoverage = sum over covered v of a_v

anchoredQ_i = sum over v in E_i of a_v / m_v
```

The Shapley conservation property remains:

```text
sum_i(anchoredQ_i) = anchoredCoverage
```

The hard question is defining `a_v` without unstable circular reinforcement. Possibilities include:

- membership in or reachability to a designated anchor population;
- compressed prior evidence of cross-community participation;
- a slowly updated landmark-reachability score;
- externally meaningful region or organization coverage;
- a score learned against rating-stability outcomes.

Using raw degree as `a_v` is insufficient: a dense isolated component can generate high degree
internally.

#### Community Coverage

Detect or assign relatively stable community labels, then cover communities rather than people:

```text
E_i = set of external communities recently reached by i
```

Coverage Credit can then divide the value of each independently reached community among the
participants who supply it.

Potential labels include:

- clubs inferred from repeated coattendance;
- geographic regions when available;
- communities from an offline label-propagation pass;
- stable match-series clusters;
- random landmarks selected across known components.

This compresses thousands of redundant people in one component into fewer independent attachment
units.

#### Participation Coefficient

Given community labels, direct breadth can be supplemented with:

```text
participation_i = 1 - sum_c((k_i,c / k_i)^2)
```

where `k_i,c` is competitor `i`'s encounter weight in community `c`.

This is high when direct relationships span several communities and low when all evidence remains
inside one population. It measures the behavior that field-size moments attempted to infer.

#### Outcome-Defined Attachment

Rather than designating a global component manually, define attachment by the empirical target:

```text
How much does observing this competitor or match reduce uncertainty in cross-population rating
alignment?
```

Withheld-bridge and bootstrap experiments can estimate that value. A lightweight local feature can
then be fitted to predict it.

### Revised Recommendation After The Sweep

Do not use raw external coverage as the sole Elo connectivity multiplier.

Do not discard Coverage Credit. Preserve its allocation mechanism, but distinguish:

```text
Raw coverage:
Estimates recent two-hop component reach.

Relative Coverage Credit:
Identifies unusually important carriers within a field.

Anchored or community-weighted coverage:
Candidate definition of global attachment.
```

Effective Degree remains a useful optional direct-breadth diagnostic, but the sweep confirms that
it cannot measure global attachment.

The next implementation experiment should add relative/excess Coverage Credit and a controlled
bridge sweep. The next conceptual experiment should compare community-weighted or anchored coverage
against real cross-population rating stability.

## Superseded Initial USPSA Major-Participation Profile Simulation

> This section preserves the first profile experiment for history. It assigned overlapping division
> memberships and used simpler local-activity models. The later **Revised One-Division USPSA
> Simulation** supersedes it.

### Motivation

Global attachment may be too ambitious for a fast local approximation. A narrower operational
target is:

> Does a competitor or field have recent attachment to the population that regularly attends major
> matches?

USPSA has approximately 50,000 members, while the supplied 2025-2026 participation counts identify:

```text
At least one major:                         11,118 unique people
At least one major in each year:             3,761 unique people
At least four majors over two years:         2,244 unique people
No observed major in the supplied period:   38,882 people
```

The supplied division marginals were reproduced exactly:

```text
Division          Any Major   Annual   Frequent
Open                  1,878      581        431
Limited                 541       89         46
PCC                    1,172      402        218
Limited Optics         4,083    1,152        713
Carry Optics           4,843    1,379        828
Production               551       99         53
Single Stack             618      198         46
Revolver                 102       19         11
Limited 10                95       10          1
```

The sums exceed the unique-person counts because competitors can attend majors in multiple
divisions. The simulator assigns overlapping division memberships while preserving every supplied
marginal.

### Scope And Important Caveat

The simulation measures an aggregate member coattendance graph:

```text
Two members are connected when they attend the same match, even if they compete in different
divisions.
```

Production rating connectivity may be calculated inside a division or division group. The supplied
data does not include total local participation or membership denominators by division, so a
calibrated per-division graph cannot be inferred from these major-only counts.

The division data is therefore used to reproduce major-participant overlap and attendance metadata,
not to claim accurate division-specific local populations.

### Simulator

The implementation is:

```text
research/connectivity/uspsa_major_profile_simulation.dart
```

Run the default correlated-activity model with:

```text
dart run research/connectivity/uspsa_major_profile_simulation.dart
```

Run the activity-matched model with:

```text
dart run research/connectivity/uspsa_major_profile_simulation.dart --matched-local-activity
```

Both models:

- create exactly 50,000 members;
- reproduce all unique and division-level major cohorts;
- assign 50 home regions and 400 home clubs;
- generate two chronological years;
- generate approximately 200,000 match entries;
- create local club, regional major, and national match types;
- calculate connectivity causally from pre-match windows;
- evaluate final scores against the known major-attendance cohorts.

Majors connect larger and more geographically varied populations. Local matches repeatedly draw
from home clubs.

### Attendance Model

The major cohorts receive approximately:

```text
Occasional:
  1-2 majors, increased as necessary to cover multiple observed divisions

Annual:
  2-3 majors, increased as necessary to cover multiple observed divisions

Frequent:
  4-7 majors, increased as necessary to cover multiple observed divisions
```

Regional-versus-national major attendance probabilities are:

```text
Occasional: 10% national
Annual:     25% national
Frequent:   55% national
```

These probabilities are synthetic assumptions, not facts derived from the supplied table.

### Two Local-Activity Models

The default run assumes major participants are also more active locally:

```text
Local-only mean local matches:    3.2
Occasional mean local matches:    4.0
Annual mean local matches:        6.0
Frequent mean local matches:      8.0
```

That is plausible but not established by the supplied data.

The matched run gives every cohort the same expected local activity:

```text
All cohorts: 3.6 mean local matches
```

The second run is the better test of whether metrics recover major exposure rather than an assumed
correlation between major and local activity.

## Default Correlated-Activity Results

### Scale And Runtime

```text
Members:                              50,000
Active members:                       48,458
Matches:                               4,000
Entries:                             206,556
Generated unique major shooters:      11,118
Generation time:                       0.91 seconds
Connectivity math time:                8.42 seconds
Projected 200,000-entry math time:      8.15 seconds
```

This population is much sparser than the dense isolated-component stress test. Recent neighborhood
sizes remain smaller, and exact Coverage Credit is comfortably inside the computational target.

### Cohort Metric Means

```text
Cohort        U      T    D_eff      Q    sqrt   carriers   effective   credit
Local-only    89    160     76.1    0.9   118.4      210.0       108.9      0.9
Occasional   339    418    288.9   47.0   375.9      362.7       346.0     47.0
Annual       411    494    353.3   92.1   449.4      381.7       416.1     92.1
Frequent     622    692    566.8  181.9   656.0      442.0       625.3    181.9
```

Every metric orders the synthetic cohorts correctly. Coverage Credit has the largest proportional
separation, while the field-size-moment carrier score compresses annual and frequent participants.

### Correlations

```text
Method       Major Count   Local Count   Recent Majors   Mean Field
sqrt               0.711         0.748           0.712        0.610
carriers           0.712         0.436           0.711        0.774
effective          0.710         0.736           0.713        0.627
credit             0.719         0.751           0.693        0.366
```

The strong local-count correlations for sqrt, Effective Degree, and credit show that this run cannot
cleanly attribute their success to major exposure. The carrier score is less correlated with local
count but most correlated with field size.

### Classification

Area under the ROC curve:

```text
Method       Any Major   Annual   Frequent
sqrt             0.991    0.960      0.971
carriers         0.994    0.952      0.960
effective        0.990    0.959      0.970
credit           0.996    0.979      0.987
```

Exact-size top-K precision and recall:

```text
Method       Any @ 11,118   Annual @ 3,761   Frequent @ 2,244
sqrt                  95.2%            63.7%              68.1%
carriers              97.3%            60.2%              59.2%
effective             95.4%            63.4%              68.2%
credit                98.3%            71.9%              69.5%
```

Coverage Credit performs best in this run, but the activity assumption materially helps it and the
direct breadth scores.

## Matched-Local-Activity Results

### Scale And Runtime

```text
Members:                              50,000
Active members:                       48,945
Generated unique major shooters:      11,118
Matches:                               3,915
Entries:                             206,902
Generation time:                       0.93 seconds
Connectivity math time:                7.78 seconds
Projected 200,000-entry math time:      7.52 seconds
```

The realistic sparse-population benchmark is safely below the 30-second target.

### Realized Activity

```text
Cohort        Local Matches   Major Matches   Majors In Recent Five
Local-only              3.6             0.0                   0.00
Occasional              3.6             1.7                   1.48
Annual                  3.5             2.5                   2.04
Frequent                3.6             5.5                   2.99
```

Local activity is now equal. Total activity still rises with major count, which is inherent in the
observed major-frequency categories.

### Cohort Metric Means

```text
Cohort        U      T    D_eff      Q    sqrt   carriers   effective   credit
Local-only    94    175     80.4    1.0   127.4      214.2       117.3      1.0
Occasional   336    411    291.2   57.9   370.8      358.7       344.2     57.9
Annual       452    524    402.8  102.0   486.1      389.8       458.1    102.0
Frequent     677    746    624.3  204.5   710.6      438.6       681.8    204.5
```

The monotonic ordering survives equal local activity. Major matches genuinely produce broader,
less-local histories under the generator.

### Match Metrics

```text
Type         Mean Size   Coverage   Efficiency   Effective Carriers
Club                48      1,309        0.372                  5.2
Area               151      5,723        0.192                 74.5
National           249     14,226        0.206                166.3
```

Historical participant scores aggregated before each match were:

```text
Type          sqrt   carriers   effective   credit
Club         249.5      183.5       239.8     48.4
Area         436.3      280.8       418.0    108.1
National     542.0      313.4       521.5    143.3
```

All methods produce the intended local-to-area-to-national ordering.

Coverage efficiency remains highest at clubs, reinforcing that it measures nonredundancy rather
than total attachment. Effective carrier count scales strongly with field size and distributed
participation.

### Correlations

```text
Method       Major Count   Local Count   Recent Majors   Mean Field
sqrt               0.713         0.534           0.714        0.614
carriers           0.717         0.170           0.714        0.788
effective          0.714         0.521           0.715        0.629
credit             0.716         0.542           0.696        0.340
```

Equalizing expected local activity reduces but does not eliminate local-count correlation. Random
Poisson variation and chronological placement affect which matches remain in the five-match window.

Coverage Credit has the lowest field-size correlation by a large margin. Rating Carriers remains
dominated by field size.

### Classification AUC

```text
Method       Any Major   Annual   Frequent
sqrt             0.991    0.975      0.983
carriers         0.997    0.963      0.969
effective        0.992    0.975      0.983
credit           0.994    0.975      0.985
```

All methods almost perfectly separate any major participant from local-only members.

This task is too easy to validate graph attachment:

- majors are much larger than local matches;
- majors deliberately mix regions;
- major participants necessarily have additional total matches;
- local-only members remain mostly inside one club.

Even Rating Carriers achieves AUC 0.997 for any-major exposure despite its known failure on the
isolated-mega test. High classification accuracy here does not rehabilitate field-size moments as a
graph measure.

The annual and frequent tasks are more informative. Sqrt, Effective Degree, and Coverage Credit all
outperform Rating Carriers.

### Exact-Size Top-K Recovery

```text
Method       Any @ 11,118   Annual @ 3,761   Frequent @ 2,244
sqrt                  95.9%            71.3%              73.1%
carriers              98.3%            63.7%              59.5%
effective             96.2%            71.8%              72.6%
credit                98.4%            70.1%              68.1%
```

The interpretation differs by target:

- Coverage Credit best identifies whether someone has any major exposure.
- Effective Degree narrowly leads annual top-K recovery.
- Sqrt narrowly leads frequent top-K recovery.
- Rating Carriers identifies any major because of field size but is substantially worse at
  distinguishing sustained major participation.

Coverage Credit has the best frequent-participant AUC but weaker exact top-K recovery. AUC evaluates
the complete ranking, while top-K depends on the extreme upper tail.

This behavior matches the metric's definition. An occasional major shooter who returns to a local
club can receive large marginal credit by importing a network no one else at the club reaches. A
frequent national competitor shares external reach with many other frequent competitors and divides
the credit. Coverage Credit measures marginal carrier behavior, not major-match count.

That is a feature if the target is rating transport. It is a limitation if the desired score is
simply a proxy for frequency of major attendance.

## Interpretation Of The Realistic-Population Experiment

### The Narrower Goal Is Feasible

A fast recent-window approximation can reliably distinguish members with major-connected histories
in a 50,000-member, approximately 200,000-entry synthetic population.

The computational result is stronger than the dense-component stress test:

```text
Projected 200,000-entry time: approximately 7.5-8.2 seconds
```

The 30-second failures occurred in adversarial dense mature components where every participant
carried a near-maximum five-match neighborhood. The USPSA-profile graph is sparse and dominated by
small local fields.

### Existing Sqrt Is More Useful Than The Initial Discussion Suggested

For the operational target "recent attachment to major-connected populations," current square-root
connectivity performs well:

- it strongly separates all major cohorts;
- it leads frequent top-K recovery;
- it is simpler than Coverage Credit;
- its runtime and storage behavior are already understood.

Its limitation remains conceptual: it measures breadth and volume, so a large isolated circuit can
produce a similar score. The earlier isolated-component experiments demonstrate that failure mode.

The narrower goal may accept that limitation if large isolated circuits are rare or still provide
useful rating evidence.

### Effective Degree Is A Mild Refinement

Effective Degree remains almost behaviorally identical to sqrt, but it slightly improves annual
top-K recovery:

```text
Annual top-K:
  Effective Degree: 71.8%
  Sqrt:             71.3%
```

The difference is too small to justify replacement based on simulation alone. Effective Degree's
main value is principled handling of repeated-core concentration.

### Coverage Credit Measures Something Different

Coverage Credit:

- has much lower field-size dependence;
- best recovers any major exposure at the exact cohort size;
- gives very large cohort separation;
- identifies people who carry outside history into local fields;
- does not rank sustained major frequency as directly as breadth measures.

This supports keeping two concepts separate:

```text
Breadth/volume:
How much broad recent evidence does this rating contain?

Carrier contribution:
How unusually responsible is this competitor for connecting the current field outward?
```

Trying to force both into one scalar may discard useful information.

### Rating Carriers Remains The Weakest Candidate

Rating Carriers appears excellent on the easy any-major classification task because majors are
large. It performs worst for sustained major participation:

```text
Frequent top-K:
  carriers: 59.5%
  credit:   68.1%
  effective:72.6%
  sqrt:     73.1%
```

Together with its isolated-mega failure and field-size correlation of 0.788, this is further
evidence against interpreting field-size variance and skewness as graph bridge behavior.

## Remaining Simulation Confounds

### Total Activity

Matching local activity does not match total activity. Frequent competitors necessarily receive
more major matches.

The next ablation should hold total match count constant:

```text
Local-only: all local matches
Occasional: replace some local matches with occasional majors
Annual: replace more local matches with majors
Frequent: replace still more local matches with majors
```

That isolates population mixing from total evidence volume.

### Field Size

Major matches are intentionally larger than local matches. A field-size-only score can therefore
classify major exposure.

A field-size-matched ablation should compare:

- large local supershoots drawing repeatedly from one regional population;
- equally large majors drawing from several regions;
- equally active competitors in both populations.

This is the realistic analogue of the isolated-mega control.

### Aggregate Versus Per-Division Connectivity

The aggregate graph may overstate connectivity available to a per-division rating.

A per-division simulation requires:

- total active local competitors in each division;
- local match-entry counts by division;
- match-size distributions within each division;
- division-switching behavior;
- the rating groups actually used in production.

Without those denominators, the supplied major table can calibrate positive cohorts but not each
division's full graph.

### Synthetic Major Mixing

The regional and national mixing probabilities are assumptions. The simulation encodes the premise
that majors connect geographically broader populations, then tests whether metrics recover that
structure.

The strong AUC results confirm implementation behavior, not real-world predictive validity.

## Revised Practical Direction

For an economical approximation of major-connectedness:

1. Retain sqrt direct breadth as the baseline candidate.
2. Test Effective Degree as a concentration-corrected alternative, but require real-data
   improvement before accepting its additional complexity.
3. Retain Coverage Credit as a separate carrier diagnostic or secondary match feature.
4. Remove field-size-moment bridge bonuses from serious consideration.
5. Run total-activity-matched and field-size-matched ablations.
6. Validate on actual USPSA history using future cross-population residuals or withheld majors.

For Elo, a practical first comparison is:

```text
Model A: no connectivity modifier
Model B: current sqrt connectivity
Model C: Effective Degree breadth
Model D: sqrt breadth plus a small Coverage Credit carrier term
```

For a future LLR intraclass-correlation modifier, match-level breadth and carrier concentration
should remain separate inputs until calibration shows how each relates to within-match residual
correlation.

## Revised One-Division USPSA Simulation

### Why The Profile Was Revised

The first USPSA-profile experiment made three assumptions that were too strong:

1. It used overlapping division assignments even though the desired benchmark is one connectivity
   population.
2. It assigned every local competitor to one home club.
3. It modeled local activity as either monotonically correlated with major frequency or completely
   independent of it.

The revised model follows these principles:

- Treat all 50,000 members as one division.
- Reproduce only the supplied unique-person thresholds, without division splits.
- Give regional competitors a primary club, usually a secondary club, and several occasional clubs.
- Use a strongly skewed local-participation distribution.
- Increase local activity through moderate major participation.
- Reduce local participation for the highest-volume major shooters, who increasingly replace local
  matches with majors.

The implementation remains:

```text
research/connectivity/uspsa_major_profile_simulation.dart
```

Run with:

```text
dart run research/connectivity/uspsa_major_profile_simulation.dart
```

### Exact Major Thresholds

The model creates exactly:

```text
Total members:                         50,000
At least one major:                    11,118
At least one major in both years:       3,761
At least four majors over two years:    2,244
```

The generated matches preserve the same realized thresholds:

```text
Generated unique major shooters:       11,118
Generated annual major shooters:        3,761
Generated four-plus major shooters:     2,244
```

Every major token is scheduled into a distinct match for that shooter. Attendance is not discarded
when a circuit-year has a small remainder.

### Major Count Distribution

The supplied data gives thresholds, not a complete frequency distribution. The simulation assumes:

```text
Occasional cohort:
  70% shoot 1 major
  25% shoot 2 majors
   5% shoot 3 majors
  All are assigned to only one of the two years

Annual-but-not-four-plus cohort:
  Shoot 2-3 majors
  At least one in each year

Four-plus cohort:
  70% shoot 4-6 majors
  20% shoot 7-9 majors
  10% shoot 10-16 majors
  At least one in each year
```

The first three threshold counts are exact. The distribution within the thresholds is a research
assumption and should be replaced if actual attendance-frequency counts become available.

### Regional Club Model

The population has:

```text
Regions:           50
Clubs per region:   8
Total clubs:       400
```

Each member receives:

- one primary club;
- an 80% chance of having a secondary club;
- three or four additional satellite clubs in the same region.

Each local attendance chooses:

```text
Primary club:      45%
Secondary club:    30%
Satellite clubs:   25%
```

When no secondary club exists, its attendance probability returns to the primary club. Each of the
three or four satellite clubs therefore receives only about 6-8% of a member's local attendance.

This produces repeated local populations without making club boundaries absolute. Active major
cohorts average approximately four to five distinct local clubs over the two-year period, while
approximately 75% of their attendance remains concentrated at one or two clubs.

### Local Activity Model

Members with no major attendance use a mixture distribution:

```text
70%: mean 0.5 local matches
20%: mean 4 local matches
 8%: mean 12 local matches
 2%: mean 30 local matches
```

This creates many inactive or minimally active roster members plus a small high-activity tail.

For major participants with at most six majors:

```text
expected local matches = 12 + 8 * major count
```

Examples:

```text
1 major:  20 expected local matches
2 majors: 28 expected local matches
4 majors: 44 expected local matches
6 majors: 60 expected local matches
```

For more than six majors:

```text
expected local matches = max(2, 60 - 12 * (major count - 6))
```

Examples:

```text
7 majors:  48 expected local matches
8 majors:  36 expected local matches
9 majors:  24 expected local matches
10 majors: 12 expected local matches
11+ majors: approaches 2 local matches
```

A lognormal individual multiplier and Poisson realization add substantial variation around those
means.

This creates an inverted-U relationship:

- moderate major shooters are usually very active locally;
- the highest-volume major shooters increasingly shoot majors instead of locals.

### Generated Scale

```text
Members:                              50,000
Active members:                       32,808
Matches:                              17,526
Entries:                             444,897
Local matches:                        17,364
Area majors:                             120
National majors:                          42
```

Approximately 17,192 roster members have no generated match entries. They remain useful when
describing the complete 50,000-member roster, but production rating connectivity would normally
contain only members with at least one rating event. Results are therefore reported both for the
full roster and for active members.

### Runtime

```text
Match generation:                     0.58 seconds
Connectivity math:                   14.69 seconds
Projected 200,000-entry math time:    6.60 seconds
```

The more realistic one-division graph remains comfortably inside the mathematical budget. Exact
Coverage Credit is economical because most of the graph consists of small local fields and short
recent neighborhoods.

### Realized Activity

By supplied threshold cohort:

```text
Cohort        People   Local Matches   Major Matches   Local Clubs   Recent Majors
Local-only    38,882             2.7             0.0          1.14            0.00
Occasional     7,357            22.8             1.4          4.46            0.31
Annual         1,517            31.6             2.5          4.78            0.39
Frequent       2,244            43.2             6.4          4.71            0.94
```

The frequent-cohort aggregate still has high local activity because most of its members shoot 4-6
majors. The major-count bands expose the intended upper-tail reversal:

```text
Major Count   People   Local Matches   Local Clubs
0             38,882             2.7          1.14
1              5,154            19.9          4.34
2-3            3,720            30.5          4.74
4-6            1,578            51.3          5.13
7-9              421            36.4          4.89
10+               245             2.9          1.63
```

The 4-6-major group shoots approximately 2.1 local matches per month over two years. The 10+ group
shoots mainly majors.

### Score Behavior Across Major Counts

```text
Major Count   sqrt   Effective Degree Score   Coverage Credit
0              34.2                    32.1               3.3
1             145.9                   135.1              38.8
2-3           159.0                   148.0              43.2
4-6           185.4                   175.1              60.0
7-9           258.2                   245.9             109.2
10+           880.0                   836.0             203.0
```

Several patterns are important.

#### Breadth Scores Flatten Through Moderate Activity

Sqrt and Effective Degree rise sharply from zero to one major, then change little through 1-3
majors. Those competitors shoot many local matches after the major, so the five-match window often
contains mostly local fields.

The 4-6 group rises moderately. The 7-9 and 10+ groups rise sharply because majors occupy an
increasing fraction of the final five-match window.

#### The Highest Major Group Is Easy To Identify

The 10+ group has only 2.9 local matches on average. Its recent window is dominated by majors,
producing very large direct breadth:

```text
sqrt:       880.0
effective:  836.0
credit:     203.0
```

This matches the real-world hypothesis that the highest-volume major shooters participate mainly in
majors.

#### Coverage Credit Is More Monotonic

Coverage Credit rises at every major-count band:

```text
3.3, 38.8, 43.2, 60.0, 109.2, 203.0
```

Returning to several regional clubs after a major creates opportunities to import external history.
Even when a major has aged out of the final five matches, its effects can be reflected through
credit earned at subsequent local matches.

### Cohort Metric Means

```text
Cohort        U      T    D_eff      Q    sqrt   carriers   effective   credit
Local-only    31     38     27.7    3.3    34.2       76.2        32.1      3.3
Occasional   136    164    117.1   38.8   148.8      198.5       137.9     38.8
Annual       151    178    132.5   50.0   164.0      215.3       153.2     50.0
Frequent     258    293    232.6   84.9   274.9      258.7       260.5     84.9
```

All measures retain the intended ordering, but Coverage Credit has the clearest annual-versus-
occasional and frequent-versus-annual separation.

### Match-Level Results

```text
Type       Matches   Mean Size   Coverage   Efficiency   Effective Carriers
Club        17,364          24        939        0.369                  7.7
Area           120         146      3,613        0.178                 36.7
National        42         253     11,315        0.183                204.4
```

Pre-match participant-score aggregations were:

```text
Type          sqrt   carriers   effective   credit
Club         187.0      174.9       177.4     65.3
Area         383.2      195.0       357.8    105.3
National     436.2      258.5       408.9    138.9
```

The local-to-area-to-national ordering remains intact.

Club match credit is substantial because major-connected competitors carry outside history back
into several regional clubs. This is intended behavior: a small match can be attached to the wider
network through a few participants.

Coverage efficiency remains highest at clubs and must not be interpreted as absolute attachment.

### Metric Correlations

```text
Method       Major Count   Local Count   Recent Majors   Mean Field
sqrt               0.645         0.945           0.470        0.874
carriers           0.622         0.880           0.470        0.912
effective          0.644         0.944           0.470        0.873
credit             0.710         0.903           0.442        0.635
```

Sqrt and Effective Degree remain dominated by local activity and field size. Their correlation with
major count is substantially weaker than their correlation with local count.

Rating Carriers is the most field-size-dependent method.

Coverage Credit also correlates strongly with local activity because a carrier needs opportunities
to transport rating information into fields. However:

- it has the strongest major-count correlation;
- it has far less field-size dependence;
- it provides information beyond direct breadth.

### Full-Roster Classification

AUC across all 50,000 roster members:

```text
Method       Any Major   Annual   Frequent
sqrt             0.940    0.894      0.895
carriers         0.924    0.889      0.889
effective        0.939    0.894      0.896
credit           0.961    0.905      0.901
```

These values are inflated by the 17,192 inactive local-only members, all of whom have zero scores.

### Active-Member Classification

Restricting evaluation to the 32,808 members with generated entries:

```text
Method       Any Major   Annual   Frequent
sqrt             0.893    0.830      0.836
carriers         0.863    0.824      0.827
effective        0.891    0.831      0.837
credit           0.929    0.849      0.846
```

This is the more relevant result.

Coverage Credit has the best AUC for all three targets. Its advantage is large for any-major
classification and modest for annual and frequent classification. The frequent-major AUC of 0.846
remains notable because the upper tail deliberately reduces local activity.

Rating Carriers trails both breadth measures and credit while remaining strongly tied to field size.

### Exact-Size Top-K Recovery

```text
Method       Any @ 11,118   Annual @ 3,761   Frequent @ 2,244
sqrt                  68.8%            45.3%              40.6%
carriers              70.3%            45.0%              40.3%
effective             68.8%            45.2%              40.9%
credit                73.5%            43.8%              39.6%
```

The task is now substantially harder than the superseded profile simulation. Local competitors
cross clubs, major shooters often accumulate many local matches, and the final five-match window
can contain no majors.

Coverage Credit leads any-major recovery by 3.2 percentage points, but does not produce the best
extreme tail for annual or frequent participation:

```text
Annual leader:    sqrt at 45.3%
Frequent leader:  Effective Degree at 40.9%
Coverage Credit:  43.8% annual, 39.6% frequent
```

This distinction matters. AUC asks whether a randomly selected positive tends to rank above a
randomly selected negative across the whole distribution. Exact-size top-K evaluates only the
highest-scoring tail. Credit produces the best broad ordering but allows enough high-credit
occasional and local carriers into its extreme tail to reduce recovery of the narrower cohorts.

### Effective Degree Again Adds Little

Effective Degree remains very close to sqrt:

```text
Any-major top-K:  both 68.8%
Annual top-K:     45.2% effective versus 45.3% sqrt
Frequent top-K:   40.9% effective versus 40.6% sqrt
```

It is still mathematically preferable when encounter concentration matters, but the simulation does
not show a practical predictive advantage large enough to justify replacing sqrt.

### Interpretation Of Coverage Credit

Coverage Credit is not merely recognizing current major attendance:

```text
Recent major count correlation: 0.442
Major count correlation:        0.710
```

It appears to capture the transport cycle:

```text
major participation
-> external opponent history
-> return to one or more local clubs
-> marginal external coverage supplied to those fields
```

That is close to the operational meaning of a rating carrier.

The strong local-count correlation of 0.903 is not entirely a confound. A person cannot repeatedly
carry information into local populations without participating in those populations. Nevertheless,
real-data validation must determine whether credit over-rewards sheer activity.

### Revised Conclusions

The narrower target—recent attachment to the major-connected USPSA population—is plausible for a
fast local approximation.

The current evidence supports:

1. Coverage Credit as the strongest carrier-oriented candidate.
2. Sqrt as a useful direct-breadth baseline.
3. Effective Degree as a theoretically sound but empirically minor refinement.
4. Rejection of field-size moments as a bridge model.
5. Separate treatment of breadth and carrier contribution.

The result also changes the likely role of Coverage Credit. Raw external coverage was invalid as a
general global-component measure, but relative credit within a realistically structured local/major
network appears useful for identifying people whose histories connect local fields to major
populations.

### Remaining Assumptions

The model still depends on synthetic choices:

- local activity distribution;
- major-count distribution above the supplied thresholds;
- club attendance probabilities;
- regional-versus-national major probabilities;
- local, area, and national field sizes;
- random scheduling within each year;
- one-division aggregation.

The model should be recalibrated whenever actual distributions become available.

### Next Tests

#### Constant Total Match Count

Hold every major cohort's total match count constant and replace local matches with majors. This
isolates network mixing from evidence volume.

#### Large Local Supershoots

Generate local matches with major-sized fields but repeated regional populations. Compare them with
same-sized cross-region majors.

#### Relative Coverage Credit

Add:

```text
relativeCredit_i = Q_i / (C_F / |F|)
```

This tests whether excess marginal contribution improves identification beyond raw credit while
reducing component-size effects.

#### Actual USPSA Data

For each historical competitor:

1. Label prior major participation using match level.
2. Calculate connectivity without using match level.
3. Evaluate future cross-region or major performance.
4. Compare prediction calibration and rating stability.

The synthetic simulation now provides a plausible stress harness, but actual chronological match
history is the decisive test.

## Final Recommendation

Coverage Credit improves enough on the existing candidates to justify production-quality
implementation and further evaluation, but not enough to replace sqrt as the default connectivity
path.

The final one-division simulation produced the strongest result for identifying any active major
participant:

```text
Active any-major AUC:
  sqrt:    0.893
  credit:  0.929

Any-major top-K recovery:
  sqrt:    68.8%
  credit:  73.5%
```

The advantage narrows for more frequent major participation:

```text
Active annual AUC:
  sqrt:    0.830
  credit:  0.849

Active frequent AUC:
  sqrt:    0.836
  credit:  0.846

Annual top-K recovery:
  sqrt:    45.3%
  credit:  43.8%

Frequent top-K recovery:
  sqrt:    40.6%
  credit:  39.6%
```

Coverage Credit therefore improves broad ordering of major-connected competitors, especially at the
amateur-to-major boundary, but does not improve the highest-scoring tail for annual or frequent
shooters.

Its local-count correlation is also high:

```text
Spearman(credit, local count) = 0.903
```

Some of its classification advantage may come from recognizing highly active competitors rather
than network attachment alone. The simulated participation distribution is empirically motivated,
but the result is not a substitute for validation on actual chronological match data.

### Production Direction

The recommended disposition of the current candidates is:

1. Retire Rating Carriers as a global-attachment candidate. Field-size variance and skewness are
   field descriptors, not evidence of graph bridging.
2. Keep `sqrt(T * U)` as the production default and direct-evidence baseline.
3. Do not adopt Effective Degree as a replacement unless real data reveals meaningful dense
   repetition that the simulations did not.
4. Promote Coverage Credit to the primary experimental carrier metric.
5. Treat breadth and carrier contribution as separate signals rather than forcing them into one
   master connectivity number prematurely.

This is not merely an implementation compromise. Sqrt and Coverage Credit measure different
properties:

```text
sqrt(T * U):
  How much recent direct comparison evidence does this competitor have?

Coverage Credit:
  How much otherwise-unrepresented opponent history does this competitor contribute to a field?
```

USPSA's amateur/semi-professional participation structure makes the second property important.
Moderate major shooters return to several local clubs and transport rating information between
populations. That does not make direct evidence volume irrelevant.

### Relative Coverage Credit Is Not Yet A Winner

Relative Coverage Credit remains an experiment:

```text
R_i = Q_i / (C_F / |F|)
```

It has not produced the reported `0.929` AUC; that result belongs to raw Coverage Credit.

Its normalization also guarantees:

```text
sum_i(R_i) = |F|
mean_i(R_i) = 1
```

Relative Credit can identify competitors who contribute unusually much coverage within a field, but
its same-match mean cannot measure that field's absolute attachment. A homogeneous national and a
homogeneous large disconnected island can both have a mean relative credit of `1`.

Consequently:

- do not average current-match Relative Credit as an attachment scalar;
- test historical Relative Credit as a competitor state;
- test upper quantiles, maxima, and concentration as match-level carrier signals;
- handle `C_F = 0` and low-coverage fields with explicit zero or shrinkage behavior.

Relative Credit may solve the carrier-ranking problem. It does not solve the large-island problem.

### Absolute Attachment Requires An Anchor

No unlabeled graph-only metric can distinguish two structurally identical components merely because
one is considered global and the other isolated. Absolute global attachment requires additional
context.

Two practical directions are:

```text
Anchored coverage:
  Weight externally reached competitors by attachment to a trusted reference population.

Community-weighted coverage:
  Count independent clubs or inferred communities with a saturating contribution per community.
```

Relative Credit alone does not count independent clubs. Community-aware coverage requires explicit
club/community labels or an inferred partition, followed by Shapley allocation of that weighted
coverage if individual carrier credit is still desired.

### Promotion Criteria

Coverage Credit should replace sqrt as the main path only if it passes chronological real-data
testing and improves the rating system's actual objective.

The relevant tests are:

1. Calculate every connectivity value using only information available before each match.
2. Compare no modifier, sqrt, Coverage Credit, and a two-signal model.
3. Evaluate out-of-sample prediction calibration and residuals, not merely major-attendance labels.
4. Measure cross-club and cross-region scale alignment specifically.
5. Test isolated and weakly connected populations for unstable multipliers.
6. Repeat across seeds, time periods, divisions, and participation-density assumptions.
7. Confirm that runtime and memory remain within the production budget.

Until those tests succeed, the production recommendation is:

```text
Default breadth signal:       sqrt(T * U)
Experimental carrier signal:  Coverage Credit
Rejected bridge proxy:        Rating Carriers
Deferred refinement:          Effective Degree
Future attachment signal:     Anchored or community-weighted coverage
```

The likely endpoint is a calibrated two-signal architecture, but the simulations do not yet prove
that such an architecture is mandatory or that either signal should replace the other.
