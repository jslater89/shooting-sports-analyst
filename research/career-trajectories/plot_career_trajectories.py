#!/usr/bin/env python3
"""
Plot career trajectories from CFA long-format CSV (see README.md in this folder).

Example:
  python plot_career_trajectories.py ~/data/llr_trajectories.csv --group CO \\
    --y field_adj --x career_age --highlight improvePlateauDecline \\
    --highlight declineTroughAtEnd -o co.png
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Plot career trajectories from CFA trajectory CSV.")
    p.add_argument("input_csv", type=Path, help="Long-format trajectory CSV from CFA")
    p.add_argument(
        "--group",
        default="CO",
        help="Substring match (case-insensitive) on the group column (default: CO)",
    )
    p.add_argument(
        "--x",
        choices=("career_age", "year"),
        default="career_age",
        help="Horizontal axis",
    )
    p.add_argument(
        "--y",
        choices=("rating_display", "field_adj"),
        default="field_adj",
        help="Vertical axis: raw display rating vs field-adjusted display",
    )
    p.add_argument(
        "--highlight",
        action="append",
        default=[],
        metavar="TRAJECTORY",
        help="Trajectory category to emphasize (repeatable). Must match CSV trajectory column.",
    )
    p.add_argument(
        "--min-active-years",
        type=int,
        default=0,
        metavar="N",
        help="Only plot shooters with activeYearCount >= N (0 = no filter)",
    )
    p.add_argument(
        "--background-alpha",
        type=float,
        default=0.07,
        help="Alpha for non-highlighted trajectories",
    )
    p.add_argument(
        "--highlight-alpha",
        type=float,
        default=0.85,
        help="Alpha for highlighted trajectories",
    )
    p.add_argument(
        "--linewidth-bg",
        type=float,
        default=0.6,
        help="Line width for background trajectories",
    )
    p.add_argument(
        "--linewidth-hi",
        type=float,
        default=1.4,
        help="Line width for highlighted trajectories",
    )
    p.add_argument("-o", "--output", type=Path, default=Path("career_trajectories.png"))
    p.add_argument("--title", default="", help="Figure title (default: auto from filters)")
    p.add_argument("--figwidth", type=float, default=11.0)
    p.add_argument("--figheight", type=float, default=7.0)
    p.add_argument(
        "--list-categories",
        action="store_true",
        help="Print trajectory category counts for the group filter and exit",
    )
    return p.parse_args()


def load_rows(path: Path, group_substring: str) -> list[dict[str, str]]:
    g = group_substring.lower()
    rows: list[dict[str, str]] = []
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if g not in row.get("group", "").lower():
                continue
            rows.append(row)
    return rows


def trajectory_counts_by_shooter(rows: list[dict[str, str]]) -> dict[str, int]:
    """One count per shooter (ratingId) per trajectory label."""
    per_shooter: dict[str, str] = {}
    for row in rows:
        rid = row["ratingId"]
        per_shooter[rid] = row.get("trajectory", "")
    out: dict[str, int] = defaultdict(int)
    for _rid, t in per_shooter.items():
        out[t] += 1
    return dict(sorted(out.items(), key=lambda kv: (-kv[1], kv[0])))


def build_series(
    rows: list[dict[str, str]],
    min_active: int,
    x_mode: str,
    y_mode: str,
) -> tuple[dict[str, list[tuple[float, float]]], dict[str, str]]:
    """
    Returns:
      series: ratingId -> list of (x, y) sorted by x
      trajectory_by_id: ratingId -> trajectory label
    """
    by_id: dict[str, list[tuple[float, float, int]]] = defaultdict(list)
    traj_by_id: dict[str, str] = {}

    for row in rows:
        rid = row["ratingId"]
        try:
            n_active = int(row["activeYearCount"])
        except (KeyError, ValueError):
            n_active = 0
        if min_active > 0 and n_active < min_active:
            continue
        traj_by_id[rid] = row.get("trajectory", "")

        ca = int(float(row["careerAge"]))
        yr = int(float(row["calendarYear"]))
        x = float(ca) if x_mode == "career_age" else float(yr)

        if y_mode == "rating_display":
            y = float(row["ratingDisplay"])
        else:
            y = float(row["fieldAdjDisplay"])

        by_id[rid].append((x, y, yr))

    series: dict[str, list[tuple[float, float]]] = {}
    for rid, pts in by_id.items():
        if len(pts) < 2:
            continue
        pts_sorted = sorted(pts, key=lambda t: (t[0], t[2]))
        series[rid] = [(p[0], p[1]) for p in pts_sorted]
    return series, traj_by_id


def main() -> None:
    args = parse_args()
    rows = load_rows(args.input_csv, args.group)
    if not rows:
        raise SystemExit(f"No rows match group filter {args.group!r} in {args.input_csv}")

    if args.list_categories:
        print(f"Shooters by trajectory (group contains {args.group!r}):")
        for k, v in trajectory_counts_by_shooter(rows).items():
            print(f"  {k:32} {v}")
        return

    x_mode = "career_age" if args.x == "career_age" else "year"
    y_mode = "rating_display" if args.y == "rating_display" else "field_adj"

    series, traj_by_id = build_series(rows, args.min_active_years, x_mode, y_mode)
    if not series:
        raise SystemExit("No series after filters (need >=2 points per shooter in CSV).")

    highlight_set = set(args.highlight)
    fig, ax = plt.subplots(figsize=(args.figwidth, args.figheight))

    cmap = plt.get_cmap("tab10")
    hi_colors = {h: cmap(i % 10) for i, h in enumerate(sorted(highlight_set))}

    n_bg = 0
    for rid, pts in series.items():
        t = traj_by_id.get(rid, "")
        if t in highlight_set:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax.plot(xs, ys, color="0.35", alpha=args.background_alpha, linewidth=args.linewidth_bg)
        n_bg += 1

    n_hi = 0
    for rid, pts in series.items():
        t = traj_by_id.get(rid, "")
        if t not in highlight_set:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax.plot(
            xs,
            ys,
            color=hi_colors[t],
            alpha=args.highlight_alpha,
            linewidth=args.linewidth_hi,
        )
        n_hi += 1

    if highlight_set:
        handles = []
        labels = []
        for h in sorted(highlight_set):
            (line,) = ax.plot(
                [np.nan],
                [np.nan],
                color=hi_colors[h],
                linewidth=args.linewidth_hi,
                label=h,
            )
            handles.append(line)
            labels.append(h)
        ax.legend(handles, labels, loc="best", fontsize=9)

    xlab = "Career age (years since first active year)" if args.x == "career_age" else "Calendar year"
    ylab = (
        "Field-adjusted display rating (vs group median)"
        if args.y == "field_adj"
        else "End-of-year display rating"
    )
    ax.set_xlabel(xlab)
    ax.set_ylabel(ylab)
    ax.grid(True, alpha=0.25)
    title = args.title or f"Career trajectories — group ~ {args.group!r} (n={len(series)} shooters)"
    ax.set_title(title)
    fig.tight_layout()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=160)
    print(f"Wrote {args.output} (background lines: {n_bg}, highlighted: {n_hi})")


if __name__ == "__main__":
    main()
