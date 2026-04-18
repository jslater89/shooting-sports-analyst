#!/usr/bin/env python3
"""
Parse shooting-sports-analyst backtest console output (e.g. chart-data.txt)
and emit tidy CSV plus optional matplotlib figures for blog posts.

Generates parallel figures for both scoring modes when data is present:
  - mode=all: full registration in each rating group
  - mode=rated-only: re-scored subset of competitors with a prior rating

Usage (from repo root):
  python3 research/latent-log-ratio/plot_chart_data.py \\
    research/latent-log-ratio/chart-data.txt --out-dir ./figures

Requires: matplotlib, numpy (see requirements-plot.txt in this directory)
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# --- parser -----------------------------------------------------------------

SECTION_RE = re.compile(r"^=== (.+) ===\s*$")
OVERALL_LINE_RE = re.compile(
    r"^(Elo|Glicko|LLR)\s+"
    r"n=(\d+)\s+"
    r"MAPE=([\d.]+)%\s+"
    r"MPE=([+-]?[\d.]+)%\s+"
    r"MPE\(arith\)=([+-]?[\d.]+)%\s+"
    r"MAE=([\d.]+)\s+"
    r"CRPS=([\d.]+)\s+"
    r"RankMAE=([\d.]+)\s+places\s+"
    r"1σ coverage=([\d.]+)%.*?"
    r"2σ coverage=([\d.]+)%",
    re.DOTALL,
)
BUCKET_LINE_RE = re.compile(
    r"^\s+"
    r"(top 20%|20-40%|40-60%|60-80%|bottom 20%)\s+"
    r"n=\s*(\d+)\s+"
    r"MPE=\s*([+-]?[\d.]+)%\s+"
    r"MPE\(arith\)=\s*([+-]?[\d.]+)%\s+"
    r"MAPE=\s*([\d.]+)%\s+"
    r"MAE=([\d.]+)\s+"
    r"CRPS=([\d.]+)\s+"
    r"RankMAE=\s*([\d.]+)\s+"
    r"1σ=\s*([\d.]+)%\s+"
    r"2σ=\s*([\d.]+)%\s*$"
)
ALGO_HEADER_RE = re.compile(r"^(Elo|Glicko|LLR):\s*$")

BUCKET_ORDER = ["top 20%", "20-40%", "40-60%", "60-80%", "bottom 20%"]
BUCKET_SHORT = ["Q1 (top)", "Q2", "Q3", "Q4", "Q5 (bottom)"]

MODES = ("all", "rated-only")


@dataclass
class Row:
    section: str
    bucket_axis: str
    mode: str
    algorithm: str
    bucket: str
    n: int
    mape: float
    mpe: float
    mpe_arith: float
    mae: float
    crps: float
    rank_mae: float
    coverage1: float
    coverage2: float


def infer_axis_mode(section: str) -> tuple[str, str]:
    """Returns (bucket_axis, mode_label)."""
    s = section.lower()
    mode = ""
    if "mode=rated-only" in s or "mode=rated only" in s:
        mode = "rated-only"
    elif "mode=all" in s:
        mode = "all"

    axis = ""
    if "bucketed by actual finish" in s:
        axis = "actual_finish"
    elif "predicted rank" in s or "rating)" in s:
        axis = "predicted_rank"

    return axis, mode


def parse_chart_data(text: str) -> list[Row]:
    rows: list[Row] = []
    current_section = ""
    current_algo = ""

    for line in text.splitlines():
        m_sec = SECTION_RE.match(line)
        if m_sec:
            current_section = m_sec.group(1).strip()
            current_algo = ""
            continue

        m_overall = OVERALL_LINE_RE.match(line.strip())
        if m_overall and "Per algorithm (overall)" in current_section:
            algo, n, mape, mpe, mpe_a, mae, crps, rank_mae, c1, c2 = m_overall.groups()
            axis, mode = infer_axis_mode(current_section)
            rows.append(
                Row(
                    section=current_section,
                    bucket_axis="",
                    mode=mode,
                    algorithm=algo,
                    bucket="overall",
                    n=int(n),
                    mape=float(mape),
                    mpe=float(mpe),
                    mpe_arith=float(mpe_a),
                    mae=float(mae),
                    crps=float(crps),
                    rank_mae=float(rank_mae),
                    coverage1=float(c1),
                    coverage2=float(c2),
                )
            )
            continue

        m_algo = ALGO_HEADER_RE.match(line)
        if m_algo:
            current_algo = m_algo.group(1)
            continue

        m_b = BUCKET_LINE_RE.match(line)
        if m_b and current_algo:
            b, n, mpe, mpe_a, mape, mae, crps, rank_mae, c1, c2 = m_b.groups()
            axis, mode = infer_axis_mode(current_section)
            rows.append(
                Row(
                    section=current_section,
                    bucket_axis=axis,
                    mode=mode,
                    algorithm=current_algo,
                    bucket=b.strip(),
                    n=int(n),
                    mape=float(mape),
                    mpe=float(mpe),
                    mpe_arith=float(mpe_a),
                    mae=float(mae),
                    crps=float(crps),
                    rank_mae=float(rank_mae),
                    coverage1=float(c1),
                    coverage2=float(c2),
                )
            )

    return rows


def rows_to_csv(rows: list[Row], path: Path) -> None:
    fieldnames = [
        "section",
        "bucket_axis",
        "mode",
        "algorithm",
        "bucket",
        "n",
        "mape_pct",
        "mpe_pct",
        "mpe_arith_pct",
        "mae",
        "crps",
        "rank_mae",
        "coverage_1sigma_pct",
        "coverage_2sigma_pct",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(
                {
                    "section": r.section,
                    "bucket_axis": r.bucket_axis,
                    "mode": r.mode,
                    "algorithm": r.algorithm,
                    "bucket": r.bucket,
                    "n": r.n,
                    "mape_pct": r.mape,
                    "mpe_pct": r.mpe,
                    "mpe_arith_pct": r.mpe_arith,
                    "mae": r.mae,
                    "crps": r.crps,
                    "rank_mae": r.rank_mae,
                    "coverage_1sigma_pct": r.coverage1,
                    "coverage_2sigma_pct": r.coverage2,
                }
            )


# --- plotting -----------------------------------------------------------------

COLORS = {"Elo": "#c44e52", "Glicko": "#8172b3", "LLR": "#55a868"}
IDEAL_1 = 68.27
IDEAL_2 = 95.45
ALGOS = ["Elo", "Glicko", "LLR"]


def _rows_filter(
    rows: list[Row],
    *,
    bucket_axis: str,
    mode: str,
) -> list[Row]:
    return [
        r
        for r in rows
        if r.bucket_axis == bucket_axis and r.mode == mode
    ]


def _mode_slug(mode: str) -> str:
    return "all_competitors" if mode == "all" else "rated_only"


def _mode_title(mode: str) -> str:
    return (
        "All competitors in group filters"
        if mode == "all"
        else "Rated competitors only (re-scored subset)"
    )


def plot_figures(rows: list[Row], out_dir: Path, dpi: int) -> None:
    import matplotlib.pyplot as plt
    import numpy as np

    out_dir.mkdir(parents=True, exist_ok=True)
    xs = np.arange(5)

    for mode in MODES:
        slug = _mode_slug(mode)
        mode_label = _mode_title(mode)

        # --- Overall: MAPE, MAE, CRPS ---
        overall = [r for r in rows if r.bucket == "overall" and r.mode == mode]
        if len(overall) < 3:
            print(
                f"Note: skipped overall_*_{slug}_*.png — need three algorithm rows "
                f"for mode={mode!r} in chart-data (found {len(overall)}). "
                "Paste both \"Per algorithm (overall) — mode=all\" and "
                "\"… mode=rated-only\" sections from the backtest output.",
                file=sys.stderr,
            )
        if len(overall) >= 3:
            by_algo = {r.algorithm: r for r in overall}
            if all(a in by_algo for a in ALGOS):
                fig, axes = plt.subplots(1, 3, figsize=(10, 3.8), constrained_layout=True)
                metrics = [
                    ("MAPE (%)", "mape"),
                    ("MAE (ratio)", "mae"),
                    ("CRPS", "crps"),
                ]
                x = np.arange(len(ALGOS))
                width = 0.6
                for ax, (title, attr) in zip(axes, metrics):
                    vals = [getattr(by_algo[a], attr) for a in ALGOS]
                    bars = ax.bar(
                        x,
                        vals,
                        width,
                        color=[COLORS[a] for a in ALGOS],
                        edgecolor="white",
                        linewidth=0.8,
                    )
                    ax.set_xticks(x, ALGOS)
                    ax.set_title(title, fontsize=11)
                    ax.spines["top"].set_visible(False)
                    ax.spines["right"].set_visible(False)
                    for b in bars:
                        h = b.get_height()
                        ax.annotate(
                            f"{h:.3f}" if attr != "mape" else f"{h:.1f}",
                            xy=(b.get_x() + b.get_width() / 2, h),
                            xytext=(0, 2),
                            textcoords="offset points",
                            ha="center",
                            va="bottom",
                            fontsize=8,
                        )
                fig.suptitle(
                    f"Backtest summary — {mode_label}",
                    fontsize=12,
                    fontweight="bold",
                )
                fig.savefig(
                    out_dir / f"overall_{slug}_mape_mae_crps.png",
                    dpi=dpi,
                )
                plt.close(fig)

                # Coverage — one multiline axis title (suptitle + constrained_layout
                # clipped the subtitle at the top of the canvas).
                fig, ax = plt.subplots(figsize=(6.5, 4.2), constrained_layout=True)
                w = 0.35
                c1s = [by_algo[a].coverage1 for a in ALGOS]
                c2s = [by_algo[a].coverage2 for a in ALGOS]
                ax.bar(
                    x - w / 2,
                    c1s,
                    w,
                    label="1σ coverage",
                    color="#8de4d5",
                    edgecolor="white",
                )
                ax.bar(
                    x + w / 2,
                    c2s,
                    w,
                    label="2σ coverage",
                    color="#44a8c8",
                    edgecolor="white",
                )
                ax.axhline(IDEAL_1, color="#333", linestyle="--", linewidth=1, alpha=0.7)
                ax.axhline(IDEAL_2, color="#666", linestyle=":", linewidth=1, alpha=0.7)
                ax.set_xticks(x, ALGOS)
                ax.set_ylabel("Empirical coverage (%)")
                ax.set_ylim(0, 105)
                ax.legend(loc="lower right", frameon=False)
                ax.set_title(
                    f"{mode_label}\n"
                    "Prediction interval coverage vs. nominal "
                    "(dashed ≈68%, dotted ≈95%)",
                    fontsize=10,
                    pad=12,
                )
                ax.spines["top"].set_visible(False)
                ax.spines["right"].set_visible(False)
                fig.savefig(
                    out_dir / f"overall_{slug}_coverage.png",
                    dpi=dpi,
                    bbox_inches="tight",
                    pad_inches=0.25,
                )
                plt.close(fig)

        # --- Predicted-rank quintiles ---
        pr = _rows_filter(rows, bucket_axis="predicted_rank", mode=mode)
        if pr:
            full = all(
                next((r for r in pr if r.algorithm == algo and r.bucket == b), None)
                for algo in ALGOS
                for b in BUCKET_ORDER
            )
            if not full:
                # Partial data still plot what we have
                pass

            fig, ax = plt.subplots(figsize=(8, 4), constrained_layout=True)
            for algo in ALGOS:
                pts = []
                for b in BUCKET_ORDER:
                    m = next((r for r in pr if r.algorithm == algo and r.bucket == b), None)
                    pts.append(m.mpe_arith if m else float("nan"))
                ax.plot(
                    xs,
                    pts,
                    marker="o",
                    linewidth=2,
                    label=algo,
                    color=COLORS[algo],
                )
            ax.axhline(0, color="#999", linestyle="-", linewidth=0.8)
            ax.set_xticks(xs, BUCKET_SHORT, rotation=15, ha="right")
            ax.set_ylabel("Mean percentage error (arith center) %")
            ax.set_title(
                f"Bias by predicted rating quintile — {mode_label}\n"
                "(positive = under-predicted realized ratio)",
                fontsize=11,
            )
            ax.legend(frameon=False, loc="best")
            ax.spines["top"].set_visible(False)
            ax.spines["right"].set_visible(False)
            fig.savefig(
                out_dir / f"predicted_rank_{slug}_mpe_arith.png",
                dpi=dpi,
            )
            plt.close(fig)

            fig, axes = plt.subplots(1, 2, figsize=(10, 3.8), constrained_layout=True)
            for axp, attr, title in zip(
                axes,
                ["mae", "crps"],
                ["MAE (ratio)", "CRPS"],
            ):
                for algo in ALGOS:
                    pts = []
                    for b in BUCKET_ORDER:
                        m = next((r for r in pr if r.algorithm == algo and r.bucket == b), None)
                        pts.append(getattr(m, attr) if m else float("nan"))
                    axp.plot(
                        xs,
                        pts,
                        marker="o",
                        linewidth=2,
                        label=algo,
                        color=COLORS[algo],
                    )
                axp.set_xticks(xs, BUCKET_SHORT, rotation=15, ha="right")
                axp.set_title(title)
                axp.spines["top"].set_visible(False)
                axp.spines["right"].set_visible(False)
            axes[0].legend(frameon=False, loc="upper left")
            fig.suptitle(
                f"Absolute error by predicted quintile — {mode_label}",
                fontsize=12,
                fontweight="bold",
            )
            fig.savefig(
                out_dir / f"predicted_rank_{slug}_mae_crps.png",
                dpi=dpi,
            )
            plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "input",
        type=Path,
        nargs="?",
        default=None,
        help="chart-data.txt from backtest (default: chart-data.txt next to this script)",
    )
    ap.add_argument("--out-dir", type=Path, default=None, help="PNG output directory")
    ap.add_argument("--csv", type=Path, default=None, help="Write tidy CSV here")
    ap.add_argument("--dpi", type=int, default=160)
    args = ap.parse_args()

    script_dir = Path(__file__).resolve().parent
    input_path = args.input if args.input is not None else script_dir / "chart-data.txt"
    text = input_path.read_text(encoding="utf-8")
    rows = parse_chart_data(text)
    if not rows:
        print("No rows parsed — check file format.", file=sys.stderr)
        return 1

    if args.csv:
        rows_to_csv(rows, args.csv)
        print(f"Wrote {len(rows)} rows to {args.csv}")

    out_dir = args.out_dir
    if out_dir:
        try:
            plot_figures(rows, out_dir, args.dpi)
        except ImportError as e:
            print(f"Plotting skipped (import error): {e}", file=sys.stderr)
            print("pip install matplotlib numpy", file=sys.stderr)
            return 1
        print(f"Figures written under {out_dir.resolve()}")

    if not args.csv and not args.out_dir:
        print("Parsed OK. Pass --csv and/or --out-dir.", file=sys.stderr)
        print(f"Row count: {len(rows)}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
