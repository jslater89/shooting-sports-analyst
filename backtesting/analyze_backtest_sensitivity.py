#!/usr/bin/env python3
"""
Analyze paired backtest_params_*.json + backtest_results_*.csv artifacts.

Focus: sensitivity of forecast metrics to LLR (or other) numeric settings when
you hand-sweep parameters — correlations across runs and pairwise slopes when
exactly one setting differs between two runs.

Usage:
  python analyze_backtest_sensitivity.py
  python analyze_backtest_sensitivity.py --runs-dir /path/to/backtesting
  python analyze_backtest_sensitivity.py --algorithm LLR --mode rated-only
  python analyze_backtest_sensitivity.py --metric crps_top40 crps_overall cov1_top40

Metric names use ``{stat}_{scope}`` with scope ``top40`` (rating-quintile
top two buckets) or ``overall`` (CSV overall row). Legacy ``overall_*`` CLI
names are still accepted as aliases.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


# ---------------------------------------------------------------------------
# Metric extraction from CSV (schema from backtest_raters_command.dart)
# ---------------------------------------------------------------------------

RATING_TOP_BUCKETS = ("top 20%", "20-40%")
FINISH_TOP_BUCKETS = ("top 20%", "20-40%")


def _find_row(
    rows: list[dict[str, str]],
    *,
    scope: str,
    mode: str,
    algorithm: str,
    bucket: str,
) -> dict[str, str] | None:
    for r in rows:
        if (
            r.get("scope") == scope
            and r.get("mode") == mode
            and r.get("algorithm") == algorithm
            and r.get("bucket") == bucket
        ):
            return r
    return None


def _f(row: dict[str, str], key: str) -> float:
    v = row.get(key, "").strip()
    if v == "":
        return math.nan
    return float(v)


def _i(row: dict[str, str], key: str) -> int:
    return int(row[key])


def weighted_top40_crps(
    rows: list[dict[str, str]],
    *,
    algorithm: str,
    mode: str,
    scope: str = "rating_quintile",
) -> tuple[float, int, float | None, float | None]:
    """
    n-weighted CRPS over top 20% + 20–40% buckets (predicted-rank quintiles).
    Returns (crps_top40, n_total, crps_top20, crps_q2).
    """
    b1 = RATING_TOP_BUCKETS[0]
    b2 = RATING_TOP_BUCKETS[1]
    r1 = _find_row(rows, scope=scope, mode=mode, algorithm=algorithm, bucket=b1)
    r2 = _find_row(rows, scope=scope, mode=mode, algorithm=algorithm, bucket=b2)
    if r1 is None or r2 is None:
        return math.nan, 0, None, None
    n1, n2 = _i(r1, "n"), _i(r2, "n")
    if n1 + n2 == 0:
        return math.nan, 0, None, None
    c1, c2 = _f(r1, "crps"), _f(r2, "crps")
    top40 = (n1 * c1 + n2 * c2) / (n1 + n2)
    return top40, n1 + n2, c1, c2


def weighted_top40_coverage(
    rows: list[dict[str, str]],
    *,
    algorithm: str,
    mode: str,
    scope: str = "rating_quintile",
) -> tuple[float, float]:
    """n-weighted mean coverage_1sigma and coverage_2sigma for top-40 buckets."""
    b1, b2 = RATING_TOP_BUCKETS
    r1 = _find_row(rows, scope=scope, mode=mode, algorithm=algorithm, bucket=b1)
    r2 = _find_row(rows, scope=scope, mode=mode, algorithm=algorithm, bucket=b2)
    if r1 is None or r2 is None:
        return math.nan, math.nan
    n1, n2 = _i(r1, "n"), _i(r2, "n")
    if n1 + n2 == 0:
        return math.nan, math.nan
    cov1 = (n1 * _f(r1, "coverage_1sigma") + n2 * _f(r2, "coverage_1sigma")) / (n1 + n2)
    cov2 = (n1 * _f(r1, "coverage_2sigma") + n2 * _f(r2, "coverage_2sigma")) / (n1 + n2)
    return cov1, cov2


def overall_metrics(
    rows: list[dict[str, str]],
    *,
    algorithm: str,
    mode: str,
) -> dict[str, float]:
    r = _find_row(rows, scope="overall", mode=mode, algorithm=algorithm, bucket="")
    if r is None:
        return {}
    return {
        "n_overall": float(_i(r, "n")),
        "mape_overall": _f(r, "mape"),
        "crps_overall": _f(r, "crps"),
        "rank_mae_overall": _f(r, "rank_mae"),
        "cov1_overall": _f(r, "coverage_1sigma"),
        "cov2_overall": _f(r, "coverage_2sigma"),
    }


# ---------------------------------------------------------------------------
# Params from JSON
# ---------------------------------------------------------------------------

# CLI / internal metric keys: ``{stat}_{top40|overall}``. Values are aliases → canonical.
METRIC_ALIASES: dict[str, str] = {
    "overall_crps": "crps_overall",
    "overall_mape": "mape_overall",
    "overall_rank_mae": "rank_mae_overall",
    "overall_coverage_1sigma": "cov1_overall",
    "overall_coverage_2sigma": "cov2_overall",
    "overall_n": "n_overall",
}


def normalize_metric_names(names: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(METRIC_ALIASES.get(n, n) for n in names))


SHORT_PARAM_LABELS: dict[str, str] = {
    "latentLogSurpriseAdaptationRate": "gamma",
    "latentLogMomentumAdaptationRate": "lambda_m",
    "latentLogPredictionBehavioralVolatilityKappa": "kappa_pred",
    "latentLogPredictionSportVariance": "pred_sv_add",
    "latentLogVolatilityAdaptationRate": "disp_adapt",
    "latentLogSportVolatility": "sport_vol",
    "latentLogSkillDriftRate": "skill_drift",
    "latentLogStartingVariance": "start_var",
    "latentLogMaximumVariance": "max_var",
    "latentLogStartingDispersion": "start_disp",
    "latentLogStudentTCutoffZ": "student_t_z",
    "latentLogWeakFieldVariance": "wf_omega",
    "latentLogNoveltyVariance": "novelty_psi",
}


def numeric_settings(settings: dict[str, Any]) -> dict[str, float]:
    out: dict[str, float] = {}
    for k, v in settings.items():
        if isinstance(v, bool):
            continue
        if isinstance(v, int) and not isinstance(v, bool):
            out[k] = float(v)
        elif isinstance(v, float):
            out[k] = v
    return out


def load_run_pair(params_path: Path) -> tuple[dict[str, Any], list[dict[str, str]]]:
    with params_path.open(encoding="utf-8") as f:
        payload = json.load(f)
    csv_name = payload.get("csv_file")
    if not csv_name:
        raise ValueError(f"No csv_file in {params_path}")
    csv_path = params_path.parent / csv_name
    if not csv_path.is_file():
        raise FileNotFoundError(csv_path)
    with csv_path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    return payload, rows


def discover_param_files(runs_dir: Path) -> list[Path]:
    return sorted(runs_dir.glob("backtest_params_*.json"))


# ---------------------------------------------------------------------------
# Statistics (stdlib only)
# ---------------------------------------------------------------------------

def pearson(xs: list[float], ys: list[float]) -> float:
    n = len(xs)
    if n < 2 or n != len(ys):
        return math.nan
    mx = sum(xs) / n
    my = sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    deny = math.sqrt(sum((y - my) ** 2 for y in ys))
    if denx == 0 or deny == 0:
        return math.nan
    return num / (denx * deny)


def spearman(xs: list[float], ys: list[float]) -> float:
    def ranks(vals: list[float]) -> list[float]:
        indexed = sorted(range(len(vals)), key=lambda i: vals[i])
        r = [0.0] * len(vals)
        i = 0
        while i < len(indexed):
            j = i
            while j + 1 < len(indexed) and vals[indexed[j + 1]] == vals[indexed[i]]:
                j += 1
            avg_rank = (i + j) / 2.0 + 1.0
            for k in range(i, j + 1):
                r[indexed[k]] = avg_rank
            i = j + 1
        return r

    if len(xs) < 2:
        return math.nan
    return pearson(ranks(xs), ranks(ys))


# ---------------------------------------------------------------------------
# Run record + sensitivity
# ---------------------------------------------------------------------------

@dataclass
class RunRecord:
    timestamp: str
    params_path: Path
    settings: dict[str, float] = field(default_factory=dict)
    metrics: dict[str, float] = field(default_factory=dict)


def build_records(
    runs_dir: Path,
    *,
    algorithm: str,
    mode: str,
) -> list[RunRecord]:
    records: list[RunRecord] = []
    for p in discover_param_files(runs_dir):
        try:
            payload, rows = load_run_pair(p)
        except (OSError, ValueError, json.JSONDecodeError) as e:
            print(f"skip {p.name}: {e}", file=sys.stderr)
            continue
        algo_cfg = payload.get("algorithm_settings", {}).get(algorithm)
        if not algo_cfg:
            print(f"skip {p.name}: no settings for {algorithm}", file=sys.stderr)
            continue
        settings_raw = algo_cfg.get("settings") or {}
        settings = numeric_settings(settings_raw)

        top40, _, _, _ = weighted_top40_crps(rows, algorithm=algorithm, mode=mode)
        cov1, cov2 = weighted_top40_coverage(rows, algorithm=algorithm, mode=mode)
        overall = overall_metrics(rows, algorithm=algorithm, mode=mode)

        metrics = {
            "crps_top40": top40,
            "cov1_top40": cov1,
            "cov2_top40": cov2,
            **overall,
        }
        ts = payload.get("timestamp") or p.stem.replace("backtest_params_", "")
        records.append(
            RunRecord(
                timestamp=str(ts),
                params_path=p,
                settings=settings,
                metrics=metrics,
            )
        )
    return records


def count_confounded_pairs(records: list[RunRecord]) -> int:
    """Pairs of runs that differ in two or more numeric settings (not clean 1D steps)."""
    sorted_recs = sorted(records, key=lambda r: r.timestamp)
    n = 0
    for i, a in enumerate(sorted_recs):
        for b in sorted_recs[i + 1 :]:
            all_keys = set(a.settings) & set(b.settings)
            diff_keys = [k for k in all_keys if a.settings[k] != b.settings[k]]
            if len(diff_keys) > 1:
                n += 1
    return n


def pairwise_single_param_slopes(
    records: list[RunRecord],
    *,
    metric_key: str,
) -> list[dict[str, Any]]:
    """
    For each pair of runs, if exactly one numeric setting differs, record
    Δmetric/Δparam (signed, from lower timestamp to higher for tie-break).
    """
    events: list[dict[str, Any]] = []
    sorted_recs = sorted(records, key=lambda r: r.timestamp)
    for i, a in enumerate(sorted_recs):
        for b in sorted_recs[i + 1 :]:
            keys_a = set(a.settings)
            keys_b = set(b.settings)
            all_keys = sorted(keys_a & keys_b)
            diff_keys = [k for k in all_keys if a.settings[k] != b.settings[k]]
            if len(diff_keys) != 1:
                continue
            k = diff_keys[0]
            da = a.metrics.get(metric_key, math.nan)
            db = b.metrics.get(metric_key, math.nan)
            pa = a.settings[k]
            pb = b.settings[k]
            if math.isnan(da) or math.isnan(db) or pa == pb:
                continue
            slope = (db - da) / (pb - pa)
            events.append(
                {
                    "param": k,
                    "short": SHORT_PARAM_LABELS.get(k, k),
                    "run_a": a.timestamp,
                    "run_b": b.timestamp,
                    "delta_param": pb - pa,
                    "delta_metric": db - da,
                    "slope": slope,
                    "v_a": pa,
                    "v_b": pb,
                }
            )
    return events


def correlation_table(
    records: list[RunRecord],
    *,
    metric_key: str,
) -> list[tuple[str, str, float, float, int]]:
    """
    (param_key, short_label, pearson_r, spearman_rho, n_distinct)
    Only params with ≥2 distinct values; correlation needs ≥2 points (returns nan if not).
    """
    ys = [r.metrics.get(metric_key, math.nan) for r in records]
    rows_out: list[tuple[str, str, float, float, int]] = []
    all_keys: set[str] = set()
    for r in records:
        all_keys |= set(r.settings.keys())
    for k in sorted(all_keys):
        xs = [r.settings.get(k, math.nan) for r in records]
        pairs = [(x, y) for x, y in zip(xs, ys) if not math.isnan(x) and not math.isnan(y)]
        if len(pairs) < 2:
            continue
        xv = [p[0] for p in pairs]
        yv = [p[1] for p in pairs]
        n_distinct = len(set(xv))
        label = SHORT_PARAM_LABELS.get(k, k)
        rows_out.append(
            (
                k,
                label,
                pearson(xv, yv),
                spearman(xv, yv),
                n_distinct,
            )
        )
    return rows_out


def print_summary_table(records: list[RunRecord], *, metric_keys: list[str]) -> None:
    priority_keys = [
        "latentLogSurpriseAdaptationRate",
        "latentLogMomentumAdaptationRate",
        "latentLogPredictionBehavioralVolatilityKappa",
        "latentLogPredictionSportVariance",
        "latentLogVolatilityAdaptationRate",
    ]
    headers = ["timestamp"] + [SHORT_PARAM_LABELS.get(k, k) for k in priority_keys]
    headers.extend(metric_keys)
    if "crps_overall" not in metric_keys:
        headers.append("crps_overall")
    if "cov1_overall" not in metric_keys:
        headers.append("cov1_overall")
    print("\n=== Summary (selected columns) ===")
    print(",".join(headers))
    for r in sorted(records, key=lambda x: x.timestamp):
        row = [r.timestamp]
        for k in priority_keys:
            v = r.settings.get(k, math.nan)
            row.append("" if math.isnan(v) else f"{v:.6g}")
        for mk in metric_keys:
            m = r.metrics.get(mk, math.nan)
            row.append("" if math.isnan(m) else f"{m:.6f}")
        if "crps_overall" not in metric_keys:
            oc = r.metrics.get("crps_overall", math.nan)
            row.append("" if math.isnan(oc) else f"{oc:.6f}")
        if "cov1_overall" not in metric_keys:
            o1 = r.metrics.get("cov1_overall", math.nan)
            row.append("" if math.isnan(o1) else f"{o1:.4f}")
        print(",".join(row))


def print_pairwise(events: list[dict[str, Any]], *, metric_key: str) -> None:
    print(f"\n=== Pairwise single-parameter changes (Δ{metric_key}/Δparam) ===")
    if not events:
        print("(no pairs with exactly one numeric setting difference)")
        return
    by_param: dict[str, list[dict[str, Any]]] = {}
    for e in events:
        by_param.setdefault(e["param"], []).append(e)
    for param in sorted(by_param.keys()):
        short = SHORT_PARAM_LABELS.get(param, param)
        evs = by_param[param]
        slopes = [e["slope"] for e in evs if not math.isnan(e["slope"])]
        mean_s = sum(slopes) / len(slopes) if slopes else math.nan
        print(f"\n{param} ({short})  n_pairs={len(evs)}  mean_slope={mean_s:.6g}")
        for e in sorted(evs, key=lambda x: (x["run_a"], x["run_b"])):
            print(
                f"  {e['run_a']} → {e['run_b']}: "
                f"param {e['v_a']:.6g}→{e['v_b']:.6g}  "
                f"Δmetric={e['delta_metric']:.6g}  slope={e['slope']:.6g}"
            )


def print_correlations(corr_rows: list[tuple[str, str, float, float, int]], *, metric_key: str) -> None:
    print(f"\n=== Correlation with {metric_key} (all numeric settings) ===")
    print("param_short  n_distinct  pearson_r  spearman_rho")
    ranked = sorted(
        corr_rows,
        key=lambda t: (abs(t[3]) if not math.isnan(t[3]) else -1.0, abs(t[2])),
        reverse=True,
    )
    for _k, label, pr, sr, nd in ranked:
        if nd < 2:
            continue
        print(
            f"{label:14}  {nd:3d}      "
            f"{('nan' if math.isnan(pr) else f'{pr: .4f}'):>8}  "
            f"{('nan' if math.isnan(sr) else f'{sr: .4f}'):>8}"
        )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--runs-dir",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Directory containing backtest_params_*.json and CSVs",
    )
    ap.add_argument("--algorithm", default="LLR", help="Algorithm key in JSON")
    ap.add_argument(
        "--mode",
        default="rated-only",
        choices=["rated-only", "all"],
        help="CSV mode column filter",
    )
    ap.add_argument(
        "--metric",
        dest="metrics",
        nargs="+",
        default=["crps_top40"],
        metavar="NAME",
        help=(
            "One or more metrics for the summary table; each also gets its own "
            "pairwise-slope and correlation sections. Canonical names: crps_top40, "
            "cov1_top40, cov2_top40, crps_overall, cov1_overall, cov2_overall, "
            "mape_overall, rank_mae_overall, n_overall. Legacy aliases "
            "(e.g. overall_crps, overall_coverage_1sigma) are accepted. Example: "
            "--metric crps_top40 crps_overall cov1_top40"
        ),
    )
    args = ap.parse_args()
    metrics = normalize_metric_names(args.metrics)
    runs_dir: Path = args.runs_dir
    if not runs_dir.is_dir():
        print(f"Not a directory: {runs_dir}", file=sys.stderr)
        sys.exit(1)

    records = build_records(runs_dir, algorithm=args.algorithm, mode=args.mode)
    if not records:
        print("No runs loaded.", file=sys.stderr)
        sys.exit(2)

    print(f"Loaded {len(records)} run(s) from {runs_dir}")
    confounded = count_confounded_pairs(records)
    total_pairs = len(records) * (len(records) - 1) // 2
    print(
        f"Run pairs with >1 param change: {confounded} / {total_pairs} "
        "(those do not appear in pairwise slopes)"
    )
    print_summary_table(records, metric_keys=metrics)

    for mk in metrics:
        events = pairwise_single_param_slopes(records, metric_key=mk)
        print_pairwise(events, metric_key=mk)

        corr_rows = correlation_table(records, metric_key=mk)
        print_correlations(corr_rows, metric_key=mk)


if __name__ == "__main__":
    main()
