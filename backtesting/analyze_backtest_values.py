#!/usr/bin/env python3

import math
import json
import glob
import os
from typing import Optional
import pandas as pd
import numpy as np
import statsmodels.formula.api as smf
import matplotlib.pyplot as plt
import seaborn as sns
from scipy.stats import spearmanr

# ---------------------------------------------------------
# 1. Data Loading and Parsing
# ---------------------------------------------------------
def load_data():
    run_records = []

    json_files = glob.glob("backtest_params_*.json")
    if not json_files:
        print("No JSON files found in current directory.")
        return pd.DataFrame()

    for param_file in json_files:
        with open(param_file, 'r') as f:
            data = json.load(f)

        timestamp = data.get('timestamp', 'unknown')
        csv_file = data.get('csv_file', '')

        if not os.path.exists(csv_file):
            continue

        settings = data['algorithm_settings']['LLR']['settings']

        # Clean parameter names (remove 'latentLog' prefix for readability)
        clean_settings = {k.replace('latentLog', ''): v for k, v in settings.items()}

        try:
            df_csv = pd.read_csv(csv_file)

            # Helper to extract specific rows safely
            def get_metric(scope, mode, bucket, group, metric):
                mask = (df_csv['scope'] == scope) & (df_csv['mode'] == mode)
                if bucket: mask &= (df_csv['bucket'] == bucket)
                if group: mask &= (df_csv['group'] == group)

                res = df_csv[mask]
                return res[metric].values[0] if not res.empty else np.nan

            metrics = {
                'timestamp': timestamp,
                # Overall Metrics
                'crps_overall': get_metric('overall', 'rated-only', None, None, 'crps'),
                'mape_overall': get_metric('overall', 'rated-only', None, None, 'mape'),
                'mpe_overall': get_metric('overall', 'rated-only', None, None, 'mpe'),

                # Top 20% Metrics (Sharpness & Calibration)
                'crps_top20': get_metric('rating_quintile', 'rated-only', 'top 20%', None, 'crps'),
                'mape_top20': get_metric('rating_quintile', 'rated-only', 'top 20%', None, 'mape'),
                'mae_top20': get_metric('rating_quintile', 'rated-only', 'top 20%', None, 'mae'),
                'cov1_top20': get_metric('rating_quintile', 'rated-only', 'top 20%', None, 'coverage_1sigma'),

                # Division MAE (for Divergence check)
                'mae_open': get_metric('group', 'rated-only', None, 'Open', 'mae'),
                'mae_co': get_metric('group', 'rated-only', None, 'Carry Optics', 'mae'),
                'mae_lo': get_metric('group', 'rated-only', None, 'Limited Optics', 'mae')
            }

            # Merge cleaned settings and metrics
            run_dict = {**metrics, **clean_settings}
            run_records.append(run_dict)

        except Exception as e:
            print(f"Error processing {csv_file}: {e}")

    df = pd.DataFrame(run_records)
    return df

# ---------------------------------------------------------
# 2. Mathematical Topology (Valley/Plateau Detection)
# ---------------------------------------------------------
def analyze_topology(df, varying_params, target_metrics):
    print("\n" + "="*60)
    print(" QUADRATIC TOPOLOGY DETECTION")
    print("="*60)

    for metric in target_metrics:
        print(f"\n--- Target Metric: {metric} (Lower is Better) ---")
        for param in varying_params:
            unique_vals = df[param].nunique()
            if unique_vals < 3:
                continue # Need at least 3 points for a quadratic curve

            # Fit Model: y = a*x^2 + b*x + c
            formula = f"{metric} ~ {param} + I({param}**2)"
            try:
                model = smf.ols(formula=formula, data=df).fit()
            except Exception:
                continue

            a = model.params.get(f"I({param} ** 2)", 0)
            b = model.params.get(param, 0)
            p_val_a = model.pvalues.get(f"I({param} ** 2)", 1)
            p_val_b = model.pvalues.get(param, 1)

            param_min, param_max = df[param].min(), df[param].max()

            # Analyze curve shape
            if p_val_a < 0.10 and a > 0:
                # U-Shape (Valley)
                vertex_x = -b / (2 * a)
                if param_min <= vertex_x <= param_max:
                    print(f"  [VALLEY] {param}: Optimal value found inside bounds at ~{vertex_x:.4f} (p={p_val_a:.3f})")
                else:
                    direction = "Min" if vertex_x < param_min else "Max"
                    print(f"  [EDGE]   {param}: U-Shape, but optimal vertex ({vertex_x:.4f}) is outside tested bounds. Drive parameter toward {direction}.")
            elif p_val_a < 0.10 and a < 0:
                # Inverted U-Shape (Peak - worst case scenario)
                print(f"  [PEAK]   {param}: Inverted U-shape. Mid-points perform worst. Drive parameter to edges.")
            elif p_val_b < 0.05:
                # Linear trend dominates
                direction = "Decrease" if b > 0 else "Increase"
                print(f"  [LINEAR] {param}: No distinct valley. Linear trend dictates: {direction} parameter to improve metric.")
            else:
                # Noise / Plateau
                print(f"  [PLATEAU]{param}: No statistically significant variance (p_quad={p_val_a:.2f}, p_lin={p_val_b:.2f}). Safe to lock at default.")

# ---------------------------------------------------------
# 3. Sub-Population Divergence Check
# ---------------------------------------------------------
def analyze_divergence(df, varying_params):
    print("\n" + "="*60)
    print(" SUB-POPULATION DIVERGENCE (OVER-FITTING CHECK)")
    print("="*60)

    # Calculate MAE variance across the three main divisions
    df['div_mae_variance'] = df[['mae_open', 'mae_co', 'mae_lo']].var(axis=1)

    print("Checking if any parameter actively widens the error gap between divisions...")
    for param in varying_params:
        corr, p_val = spearmanr(df[param], df['div_mae_variance'])
        if p_val < 0.05:
            effect = "Widening" if corr > 0 else "Closing"
            print(f"  - {param}: {effect} the gap between divisions (Spearman rho = {corr:.2f}, p={p_val:.3f})")

# ---------------------------------------------------------
# 4. Visualizations
# ---------------------------------------------------------
def generate_plots(df, varying_params):
    print("\nGenerating visual plots (saving to current directory)...")

    def _frontier_df(
        local_df: pd.DataFrame,
        param: str,
        metric: str,
        *,
        bins: int = 20,
        method: str = 'q10',
        smooth_window: int = 3
    ) -> pd.DataFrame:
        """
        Build an efficient frontier by binning x and aggregating the metric per bin.
        method:
            - 'q10': 10th percentile per bin (robust lower-edge estimate)
            - 'min': strict minimum per bin
        smooth_window:
            Optional rolling median window on the frontier line.
        """
        clean = local_df[[param, metric]].dropna().copy()
        if clean.empty:
            return pd.DataFrame(columns=['x', 'frontier_y'])

        x_min, x_max = clean[param].min(), clean[param].max()
        if not np.isfinite(x_min) or not np.isfinite(x_max) or x_min == x_max:
            return pd.DataFrame(columns=['x', 'frontier_y'])

        # Bin to form a 1D local frontier; include_lowest ensures edge coverage.
        clean['_x_bin'] = pd.cut(clean[param], bins=bins, include_lowest=True)
        grouped = clean.groupby('_x_bin', observed=False)

        if method == 'min':
            y = grouped[metric].min()
        else:
            y = grouped[metric].quantile(0.10)

        x = grouped[param].median()
        frontier = pd.DataFrame({'x': x, 'frontier_y': y}).dropna().sort_values('x')

        if smooth_window >= 3 and len(frontier) >= smooth_window:
            frontier['frontier_y'] = (
                frontier['frontier_y']
                .rolling(window=smooth_window, center=True, min_periods=1)
                .median()
            )

        return frontier

    def _plot_frontier_grid(
        metric: str,
        file_name: str,
        title_prefix: str,
        line_color: str,
        y_label: Optional[str] = None,
        hline: Optional[float] = None
    ):
        if n_params <= 0:
            return

        cols = min(4, n_params)
        rows = math.ceil(n_params / cols)
        fig, axes = plt.subplots(rows, cols, figsize=(5 * cols, 5 * rows))
        if n_params == 1:
            axes = np.array([axes])
        else:
            axes = axes.flatten()

        for i, param in enumerate(varying_params):
            # Keep raw cloud visible for density/context.
            sns.scatterplot(
                ax=axes[i], data=df, x=param, y=metric,
                alpha=0.25, s=26, color='gray', edgecolor=None
            )

            frontier = _frontier_df(df, param, metric, bins=20, method='q10', smooth_window=3)
            if not frontier.empty:
                axes[i].plot(
                    frontier['x'], frontier['frontier_y'],
                    color=line_color, linewidth=2.2, label='Efficient Frontier (Q10)'
                )

            if hline is not None:
                axes[i].axhline(hline, color='red', linestyle='--', label='Ideal 1σ (0.683)')

            axes[i].set_title(f"{title_prefix} vs {param}", fontsize=10)
            if y_label:
                axes[i].set_ylabel(y_label)
            axes[i].grid(True, alpha=0.3)
            axes[i].legend(loc='best', fontsize=8)

        for j in range(i + 1, len(axes)):
            axes[j].set_visible(False)

        plt.tight_layout()
        plt.savefig(file_name, dpi=150, bbox_inches='tight')
        plt.close()

    # ---------------------------------------------------------
    # 1. Pareto Frontier Grid (CRPS vs Coverage, colored by each param)
    # ---------------------------------------------------------
    n_params = len(varying_params)
    if n_params > 0:
        cols = min(3, n_params) # Max 3 columns across
        rows = math.ceil(n_params / cols)

        fig, axes = plt.subplots(rows, cols, figsize=(6 * cols, 5 * rows))
        # Ensure axes is a flat array even if there's only 1 row or 1 plot
        if n_params == 1:
            axes = np.array([axes])
        else:
            axes = axes.flatten()

        for i, param in enumerate(varying_params):
            sns.scatterplot(ax=axes[i], data=df, x='crps_top20', y='cov1_top20',
                            hue=param, palette='viridis', s=80, alpha=0.8, edgecolor='k')

            axes[i].axhline(0.6827, color='red', linestyle='--', label='Ideal 1σ (0.683)')
            axes[i].set_title(f"Trade-off colored by:\n{param}", fontsize=11)
            axes[i].set_xlabel("CRPS Top 20% (Lower is Better)")
            axes[i].set_ylabel("1σ Coverage Top 20%")
            axes[i].grid(True, alpha=0.3)

            # Make legends smaller so they don't crowd the plot
            axes[i].legend(title=param, fontsize=8, title_fontsize=9, loc='best')

        # Hide any empty subplots
        for j in range(i + 1, len(axes)):
            axes[j].set_visible(False)

        plt.tight_layout()
        plt.savefig("pareto_grid.png", dpi=150, bbox_inches='tight')
        plt.close()

    # ---------------------------------------------------------
    # 2. LOESS Grids for CRPS Top 20 (All parameters)
    # ---------------------------------------------------------
    if n_params > 0:
        cols = min(4, n_params)
        rows = math.ceil(n_params / cols)

        fig, axes = plt.subplots(rows, cols, figsize=(5 * cols, 5 * rows))
        if n_params == 1:
            axes = np.array([axes])
        else:
            axes = axes.flatten()

        for i, param in enumerate(varying_params):
            unique_vals = df[param].nunique()
            use_loess = unique_vals >= 3 # Avoid divide-by-zero math warning

            sns.regplot(ax=axes[i], data=df, x=param, y='crps_top20',
                        lowess=use_loess, scatter_kws={'alpha':0.6}, line_kws={'color':'red'})

            title_suffix = " (LOESS)" if use_loess else " (Scatter Only)"
            axes[i].set_title(f"CRPS vs {param}\n{title_suffix}", fontsize=10)
            axes[i].grid(True, alpha=0.3)

        for j in range(i + 1, len(axes)):
            axes[j].set_visible(False)

        plt.tight_layout()
        plt.savefig("loess_landscape.png", dpi=150, bbox_inches='tight')
        plt.close()

    # ---------------------------------------------------------
    # 2b. Efficient Frontier Grids for CRPS Top 20 (All parameters)
    # ---------------------------------------------------------
    _plot_frontier_grid(
        metric='crps_top20',
        file_name='frontier_crps_landscape.png',
        title_prefix='CRPS Frontier',
        line_color='darkorange',
        y_label='CRPS Top 20% (Lower is Better)',
    )

    # ---------------------------------------------------------
    # 3. LOESS Grids for 1σ Coverage Top 20 (All parameters)
    # ---------------------------------------------------------
    if n_params > 0:
        cols = min(4, n_params)
        rows = math.ceil(n_params / cols)

        fig, axes = plt.subplots(rows, cols, figsize=(5 * cols, 5 * rows))
        if n_params == 1:
            axes = np.array([axes])
        else:
            axes = axes.flatten()

        for i, param in enumerate(varying_params):
            unique_vals = df[param].nunique()
            use_loess = unique_vals >= 3  # Avoid divide-by-zero math warning

            sns.regplot(ax=axes[i], data=df, x=param, y='cov1_top20',
                        lowess=use_loess, scatter_kws={'alpha':0.6}, line_kws={'color':'blue'})

            axes[i].axhline(0.6827, color='red', linestyle='--', label='Ideal 1σ (0.683)')
            title_suffix = " (LOESS)" if use_loess else " (Scatter Only)"
            axes[i].set_title(f"1σ Coverage vs {param}\n{title_suffix}", fontsize=10)
            axes[i].grid(True, alpha=0.3)
            axes[i].legend(loc='best', fontsize=8)

        for j in range(i + 1, len(axes)):
            axes[j].set_visible(False)

        plt.tight_layout()
        plt.savefig("loess_coverage_landscape.png", dpi=150, bbox_inches='tight')
        plt.close()

    # ---------------------------------------------------------
    # 3b. Efficient Frontier Grids for 1σ Coverage Top 20 (All parameters)
    # ---------------------------------------------------------
    _plot_frontier_grid(
        metric='cov1_top20',
        file_name='frontier_coverage_landscape.png',
        title_prefix='1σ Coverage Frontier',
        line_color='blue',
        y_label='1σ Coverage Top 20%',
        hline=0.6827,
    )

    # ---------------------------------------------------------
    # 4. LOESS Grids for MAPE Top 20 Rated-Only (All parameters)
    # ---------------------------------------------------------
    if n_params > 0:
        cols = min(4, n_params)
        rows = math.ceil(n_params / cols)

        fig, axes = plt.subplots(rows, cols, figsize=(5 * cols, 5 * rows))
        if n_params == 1:
            axes = np.array([axes])
        else:
            axes = axes.flatten()

        for i, param in enumerate(varying_params):
            unique_vals = df[param].nunique()
            use_loess = unique_vals >= 3  # Avoid divide-by-zero math warning

            sns.regplot(ax=axes[i], data=df, x=param, y='mape_top20',
                        lowess=use_loess, scatter_kws={'alpha':0.6}, line_kws={'color':'green'})

            title_suffix = " (LOESS)" if use_loess else " (Scatter Only)"
            axes[i].set_title(f"MAPE Top 20 vs {param}\n{title_suffix}", fontsize=10)
            axes[i].set_ylabel("MAPE Top 20 (Rated-Only)")
            axes[i].grid(True, alpha=0.3)

        for j in range(i + 1, len(axes)):
            axes[j].set_visible(False)

        plt.tight_layout()
        plt.savefig("loess_mape_landscape.png", dpi=150, bbox_inches='tight')
        plt.close()

    # ---------------------------------------------------------
    # 4b. Efficient Frontier Grids for MAPE Top 20 Rated-Only (All parameters)
    # ---------------------------------------------------------
    _plot_frontier_grid(
        metric='mape_top20',
        file_name='frontier_mape_landscape.png',
        title_prefix='MAPE Top 20 Frontier',
        line_color='green',
        y_label='MAPE Top 20 (Rated-Only)',
    )

    print(
        "Plots saved as "
        "'pareto_grid.png', "
        "'loess_landscape.png', "
        "'loess_coverage_landscape.png', "
        "'loess_mape_landscape.png', "
        "'frontier_crps_landscape.png', "
        "'frontier_coverage_landscape.png', "
        "and 'frontier_mape_landscape.png'."
    )

# ---------------------------------------------------------
# Main Execution
# ---------------------------------------------------------
if __name__ == "__main__":
    df = load_data()

    if df.empty:
        print("Execution halted: No valid data loaded.")
        exit()

    # Automatically identify which parameters actually vary in this dataset
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    # Exclude metrics from the parameter list
    metrics_list = ['crps_overall', 'mape_overall', 'mpe_overall', 'crps_top20', 'mape_top20', 'mae_top20', 'cov1_top20', 'mae_open', 'mae_co', 'mae_lo']
    param_cols = [c for c in numeric_cols if c not in metrics_list]

    varying_params = [p for p in param_cols if df[p].nunique() > 1]

    print(f"Detected {len(df)} runs.")
    print(f"Detected {len(varying_params)} varying parameters: {varying_params}")

    if not varying_params:
        print("No varying parameters found to analyze.")
        exit()

    target_metrics = ['crps_top20', 'crps_overall', 'mape_overall']

    analyze_topology(df, varying_params, target_metrics)
    analyze_divergence(df, varying_params)
    generate_plots(df, varying_params)

    print("\nAnalysis complete.")