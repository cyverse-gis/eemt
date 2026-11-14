#!/usr/bin/env python3
"""
EEMT Multi-Year Summary Report — Gordon Gulch 1980-2024
========================================================
Aggregates per-year EEMT results into summary statistics,
identifies ENSO patterns, and generates ASCII charts.

Usage:
    python3 scripts/eemt_multiyear_report.py
"""

import csv
import json
import os
import sys
import time
from pathlib import Path

import numpy as np

# =============================================================================
# Configuration
# =============================================================================

OUTPUT_BASE = "/opt/tswetnam/data/gordon_gulch/eemt_smoke_test"
YEARS = list(range(1980, 2025))
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun",
          "jul", "aug", "sep", "oct", "nov", "dec"]

# ENSO classification (Oceanic Nino Index 3-month running mean >= +/- 0.5°C)
# Source: NOAA CPC ONI data through 2024
# El Nino years (DJF season, so year = Jan year)
EL_NINO_YEARS = [
    1983, 1987, 1988, 1992, 1995, 1998, 2003, 2005, 2007,
    2010, 2015, 2016, 2019, 2024,
]
# Strong El Nino (ONI >= 1.5)
STRONG_EL_NINO = [1983, 1998, 2016]

# La Nina years
LA_NINA_YEARS = [
    1984, 1985, 1989, 1996, 1999, 2000, 2001, 2006, 2008,
    2009, 2011, 2012, 2018, 2021, 2022, 2023,
]
# Strong La Nina (ONI <= -1.5)
STRONG_LA_NINA = [1989, 1999, 2000, 2008, 2011]

NEUTRAL_YEARS = [y for y in YEARS if y not in EL_NINO_YEARS and y not in LA_NINA_YEARS]


# =============================================================================
# Data Loading
# =============================================================================

def load_yearly_stats(years):
    """Load monthly_stats.csv for each year. Returns dict of year -> month data."""
    all_data = {}
    missing = []

    for year in years:
        # Try per-year output first, then yearly_stats
        csv_path = os.path.join(OUTPUT_BASE, str(year), "monthly_stats.csv")
        if not os.path.isfile(csv_path):
            csv_path = os.path.join(OUTPUT_BASE, "yearly_stats", f"stats_{year}.csv")
        if not os.path.isfile(csv_path):
            missing.append(year)
            continue

        with open(csv_path) as f:
            reader = csv.DictReader(f)
            months = list(reader)
            if len(months) >= 12:
                all_data[year] = months

    return all_data, missing


def extract_annual_stats(all_data):
    """Compute annual EEMT from monthly data."""
    annual = {}
    for year, months in all_data.items():
        eemt_trad_sum = sum(float(m["eemt_trad_mean"]) for m in months)
        eemt_trad_max_monthly = max(float(m["eemt_trad_mean"]) for m in months)
        tmean_annual = np.mean([float(m["tmean_loc"]) for m in months])
        npp_peak = max(float(m["npp_trad_mean"]) for m in months)
        prcp_proxy = sum(float(m.get("e_ppt_trad_mean", "0")) for m in months)

        annual[year] = {
            "eemt_annual": eemt_trad_sum,
            "eemt_peak_month": eemt_trad_max_monthly,
            "tmean_annual": tmean_annual,
            "npp_peak": npp_peak,
            "prcp_energy": prcp_proxy,
        }
    return annual


# =============================================================================
# Statistics
# =============================================================================

def compute_group_stats(annual, years_subset, label):
    """Compute stats for a subset of years."""
    vals = [annual[y]["eemt_annual"] for y in years_subset if y in annual]
    if not vals:
        return None
    arr = np.array(vals)
    return {
        "label": label,
        "n": len(arr),
        "mean": np.mean(arr),
        "median": np.median(arr),
        "std": np.std(arr),
        "min": np.min(arr),
        "max": np.max(arr),
        "q25": np.percentile(arr, 25),
        "q75": np.percentile(arr, 75),
        "iqr": np.percentile(arr, 75) - np.percentile(arr, 25),
    }


def welch_t_test(group1, group2):
    """Simple Welch's t-test for unequal variances."""
    n1, n2 = len(group1), len(group2)
    if n1 < 2 or n2 < 2:
        return None, None
    m1, m2 = np.mean(group1), np.mean(group2)
    v1, v2 = np.var(group1, ddof=1), np.var(group2, ddof=1)
    se = np.sqrt(v1 / n1 + v2 / n2)
    if se < 1e-10:
        return 0, 1.0
    t_stat = (m1 - m2) / se
    # Approximate p-value using normal distribution (good for n > 10)
    # For small n this is rough, but adequate for a report
    from math import erfc, sqrt
    p_value = erfc(abs(t_stat) / sqrt(2))
    return t_stat, p_value


# =============================================================================
# ASCII Chart
# =============================================================================

def ascii_bar_chart(values, labels, title, width=50, unit=""):
    """Generate an ASCII horizontal bar chart."""
    lines = [title, "=" * (width + 20)]
    if not values:
        lines.append("  (no data)")
        return "\n".join(lines)

    max_val = max(abs(v) for v in values) if values else 1
    if max_val == 0:
        max_val = 1

    for label, val in zip(labels, values):
        bar_len = int(abs(val) / max_val * width)
        bar = "#" * bar_len
        lines.append(f"  {label:>5} | {bar:<{width}} {val:>7.1f} {unit}")
    return "\n".join(lines)


def ascii_time_series(years, values, title, width=60, unit=""):
    """Generate an ASCII time series with El Nino/La Nina markers."""
    lines = [title, "=" * (width + 25)]
    if not values:
        lines.append("  (no data)")
        return "\n".join(lines)

    min_val = min(values)
    max_val = max(values)
    val_range = max_val - min_val if max_val != min_val else 1

    for year, val in zip(years, values):
        pos = int((val - min_val) / val_range * width)
        bar = " " * pos + "*"
        # ENSO marker
        if year in STRONG_EL_NINO:
            marker = " <<< Strong El Nino"
        elif year in EL_NINO_YEARS:
            marker = " < El Nino"
        elif year in STRONG_LA_NINA:
            marker = " >>> Strong La Nina"
        elif year in LA_NINA_YEARS:
            marker = " > La Nina"
        else:
            marker = ""
        lines.append(f"  {year} |{bar:<{width+1}}| {val:>6.1f}{marker}")

    lines.append(f"  {'':>4}  {min_val:<{width//2}.1f}{' '*(width//2-len(f'{min_val:.1f}'))}{max_val:>.1f} {unit}")
    return "\n".join(lines)


def ascii_seasonal_chart(all_data, title):
    """Monthly climatology chart."""
    lines = [title, "=" * 70]

    # Compute monthly means across all years
    monthly_means = []
    monthly_stds = []
    for mi in range(12):
        vals = []
        for year, months in all_data.items():
            vals.append(float(months[mi]["eemt_trad_mean"]))
        monthly_means.append(np.mean(vals))
        monthly_stds.append(np.std(vals))

    max_val = max(monthly_means) if monthly_means else 1
    for mi in range(12):
        bar_len = int(monthly_means[mi] / max(max_val, 0.01) * 40)
        bar = "#" * bar_len
        lines.append(f"  {MONTHS[mi]:>3} | {bar:<40} {monthly_means[mi]:>6.2f} +/- {monthly_stds[mi]:.2f}")

    return "\n".join(lines)


# =============================================================================
# Report Generation
# =============================================================================

def generate_report(all_data, annual, missing):
    """Generate the full multi-year summary report."""
    report_path = os.path.join(OUTPUT_BASE, "multiyear_summary_report.txt")
    available_years = sorted(all_data.keys())

    with open(report_path, "w") as f:
        f.write("EEMT Multi-Year Summary Report — Gordon Gulch\n")
        f.write(f"{'='*70}\n\n")
        f.write(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Years analyzed: {min(available_years)}-{max(available_years)} "
                f"({len(available_years)} years)\n")
        if missing:
            f.write(f"Missing years: {missing}\n")
        f.write(f"Mode: Daily computation, summed to monthly\n")
        f.write(f"DEM: gordongulch_dem_10m_3dep_cog.tif (434x296, 10m, UTM 13N)\n")
        f.write(f"Elevation: 2377-2792 m\n\n")

        # =====================================================================
        # Table 1: Annual EEMT Summary Statistics
        # =====================================================================
        f.write("TABLE 1: ANNUAL EEMT SUMMARY STATISTICS (MJ/m2/yr)\n")
        f.write(f"{'-'*70}\n")

        all_stats = compute_group_stats(annual, available_years, "All Years")
        el_nino_stats = compute_group_stats(annual,
            [y for y in EL_NINO_YEARS if y in annual], "El Nino")
        la_nina_stats = compute_group_stats(annual,
            [y for y in LA_NINA_YEARS if y in annual], "La Nina")
        neutral_stats = compute_group_stats(annual,
            [y for y in NEUTRAL_YEARS if y in annual], "Neutral")
        strong_en_stats = compute_group_stats(annual,
            [y for y in STRONG_EL_NINO if y in annual], "Strong El Nino")
        strong_ln_stats = compute_group_stats(annual,
            [y for y in STRONG_LA_NINA if y in annual], "Strong La Nina")

        header = f"  {'Group':<18} {'N':>3} {'Mean':>7} {'Median':>7} {'Std':>7} {'Min':>7} {'Max':>7} {'IQR':>7}"
        f.write(header + "\n")
        f.write(f"  {'-'*66}\n")
        for s in [all_stats, el_nino_stats, la_nina_stats, neutral_stats,
                  strong_en_stats, strong_ln_stats]:
            if s:
                f.write(f"  {s['label']:<18} {s['n']:>3} {s['mean']:>7.1f} {s['median']:>7.1f} "
                        f"{s['std']:>7.1f} {s['min']:>7.1f} {s['max']:>7.1f} {s['iqr']:>7.1f}\n")

        # =====================================================================
        # Table 2: Statistical Significance Tests
        # =====================================================================
        f.write(f"\n\nTABLE 2: WELCH'S t-TEST: ENSO vs NEUTRAL\n")
        f.write(f"{'-'*70}\n")
        f.write(f"  {'Comparison':<35} {'t-stat':>8} {'p-value':>10} {'Signif':>8}\n")
        f.write(f"  {'-'*65}\n")

        tests = [
            ("El Nino vs Neutral", EL_NINO_YEARS, NEUTRAL_YEARS),
            ("La Nina vs Neutral", LA_NINA_YEARS, NEUTRAL_YEARS),
            ("El Nino vs La Nina", EL_NINO_YEARS, LA_NINA_YEARS),
            ("Strong El Nino vs Neutral", STRONG_EL_NINO, NEUTRAL_YEARS),
            ("Strong La Nina vs Neutral", STRONG_LA_NINA, NEUTRAL_YEARS),
        ]
        for label, grp1, grp2 in tests:
            v1 = [annual[y]["eemt_annual"] for y in grp1 if y in annual]
            v2 = [annual[y]["eemt_annual"] for y in grp2 if y in annual]
            t_stat, p_val = welch_t_test(v1, v2)
            if t_stat is not None:
                sig = "***" if p_val < 0.001 else "**" if p_val < 0.01 else "*" if p_val < 0.05 else "ns"
                f.write(f"  {label:<35} {t_stat:>8.3f} {p_val:>10.4f} {sig:>8}\n")
            else:
                f.write(f"  {label:<35} {'N/A':>8} {'N/A':>10} {'N/A':>8}\n")

        f.write(f"\n  Significance: *** p<0.001, ** p<0.01, * p<0.05, ns = not significant\n")

        # =====================================================================
        # Table 3: Year-by-Year Annual EEMT
        # =====================================================================
        f.write(f"\n\nTABLE 3: YEAR-BY-YEAR ANNUAL EEMT\n")
        f.write(f"{'-'*70}\n")
        f.write(f"  {'Year':>5} {'EEMT':>8} {'Tmean':>7} {'NPP_pk':>8} {'ENSO':>15} {'Rank':>6}\n")
        f.write(f"  {'-'*55}\n")

        # Sort by EEMT for ranking
        sorted_years = sorted(available_years, key=lambda y: annual[y]["eemt_annual"], reverse=True)
        rank_map = {y: i+1 for i, y in enumerate(sorted_years)}

        for year in available_years:
            a = annual[year]
            if year in STRONG_EL_NINO:
                enso = "Strong El Nino"
            elif year in EL_NINO_YEARS:
                enso = "El Nino"
            elif year in STRONG_LA_NINA:
                enso = "Strong La Nina"
            elif year in LA_NINA_YEARS:
                enso = "La Nina"
            else:
                enso = "Neutral"
            f.write(f"  {year:>5} {a['eemt_annual']:>8.1f} {a['tmean_annual']:>7.1f} "
                    f"{a['npp_peak']:>8.0f} {enso:>15} {rank_map[year]:>6}\n")

        # =====================================================================
        # Table 4: Decadal Summary
        # =====================================================================
        f.write(f"\n\nTABLE 4: DECADAL EEMT TRENDS\n")
        f.write(f"{'-'*70}\n")
        decades = [(1980, 1989), (1990, 1999), (2000, 2009), (2010, 2019), (2020, 2024)]
        f.write(f"  {'Decade':<12} {'N':>3} {'Mean':>7} {'Std':>7} {'Trend':>12}\n")
        f.write(f"  {'-'*45}\n")
        prev_mean = None
        for d_start, d_end in decades:
            d_years = [y for y in range(d_start, d_end+1) if y in annual]
            if d_years:
                d_vals = [annual[y]["eemt_annual"] for y in d_years]
                d_mean = np.mean(d_vals)
                d_std = np.std(d_vals)
                if prev_mean is not None:
                    trend = f"{d_mean - prev_mean:+.1f}"
                else:
                    trend = "—"
                f.write(f"  {d_start}-{d_end:<7} {len(d_years):>3} {d_mean:>7.1f} {d_std:>7.1f} {trend:>12}\n")
                prev_mean = d_mean

        # =====================================================================
        # Chart 1: Time Series
        # =====================================================================
        f.write(f"\n\n")
        ts_years = [y for y in available_years if y in annual]
        ts_vals = [annual[y]["eemt_annual"] for y in ts_years]
        f.write(ascii_time_series(ts_years, ts_vals,
                "CHART 1: ANNUAL EEMT TIME SERIES (MJ/m2/yr)") + "\n")

        # =====================================================================
        # Chart 2: Seasonal Climatology
        # =====================================================================
        f.write(f"\n\n")
        f.write(ascii_seasonal_chart(all_data,
                "CHART 2: MONTHLY EEMT CLIMATOLOGY (mean +/- std, MJ/m2/month)") + "\n")

        # =====================================================================
        # Chart 3: ENSO Comparison Bar Chart
        # =====================================================================
        f.write(f"\n\n")
        group_labels = []
        group_vals = []
        for s in [all_stats, el_nino_stats, la_nina_stats, neutral_stats,
                  strong_en_stats, strong_ln_stats]:
            if s:
                group_labels.append(s["label"][:12])
                group_vals.append(s["mean"])
        f.write(ascii_bar_chart(group_vals, group_labels,
                "CHART 3: MEAN ANNUAL EEMT BY ENSO PHASE", unit="MJ/m2/yr") + "\n")

        # =====================================================================
        # Top/Bottom Years
        # =====================================================================
        f.write(f"\n\nTOP 5 HIGHEST EEMT YEARS\n")
        f.write(f"{'-'*40}\n")
        for i, y in enumerate(sorted_years[:5]):
            enso = "EN" if y in EL_NINO_YEARS else "LN" if y in LA_NINA_YEARS else "N"
            f.write(f"  {i+1}. {y} — {annual[y]['eemt_annual']:.1f} MJ/m2/yr ({enso})\n")

        f.write(f"\nTOP 5 LOWEST EEMT YEARS\n")
        f.write(f"{'-'*40}\n")
        for i, y in enumerate(reversed(sorted_years[-5:])):
            enso = "EN" if y in EL_NINO_YEARS else "LN" if y in LA_NINA_YEARS else "N"
            f.write(f"  {i+1}. {y} — {annual[y]['eemt_annual']:.1f} MJ/m2/yr ({enso})\n")

        # =====================================================================
        # Linear Trend
        # =====================================================================
        f.write(f"\n\nLINEAR TREND ANALYSIS\n")
        f.write(f"{'-'*40}\n")
        if len(ts_years) > 5:
            x = np.array(ts_years, dtype=float)
            y = np.array(ts_vals, dtype=float)
            coeffs = np.polyfit(x, y, 1)
            slope = coeffs[0]
            r_val = np.corrcoef(x, y)[0, 1]
            f.write(f"  Slope: {slope:.3f} MJ/m2/yr per year\n")
            f.write(f"  R: {r_val:.3f}\n")
            f.write(f"  R²: {r_val**2:.3f}\n")
            total_change = slope * (max(ts_years) - min(ts_years))
            f.write(f"  Total change ({min(ts_years)}-{max(ts_years)}): {total_change:+.1f} MJ/m2/yr\n")

    print(f"Report written to: {report_path}")
    return report_path


def generate_csv_summary(annual, all_data):
    """Write a combined CSV with all years."""
    csv_path = os.path.join(OUTPUT_BASE, "multiyear_annual_stats.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["year", "eemt_annual", "tmean_annual", "npp_peak",
                        "enso_phase",
                        "jan", "feb", "mar", "apr", "may", "jun",
                        "jul", "aug", "sep", "oct", "nov", "dec"])
        for year in sorted(annual.keys()):
            a = annual[year]
            if year in STRONG_EL_NINO:
                enso = "strong_el_nino"
            elif year in EL_NINO_YEARS:
                enso = "el_nino"
            elif year in STRONG_LA_NINA:
                enso = "strong_la_nina"
            elif year in LA_NINA_YEARS:
                enso = "la_nina"
            else:
                enso = "neutral"

            monthly_vals = []
            if year in all_data:
                for m in all_data[year]:
                    monthly_vals.append(f"{float(m['eemt_trad_mean']):.2f}")
            else:
                monthly_vals = [""] * 12

            writer.writerow([year, f"{a['eemt_annual']:.1f}", f"{a['tmean_annual']:.1f}",
                           f"{a['npp_peak']:.0f}", enso] + monthly_vals)

    print(f"CSV written to: {csv_path}")
    return csv_path


# =============================================================================
# Main
# =============================================================================

def main():
    print("EEMT Multi-Year Summary — Gordon Gulch")
    print("=" * 50)

    all_data, missing = load_yearly_stats(YEARS)
    print(f"Loaded: {len(all_data)} years")
    if missing:
        print(f"Missing: {len(missing)} years — {missing[:10]}{'...' if len(missing)>10 else ''}")

    if len(all_data) < 5:
        print("Not enough data for summary. Run eemt_smoke_test.py for more years first.")
        sys.exit(1)

    annual = extract_annual_stats(all_data)

    report_path = generate_report(all_data, annual, missing)
    csv_path = generate_csv_summary(annual, all_data)

    # Print key findings to stdout
    available_years = sorted(all_data.keys())
    vals = [annual[y]["eemt_annual"] for y in available_years]
    print(f"\nKey findings ({min(available_years)}-{max(available_years)}):")
    print(f"  Mean annual EEMT: {np.mean(vals):.1f} +/- {np.std(vals):.1f} MJ/m2/yr")
    print(f"  Range: {np.min(vals):.1f} to {np.max(vals):.1f}")

    # ENSO comparison
    en_vals = [annual[y]["eemt_annual"] for y in EL_NINO_YEARS if y in annual]
    ln_vals = [annual[y]["eemt_annual"] for y in LA_NINA_YEARS if y in annual]
    ne_vals = [annual[y]["eemt_annual"] for y in NEUTRAL_YEARS if y in annual]
    if en_vals and ln_vals:
        print(f"  El Nino mean: {np.mean(en_vals):.1f}, La Nina mean: {np.mean(ln_vals):.1f}, "
              f"Neutral mean: {np.mean(ne_vals):.1f}")
        t_stat, p_val = welch_t_test(en_vals, ln_vals)
        if p_val is not None:
            print(f"  El Nino vs La Nina: t={t_stat:.2f}, p={p_val:.4f} "
                  f"{'(significant)' if p_val < 0.05 else '(not significant)'}")


if __name__ == "__main__":
    main()
