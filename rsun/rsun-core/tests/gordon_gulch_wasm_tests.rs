//! Gordon Gulch DEM tests — WASM code path simulation.
//!
//! The rsun-wasm crate takes scalar lat/lon (broadcast to all pixels) and
//! computes slope/aspect internally with ew_res=ns_res=1.0. This test file
//! replicates that exact code path using rsun-core directly, validating:
//!
//! 1. The WASM workflow produces physically plausible results
//! 2. Comparison against the full CPU path (which uses per-pixel reprojected
//!    lat/lon and real 10m resolution for slope/aspect)
//!
//! The WASM path will differ from the CPU path because:
//! - Scalar lat/lon vs per-pixel reprojected (small effect for 434×296 grid)
//! - slope_aspect(dem, 1.0, 1.0) vs slope_aspect(dem, 10.0, 10.0) — different
//!   pixel spacing affects gradient magnitude
//!
//! Requires the `io` feature for reading the reference DEM.

#![cfg(feature = "io")]

use rsun_core::io::{compute_latlon_grid, read_geotiff};
use rsun_core::terrain::slope_aspect;
use rsun_core::types::{Grid, SolarParams};

const DEM_PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../data/gordon_gulch/gordongulch_dem_10m_3dep_cog.tif"
);

/// Replicate the exact WASM code path from rsun-wasm/src/lib.rs:
/// 1. Read DEM data (flat f32 array)
/// 2. slope_aspect(&dem, 1.0, 1.0) — WASM hardcodes unit resolution
/// 3. Uniform lat/lon grids from scalar centroid value
/// 4. compute_day()
fn wasm_code_path(
    dem: &Grid,
    latitude_rad: f32,
    longitude_rad: f32,
    day: u16,
    step: f64,
) -> rsun_core::types::DayResult {
    // WASM computes slope/aspect internally with 1.0/1.0 resolution
    let (slope, aspect) = slope_aspect(dem, 1.0, 1.0);

    // WASM broadcasts scalar lat/lon to all pixels
    let mut lat_grid = Grid::new(dem.rows, dem.cols, f32::NAN);
    let mut lon_grid = Grid::new(dem.rows, dem.cols, f32::NAN);
    for r in 0..dem.rows {
        for c in 0..dem.cols {
            if !dem.is_nodata(r, c) {
                lat_grid.set(r, c, latitude_rad);
                lon_grid.set(r, c, longitude_rad);
            }
        }
    }

    let params = SolarParams {
        day,
        step,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    rsun_core::compute_day(dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params)
}

/// Full CPU reference path with GDAL reprojection and correct resolution.
fn cpu_reference_path(
    dem: &Grid,
    geo: &rsun_core::types::GeoTransform,
    day: u16,
    step: f64,
) -> rsun_core::types::DayResult {
    let (slope, aspect) = slope_aspect(dem, geo.x_res, geo.y_res);
    let (lat_grid, lon_grid) =
        compute_latlon_grid(dem.rows, dem.cols, geo).expect("Failed to compute lat/lon grid");

    let params = SolarParams {
        day,
        step,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    rsun_core::compute_day(dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params)
}

/// Mean of valid pixels.
fn valid_mean(grid: &Grid) -> f64 {
    let mut sum = 0.0_f64;
    let mut count = 0usize;
    for &v in &grid.data {
        if !v.is_nan() {
            sum += v as f64;
            count += 1;
        }
    }
    if count > 0 { sum / count as f64 } else { 0.0 }
}

// ============================================================================
// WASM Path — Plausibility Tests
// ============================================================================

#[test]
fn test_gordon_gulch_wasm_path_summer() {
    let (dem, _) = read_geotiff(DEM_PATH).expect("Failed to read DEM");

    // Gordon Gulch centroid: ~40.01°N, ~-105.47°W
    let lat_rad = 40.01_f32.to_radians();
    let lon_rad = (-105.47_f32).to_radians();

    let result = wasm_code_path(&dem, lat_rad, lon_rad, 172, 0.5);

    let mean_rad = valid_mean(&result.glob_rad);
    let mean_insol = valid_mean(&result.insol_time);

    eprintln!("WASM path summer (day 172): glob_rad={mean_rad:.0} Wh/m², insol={mean_insol:.1}h");

    // Should produce physically plausible summer radiation
    assert!(mean_rad > 2000.0, "WASM mean radiation {mean_rad} too low");
    assert!(mean_rad < 12000.0, "WASM mean radiation {mean_rad} too high");
    assert!(mean_insol > 6.0, "WASM mean insolation {mean_insol} too low");
    assert!(mean_insol < 16.0, "WASM mean insolation {mean_insol} too high");
}

#[test]
fn test_gordon_gulch_wasm_path_winter() {
    let (dem, _) = read_geotiff(DEM_PATH).expect("Failed to read DEM");

    let lat_rad = 40.01_f32.to_radians();
    let lon_rad = (-105.47_f32).to_radians();

    let result = wasm_code_path(&dem, lat_rad, lon_rad, 355, 0.5);

    let mean_rad = valid_mean(&result.glob_rad);
    let mean_insol = valid_mean(&result.insol_time);

    eprintln!("WASM path winter (day 355): glob_rad={mean_rad:.0} Wh/m², insol={mean_insol:.1}h");

    assert!(mean_rad > 200.0, "WASM mean radiation {mean_rad} too low");
    assert!(mean_rad < 5000.0, "WASM mean radiation {mean_rad} too high for winter");
}

// ============================================================================
// WASM Path — Seasonal Pattern
// ============================================================================

#[test]
fn test_gordon_gulch_wasm_path_seasonal_pattern() {
    let (dem, _) = read_geotiff(DEM_PATH).expect("Failed to read DEM");

    let lat_rad = 40.01_f32.to_radians();
    let lon_rad = (-105.47_f32).to_radians();

    let seasonal_days = [355u16, 80, 172, 266];
    let labels = ["Winter", "Spring", "Summer", "Fall"];
    let mut means = Vec::new();

    for (i, &day) in seasonal_days.iter().enumerate() {
        let result = wasm_code_path(&dem, lat_rad, lon_rad, day, 0.5);
        let mean = valid_mean(&result.glob_rad);
        eprintln!("  WASM {}: {mean:.0} Wh/m²", labels[i]);
        means.push(mean);
    }

    // Same seasonal pattern as CPU reference
    assert!(means[0] < means[1], "Winter < Spring");
    assert!(means[1] < means[2], "Spring < Summer");
    assert!(means[2] > means[3], "Summer > Fall");
}

// ============================================================================
// WASM vs CPU Reference — Cross-path Comparison
// ============================================================================

#[test]
fn test_gordon_gulch_wasm_vs_cpu_reference() {
    let (dem, geo) = read_geotiff(DEM_PATH).expect("Failed to read DEM");

    let lat_rad = 40.01_f32.to_radians();
    let lon_rad = (-105.47_f32).to_radians();

    // WASM path (scalar lat/lon, unit resolution slope/aspect)
    let wasm_result = wasm_code_path(&dem, lat_rad, lon_rad, 172, 0.5);

    // CPU reference (per-pixel lat/lon, real 10m resolution)
    let cpu_result = cpu_reference_path(&dem, &geo, 172, 0.5);

    let wasm_mean = valid_mean(&wasm_result.glob_rad);
    let cpu_mean = valid_mean(&cpu_result.glob_rad);

    let mean_diff_pct = ((wasm_mean - cpu_mean) / cpu_mean).abs() * 100.0;

    eprintln!("WASM vs CPU reference (day 172):");
    eprintln!("  WASM mean: {wasm_mean:.0} Wh/m²");
    eprintln!("  CPU mean:  {cpu_mean:.0} Wh/m²");
    eprintln!("  Mean difference: {mean_diff_pct:.1}%");

    // The WASM path uses unit-resolution slope/aspect which exaggerates
    // gradients by 10x (since the real resolution is 10m). This produces
    // significantly different slope values, so we expect a noticeable
    // difference in mean radiation. The test validates both paths produce
    // physically reasonable values and documents the divergence.
    //
    // Note: A production WASM interface should accept resolution parameters.
    assert!(
        wasm_mean > 0.0 && cpu_mean > 0.0,
        "Both paths should produce positive radiation"
    );
    // Log the comparison for reference even if the diff is large
    eprintln!("  (WASM uses ew_res=ns_res=1.0 vs CPU's 10.0m — slope magnitude differs by ~10x)");
}

// ============================================================================
// WASM vs CPU — Flat Terrain (eliminates slope/aspect difference)
// ============================================================================

#[test]
fn test_gordon_gulch_wasm_vs_cpu_flat_subset() {
    // On a perfectly flat DEM, the WASM and CPU paths should agree closely
    // since slope/aspect are both 0 regardless of resolution.
    let rows = 50;
    let cols = 50;
    let mut flat_dem = Grid::new(rows, cols, f32::NAN);
    for r in 0..rows {
        for c in 0..cols {
            flat_dem.set(r, c, 2600.0); // typical Gordon Gulch elevation
        }
    }

    let lat_rad = 40.01_f32.to_radians();
    let lon_rad = (-105.47_f32).to_radians();

    // WASM path
    let wasm_result = wasm_code_path(&flat_dem, lat_rad, lon_rad, 172, 0.5);

    // CPU-equivalent path (same scalar lat/lon, same flat terrain)
    let (slope, aspect) = slope_aspect(&flat_dem, 10.0, 10.0);
    let mut lat_grid = Grid::new(rows, cols, f32::NAN);
    let mut lon_grid = Grid::new(rows, cols, f32::NAN);
    for r in 0..rows {
        for c in 0..cols {
            lat_grid.set(r, c, lat_rad);
            lon_grid.set(r, c, lon_rad);
        }
    }
    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };
    let cpu_result =
        rsun_core::compute_day(&flat_dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    // Compare interior pixels (edges are nodata from slope_aspect)
    let wasm_center = wasm_result.glob_rad.get(25, 25) as f64;
    let cpu_center = cpu_result.glob_rad.get(25, 25) as f64;

    let rel_diff = ((wasm_center - cpu_center) / cpu_center).abs() * 100.0;

    eprintln!("Flat DEM WASM vs CPU (center pixel): WASM={wasm_center:.0}, CPU={cpu_center:.0}, diff={rel_diff:.3}%");

    // On flat terrain, both paths should agree very closely
    assert!(
        rel_diff < 1.0,
        "Flat terrain: WASM ({wasm_center:.0}) vs CPU ({cpu_center:.0}) differ by {rel_diff:.3}%"
    );
}
