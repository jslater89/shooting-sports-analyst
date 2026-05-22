# Career trajectory plots

Long-format CSV is produced by the CFA oneoff (`Trajectory CSV path` in the menu, or the last CLI argument to `CFA`).

## Generate data

From repo root (empty strings skip summary/compare; trajectory-only export):

```bash
dart run bin/db_oneoffs.dart CFA "L2s Main LLR" 3 8 4 2018 "" "" /tmp/llr_trajectories.csv
```

The file has one row per `(rating group, shooter, calendar year)` with at least two active years in the series. Filter to Carry Optics in Python with `--group CO` (substring match on the `group` column).

## Plot

```bash
pip install -r research/career-trajectories/requirements.txt
python research/career-trajectories/plot_career_trajectories.py /tmp/llr_trajectories.csv \
  --group CO --y field_adj --x career_age \
  --highlight improvePlateauDecline --highlight declineTroughAtEnd \
  -o /tmp/co_trajectories.png
```

- `--y rating_display` plots end-of-year display rating; `field_adj` plots vs group median that year (same construction as CFA console).
- `--highlight` may be repeated; each category is drawn on top of the faint “all shooters” cloud. Names match the `trajectory` column (Dart enum names, e.g. `improvePeakAtEnd`, `declineThenRiseAboveStart`, `improveThenFallBelowStart`).
- `--list-categories` prints trajectory counts for the `--group` filter and exits.
