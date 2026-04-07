#!/usr/bin/env python3
"""
Plot Q–Q data from latent_log_empirical.dart (ln(sample) vs standard normal quantiles).
Uses qq_ln_hf_sample.csv by default; pass --input for qq_ln_match_points_sample.csv (column sample_ln_match_points).

Generate the CSV first (from repo root):
  dart run research/latent-log-ratio/scripts/latent_log_empirical.dart

Then (from repo root or this directory):
  pip install -r research/latent-log-ratio/requirements-plot.txt
  python research/latent-log-ratio/plot_qq_ln_hf.py

Large CSVs: use --max-points to subsample evenly along the sorted series so the curve shape is preserved.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


def main() -> None:
    parser = argparse.ArgumentParser(description="Plot qq_ln_hf_sample.csv Q–Q diagram.")
    here = Path(__file__).resolve().parent
    parser.add_argument(
        "--input",
        type=Path,
        default=here / "qq_ln_hf_sample.csv",
        help="CSV: col1 = ln(sample), col2 = theoretical_normal_quantile",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="PNG path (default: sibling *_plot.png derived from input stem)",
    )
    parser.add_argument(
        "--ylabel",
        default="ln(HF)",
        help='Y-axis label for sample quantile (e.g. "ln(match points)" for match CSV)',
    )
    parser.add_argument(
        "--title",
        default="Q–Q plot: ln(hit factor) vs standard normal",
        help="Figure title",
    )
    parser.add_argument(
        "--max-points",
        type=int,
        default=200_000,
        metavar="N",
        help="Max points to plot (evenly spaced along sorted order; default 200000). Use 0 for all rows.",
    )
    parser.add_argument("--dpi", type=int, default=150, help="Figure DPI (default 150)")
    parser.add_argument("--width", type=float, default=8.0, help="Figure width inches")
    parser.add_argument("--height", type=float, default=8.0, help="Figure height inches")
    args = parser.parse_args()

    inp = args.input
    if not inp.is_file():
        raise SystemExit(f"Input not found: {inp}")

    data = np.loadtxt(inp, delimiter=",", skiprows=1)
    if data.size == 0:
        raise SystemExit("CSV has no data rows")
    if data.ndim == 1:
        data = data.reshape(1, -1)
    if data.shape[1] < 2:
        raise SystemExit("Expected at least two columns")

    sample_ln_hf = data[:, 0].astype(np.float64)
    theoretical_z = data[:, 1].astype(np.float64)
    n_full = len(sample_ln_hf)

    max_pts = args.max_points
    if max_pts is not None and max_pts > 0 and n_full > max_pts:
        idx = np.linspace(0, n_full - 1, max_pts, dtype=np.int64)
        sample_ln_hf = sample_ln_hf[idx]
        theoretical_z = theoretical_z[idx]

    # OLS line: ln(HF) ~ a + b * Z  (if Gaussian, points follow this line)
    x = theoretical_z
    y = sample_ln_hf
    A = np.vstack([x, np.ones(len(x))]).T
    slope, intercept = np.linalg.lstsq(A, y, rcond=None)[0]

    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(args.width, args.height), layout="constrained")
    ax.scatter(
        theoretical_z,
        sample_ln_hf,
        s=2,
        alpha=0.25,
        c="#1f77b4",
        edgecolors="none",
        rasterized=True,
    )

    z_line = np.linspace(float(theoretical_z.min()), float(theoretical_z.max()), 200)
    ax.plot(z_line, slope * z_line + intercept, color="crimson", linewidth=1.5, label="OLS fit")

    ax.set_xlabel("Theoretical quantile (standard normal)")
    ax.set_ylabel(f"Sample quantile: {args.ylabel}")
    ax.set_title(args.title)
    ax.grid(True, alpha=0.3)
    ax.legend(loc="lower right")

    caption = f"n_plot = {len(sample_ln_hf):,}"
    if max_pts and max_pts > 0 and n_full > max_pts:
        caption += f" (subsampled from full n = {n_full:,})"
    ax.text(
        0.02,
        0.98,
        caption,
        transform=ax.transAxes,
        fontsize=9,
        verticalalignment="top",
        bbox={"boxstyle": "round", "facecolor": "wheat", "alpha": 0.5},
    )

    out = args.output
    if out is None:
        stem = inp.stem
        plot_stem = stem[:-7] + "_plot" if stem.endswith("_sample") else f"{stem}_plot"
        out = inp.with_name(f"{plot_stem}.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=args.dpi)
    print(f"Wrote {out.resolve()}")


if __name__ == "__main__":
    main()
