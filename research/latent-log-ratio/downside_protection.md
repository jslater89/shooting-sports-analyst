# LLR Downside Protection

Working note. The sport feature is the thing to preserve; Elo's two tricks are implementations of it, not the feature. Capture this before it turns into "just copy bomb protection."

## The Feature

> A shooter of any level finishing above par at a full match is likely a signal of improvement, but a shooter finishing significantly below par is often not directly related to skill.

That is an **asymmetric observation model**, not "bombs are outliers." Practical shooting is downside-dominated: misses, no-shoots, procedurals, squibs, mental collapse. Upside is closer to a biomechanical ceiling.

The prediction EVT section already says this (performance variance is not symmetric; max potential is bounded). The update model is still a symmetric Gaussian around `R_i`.

Two claims get mixed together and should stay separate:

1. **Universal + asymmetric.** Above-par match results are cleaner skill evidence than below-par ones, at every level.
2. **Elite-conditional bombs.** A GM at 83% is usually contamination; a C-class at 35% might be skill.

Elo bomb protection is claim 2. Per-stage Elo is closer to claim 1, plus the right granularity for stage-local contamination. LLR currently implements neither directly.

## What Elo Has



### 1. Per-stage ratings

Each stage is an independent observation with small `K`. One zero among eight stages is seven normal updates plus one bomb. Net damage is ~1/8 of a match-level bomb (modulo bomb protection on that stage). The other stages still provide signal.

This matches the failure mode: contamination is almost always stage-local (squib, broken gun, miss a popper, fall down). Match aggregation folds that into one observation and destroys the clean stages' evidence.

In hit-factor sports this is especially ugly. A zero on one of eight equal-point stages, otherwise 95%:

```
match % ≈ 7/8 * 95% = 83%
```

That looks like a "pretty bad match" rather than "seven normal stages and one non-skill event."

### 2. Explicit bomb protection

`K`-hack, elite-gated, one-sided:

- Expected percent ≳ 75% (fades in to 100%)
- Raw change ≲ −0.4K
- Reduce `K` by 10–75% depending on how good you are and how bad the bomb is

It does not deform the expected-score function. It just refuses to believe the update. One event, not `K = 0`. GMs can still fall if they keep finishing below par.

## What LLR Has (Related, Not The Same)

Symmetric in `z`, absolute in `S`:

- **Student-t mean damping** (`c_t = 2`): damps `|z| ≳ 2` in both directions, mean only.
- **Tail noise** `η(S)`: starts at `s_0 = 0.40` — absolute finish, not residual vs expectation.
- **Huber baseline**: protects the field's estimate of `ln(X_win)`, not the bomber's own `R_i`.
- **Shock / Trend**: treat a large residual as "maybe the world changed."

The 100% ceiling makes Student-t de facto one-sided for elites (large positive `z` is rare near the top; large negative `z` is easy). That is not the same as modeling the feature, and it still does not fire on the common case below.

## The Hole: Moderate, Stage-Local Bombs

Take an 8-stage match, GM expected ~95%, zeros one stage, shoots the rest normally. Match percentage ≈ 83%.

```
e = ln(0.83) - ln(0.95) ≈ -0.135
```

With current defaults (`σ_sport² = 0.0012`, tight veteran `V_i`), `√T_i` is roughly 0.05–0.07, so `z ≈ -2` to `-2.5`. Then:

- `w_t ≈ 0.9+` — almost full mean update
- `η(0.83) = 0` — nowhere near `s_0 = 0.40`
- `e_phys² > T_i` — **Shock still fires**
- momentum takes almost the full negative blip — **Trend inflates next match's prior**

The mean moves, *and* the next match gets a larger Kalman gain. That is **anti-protection** for the moderate bomb.

Extreme disasters (30–40% match) *are* handled: Student-t plus tail noise. The hole is specifically "respectable match percentage produced by one contaminated stage."

A two-stage disaster (~70%) gets `z ≈ -4` to `-6` and Student-t starts to help. So if Elo is winning on "GMs who DNF'd one stage then looked normal next month," this is the mechanism. If Elo is winning on "C-class 30% finishes," tail noise may already be doing the job.

## By-Stage LLR

**Goal, not next step.**

Right now match-mode LLR is about as slow as stage-mode Elo. The math needs ~10× before by-stage is sensible.

Even with faster math, it is not a toggle:

- `1 SV` is a *match* observation. Stage-level residuals are much larger. `σ_sport²` must be retuned upward so stage-by-stage is not noise-dominated.
- `λ`, `β`, `γ`, `k_max` are in event units. Per-stage they would have half-lives inside a single match unless scaled by `~1/n_stages`.
- Stage zeros hit the log floor constantly; zero/DNF policy has to be real.
- A classifier and a 32-round field course are not exchangeable. Equal-weight per-stage throws away USPSA points weighting, which match-level LLR gets for free. Stage-point (or round-count) weights would be required.
- Downside protection is *more* important at stage level, not less: an 80% stage for someone who wins the match is common; an 80% match for someone who wins matches is not. Student-t / tail noise calibrated to match percentages will not be in the right place.

Log-ratio cancellation still kills the stage winner's curse, which is worse at stage level (noisier max). That is why by-stage LLR is attractive *once the filter is cheap enough*. Until then, solve the feature at match level.

## Refined Cut

A bombed **match** (evenly below par across stages) is a skill signal. Student-t softens it only if it is really extreme. One-sided Student-t is a natural extension: `c_t = 2` two-way is already a compromise to avoid damping upward innovations, because weak-field / novelty mostly solve spurious wins. There is no principled reason the kernel must be symmetric.

A bombed **stage** mixed into a match percentage is not necessarily a skill signal. That is the contamination detector: Huber on stage scores, reconstruct a robust match total in the same space as published match points, then

```
gap = ln(S_actual) - ln(S_robust)     # large negative ⇒ one/two stages ate the match
```

`η_contam(gap)` enters `R_obs` / `Q_i`. The mean link is untouched.

## Recommended Order



### 1. Asymmetric mean factor at match level (smallest change)

Keep the mean link `E[ln(X_i/X_j)] = R_i - R_j`. Change the weight.

Option A — one-sided Student-t:

```
w_down(z) = 1           if z >= 0
w_down(z) = w_t(z)      if z < 0, maybe with a lower c_t on the downside
```

Option B — extra observation variance on negative innovations only (more in-family with `η(S)`):

```
η_down(e) = ξ_down² · max(0, -e)² / T     (or a Huber hinge)
R_obs ← R_obs + η_down
```

Ontology: do not deform the identity; express skepticism in `R_obs` and `Q_i`. Positive residuals keep full Kalman credit. Moderate negative residuals (the 83% GM) get treated as a less precise instrument.

Repeated negative residuals must still move the mean. Trend/Shock must still allow real decline. Do not build a "GMs can't fall" trap. Elo's bomb protection is one-event `K` reduction, not `K = 0`.

### 2. Stage-contamination detector, still match-level updates (best model of the failure mode)

Huber on this shooter's stage scores (one-sided: only shrink stages *below* their own center). Reconstruct a robust match total in the same additive space the sport uses for match points — USPSA-style stage points if we have them, raw seconds for time-plus — then convert to a ratio and compare to the un-Hubered rebuild.

A GM who is evenly 8% slow across all stages: Huber weights stay ~1, `gap ≈ 0`, full update. A GM who is 95% on seven and zero on one: the zero is downweighted, `S_robust` looks like the other seven, `gap` is largely negative, `η_contam` fires.

Do not use one-sided Student-t as a substitute. The moderate one-stage bomb is still `|z| ≈ 2`–`2.5` at match level; a tighter downside `c_−` would also nibble evenly below-par matches, which are skill. The detector distinguishes those; `t` cannot.

Pseudocode: [Huber on stage scores](#huber-on-stage-scores).

### 3. By-stage LLR (after ~10× and a SV retune)

Would give Elo's dilution for free, with a cleaner mean. Needs separate (larger) SV, rates scaled by `~1/n`, a real zero/DNF policy, stage-size weights, *and* a downside factor because 80% stages are common. Do not do this until (1) or (2) is measured. If contamination-aware match updates close most of the Elo gap, by-stage can wait on performance.

## What Not To Copy

Do not copy Elo's elite gate. "Only good shooters get protection" is the least justified part of Elo relative to the feature as stated. A consistent B-class who DQs one stage has the same contamination process. LLR's `z`-score is the right *who*: anyone whose residual is large relative to *their* `T_i`. The miss is the *when* and the *sign*.

Do not treat Elo bomb protection as the target shape. It is an Obvious Rules Patch on a `K`-system that also suffers winner's curse. LLR already removed the curse. Native objects: `z`, `Q_i`, and (if precise) a stage-contamination gap.

## Counterarguments To Keep In Mind

**LLR is not empty-handed.** Extreme disasters are already handled. The live gap is the moderate, stage-local bomb that still looks like a mid-80s match.

**Over-protecting the downside will stick elites.** Three consecutive 8% below-par matches *is* skill change. Any one-sided factor needs to leave Trend/Shock able to commit after a few events. Student-t already has this split (damp mean, keep Shock); an asymmetric factor should keep it.

**Prediction and update are already inconsistent.** EVT assumes downside-dominated, upside-bounded noise; the filter assumes `ε_i ~ N(0, σ²)`. An asymmetric update without a matching predictive draw will help leaderboards and maybe next-match point estimates, and can hurt calibration. If `η_down` is added, decide whether predictive `σ` also becomes two-piece. Start with update-only; measure CRPS / 1σ coverage on "previous match was a bomb" slices.

**Match-level LLR gets points weighting right.** That is a real advantage over naive per-stage. A contamination detector should stay points-weighted so a zero on a 150-pt field course is not treated like a zero on a 50-pt classifier.

## Measurement Slice

When this gets implemented, do not only look at overall CRPS. Slice on:

- Previous match residual largely explained by 1–2 stages (contamination cohort)
- Previous match evenly below par (true-decline cohort)
- Above-par matches (must not lose upside signal)
- Next-match recovery of known GMs after a one-stage DNF

Elo winning the first slice and not the second is the expected signature if this note is right.

## Huber on Stage Scores

Goal: from one shooter's `RelativeMatchScore` (and, if needed, the rest of the field's stage scores), produce `S_actual` and `S_robust` in **the same ratio space**, then

```
gap = ln(max(ε, S_actual)) - ln(max(ε, S_robust))
η_contam = ξ_c² · max(0, −gap)²     # or a hinge past a small dead zone
```

Detection of "this stage is unlike the others" always happens in **stage-ratio space** (higher-is-better, `s_k ∈ (ε, 1]`). Reconstruction of the robust match total happens in the sport's **additive match space**: points for relative-stage-finish, seconds for cumulative time-plus. That way a 20 s disaster costs 20 s on an IDPA match regardless of which stage it was, and a zero on a 150-pt USPSA field course costs more than a zero on a 50-pt classifier — when we know those weights.

We cannot assume `stage.maxPoints > 0` (IDPA/ICORE HTML often has 0; some sports have no points concept). Time-plus does not need it: one second is one second. Hit-factor / relative-finish falls back to equal-weight ratios when values are missing.

One-sided Huber: only shrink stages with `s_k < μ`. A hot stage is not contamination; two-sided shrinking would pull `S_robust` down and understate a bomb-plus-heater.

Disable below `n_min` stages (4 is a reasonable floor). MAD is nonsense on 2–3 stages.

```
ε = 0.01                          # same score floor as LLR
c_huber = 1.5                     # or reuse baselineRobustnessZ
n_min = 4

function stage_weight(stage, scoring_mode):
    # Return a nonnegative weight used only for (a) estimating μ/MAD
    # and (b) relative-finish reconstruction. Time-plus reconstruction
    # ignores this: the match sum is unweighted seconds.
    if scoring_mode == RELATIVE_FINISH:
        if stage.maxPoints > 0: return stage.maxPoints
        if match.fixedStageValue != null: return match.fixedStageValue
        if stage.minRounds > 0: return stage.minRounds      # weak proxy
        return 1.0                                          # equal-weight fallback
    if scoring_mode == TIME_PLUS:
        return 1.0                                          # equal in ratio space
    return 1.0

function stage_ratio(stage_score):
    # RelativeStageScore.ratio is already higher-is-better vs the stage winner
    # for both hit-factor and time-plus.
    return clamp(stage_score.ratio, ε, 1.0)

function winning_time(stage, field_stage_scores):
    # Time-plus DNF/zero: s_k = 0, t_k = 0, cannot recover T_win from the
    # shooter. Pull it from anyone who finished the stage (ratio == 1
    # ⇒ their .points is T_win), or from T_win ≈ s_j * t_j on any
    # non-DNF shooter.
    for other in field_stage_scores[stage]:
        if other.ratio >= 1.0 - 1e-9 and other.points > 0:
            return other.points
    for other in field_stage_scores[stage]:
        if other.ratio > ε and other.points > 0:
            return other.points * other.ratio   # s = T_win/T ⇒ T_win = s·T
    return null

function huber_stage_match(match_score, field_scores, scoring_mode):
    stages = match_score.stageScores.values
        .where(ss => not ignored_scoring(ss.stage))
    n = len(stages)
    if n < n_min:
        return (S_actual: match_score.ratio, S_robust: match_score.ratio, gap: 0)

    s[k] = stage_ratio(stages[k])
    w_size[k] = stage_weight(stages[k].stage, scoring_mode)

    # Center / scale in log-ratio space so a 50% vs 90% is the same
    # distance regardless of stage length.
    L[k] = ln(s[k])
    μ_L = weighted_median(L, weights=w_size)          # or unweighted median
    σ_L = 1.4826 * weighted_mad(L, μ_L, weights=w_size)
    σ_L = max(σ_L, ln(1.05))                          # floor: don't Huber noise

    # One-sided Huber weights: full credit at or above center.
    for k in stages:
        z[k] = (L[k] - μ_L) / σ_L
        if z[k] >= 0:
            h[k] = 1.0
        else:
            h[k] = min(1.0, c_huber / abs(z[k]))

        # Shrink the ratio toward exp(μ_L); h=1 leaves it alone, h=0 replaces
        # the stage with the shooter's typical stage ratio.
        s_shrunk[k] = exp(h[k] * L[k] + (1 - h[k]) * μ_L)

    if scoring_mode == RELATIVE_FINISH:
        # Additive match space = stage points. Winner's published match
        # points keep S in the same space as match_score.ratio.
        # When all w_size are the equal-weight fallback, this is an
        # equal-weight ratio average — rebuild S_actual the same way
        # rather than mixing with published (possibly points-weighted) ratio.
        have_real_weights = any(stage.maxPoints > 0) or match.fixedStageValue != null
        for k in stages:
            p_actual[k]  = w_size[k] * s[k]
            p_robust[k]  = w_size[k] * s_shrunk[k]
        P_actual = sum(p_actual)
        P_robust = sum(p_robust)

        if have_real_weights and winner_match_points > 0:
            S_actual  = P_actual / winner_match_points     # ≈ match_score.ratio
            S_robust  = P_robust / winner_match_points
        else:
            W = sum(w_size)
            S_actual  = P_actual / W                       # equal-weight rebuild
            S_robust  = P_robust / W

    if scoring_mode == TIME_PLUS:
        # Additive match space = seconds. Detection used ratios; the sum
        # does not re-weight by stage size. One second is one second.
        μ_s = exp(μ_L)
        for k in stages:
            t[k] = stages[k].points                       # cumulative interpret()
            if s[k] > ε and t[k] > 0:
                # T_win_k = s_k * t_k; t_shrunk = T_win / s_shrunk
                t_shrunk[k] = t[k] * (s[k] / s_shrunk[k])
            else:
                # DNF / zero: no usable t_k. Substitute the time implied
                # by this shooter's typical ratio against the field's T_win.
                T_win = winning_time(stages[k].stage, field_scores)
                if T_win == null:
                    t_shrunk[k] = t[k]                    # give up on this stage
                else:
                    t_shrunk[k] = T_win / μ_s

        # Published match time is match_score.points (sum of interpret()).
        # Rebuild T_actual the same way, substituting DNF zeros with the
        # pre-shrink t[k] (usually 0) so only Hubered times move T_robust.
        T_actual = match_score.points
        T_robust = sum(t_shrunk)
        T_win_match = winner_match_time                  # field's best total
        if T_win_match > 0 and T_actual > 0 and T_robust > 0:
            S_actual = T_win_match / T_actual            # ≈ match_score.ratio
            S_robust = T_win_match / T_robust
        else:
            S_actual = match_score.ratio
            S_robust = match_score.ratio

    gap = ln(max(ε, S_actual)) - ln(max(ε, S_robust))
    return (S_actual, S_robust, gap)
```

Notes:

- **Same-space rebuild.** Always compare Hubered vs un-Hubered totals built with the *same* weights and the *same* winner denominator. Do not compare a published `match_score.ratio` to an equal-weight robust average; the winner-didn't-sweep and missing-`maxPoints` cases will invent a gap.
- **Time-plus DNF.** `RelativeStageScore.points` is 0 and `ratio` is 0. Recover `T_win` from the field (see `winning_time`). The rater already has every competitor's `RelativeMatchScore` in `matchScores`, so this is free. Only substitute an implied time into `T_robust` if that disaster is already in `T_actual` (large finite time). If a stage DNF is stored as 0 and omitted from the match sum, substituting a real time makes `T_robust > T_actual`, `gap > 0`, and this detector correctly does not fire — that is optimistic published scoring or a match DNF (`ratio ≈ 0`), which tail noise / Student-t already handle. The usual time-plus bomb is a large finite time; `t_shrunk = t · (s / s_shrunk)` is the path that matters.
- **Fixed-time USPSA stages.** `pointsAreUSPSAFixedTime`: stage points are raw points, not `maxPoints * ratio`. For detection, `ratio` is still the right outlier scale. For reconstruction, shrink in *points* toward `μ_s * stage_winner_points`, or treat them like relative-finish with `w_size = stage.maxPoints` and `s = points / winner_points` on that stage. Do not mix a 0.40 ratio with a 40-pt raw score in the same sum.
- **Dead zone.** A single 80% stage among 90s is common and *is* a stage, not a match bomb. `σ_L` floor plus `c_huber ≈ 1.5` should leave `h ≈ 1`. If `η_contam` still nibble-fires, put a hinge on `gap` (ignore `|gap| < ln(1.03)` or similar) rather than tightening Huber until it misses zeros.
- **Where it plugs in.** `η_contam` is a reliability term: add it to `R_obs` next to tail / weak-field / novelty so `Q_i` strips it from momentum, dispersion, and Shock. Do not replace `O_i` with the robust score. The published match is still the observation; we only say it is a less precise instrument.
- **Student-t stays on the match innovation** after this, possibly one-sided. It is the backstop for "every stage was a catastrophe," which Huber will *not* call contamination (`gap ≈ 0` when all stages are equally terrible).

