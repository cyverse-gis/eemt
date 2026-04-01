//! Gordon Gulch DEM integration tests — CPU reference path.
//!
//! Tests rsun-core on the real Gordon Gulch 10m DEM (434×296, UTM Zone 13N).
//! Validates physically plausible radiation values, seasonal patterns,
//! terrain derivatives, and nodata handling.
//!
//! Requires the `io` feature (GDAL) and the DEM at:
//!   data/gordon_gulch/gordongulch_dem_10m_3dep_cog.tif

#![cfg(feature = "io")]

use rsun_core::io::{compute_latlon_grid, read_geotiff};
use rsun_core::terrain::slope_aspect;
use rsun_core::types::SolarParams;

const DEM_PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../data/gordon_gulch/gordongulch_dem_10m_3dep_cog.tif"
);

/// Load the Gordon Gulch DEM and compute all derived grids.
/// Returns (dem, slope, aspect, lat_grid, lon_grid, geo).
fn load_gordon_gulch() -> (
    rsun_core::types::Grid,
    rsun_core::types::Grid,
    rsun_core::types::Grid,
    rsun_core::types::Grid,
    rsun_core::types::Grid,
    rsun_core::types::GeoTransform,
) {
    let (dem, geo) = read_geotiff(DEM_PATH).expect("Failed to read Gordon Gulch DEM");
    assert_eq!(dem.cols, 434, "Expected 434 columns");
    assert_eq!(dem.rows, 296, "Expected 296 rows");

    let (slope, aspect) = slope_aspect(&dem, geo.x_res, geo.y_res);
    let (lat_grid, lon_grid) =
        compute_latlon_grid(dem.rows, dem.cols, &geo).expect("Failed to compute lat/lon grid");

    (dem, slope, aspect, lat_grid, lon_grid, geo)
}

/// Helper: compute statistics for valid (non-NaN) pixels in a grid.
fn grid_stats(grid: &rsun_core::types::Grid) -> (f64, f64, f64, usize) {
    let mut sum = 0.0_f64;
    let mut min = f64::MAX;
    let mut max = f64::MIN;
    let mut count = 0usize;

    for &v in &grid.data {
        if !v.is_nan() {
            let vf = v as f64;
            sum += vf;
            if vf < min {
                min = vf;
            }
            if vf > max {
                max = vf;
            }
            count += 1;
        }
    }

    let mean = if count > 0 { sum / count as f64 } else { 0.0 };
    (mean, min, max, count)
}

// ============================================================================
// DEM and Terrain Tests
// ============================================================================

#[test]
fn test_gordon_gulch_dem_dimensions() {
    let (dem, geo) = read_geotiff(DEM_PATH).expect("Failed to read DEM");
    assert_eq!(dem.rows, 296);
    assert_eq!(dem.cols, 434);
    assert!((geo.x_res - 10.0).abs() < 0.1, "Expected ~10m x_res, got {}", geo.x_res);
    assert!((geo.y_res - 10.0).abs() < 0.1, "Expected ~10m y_res, got {}", geo.y_res);
}

#[test]
fn test_gordon_gulch_elevation_range() {
    let (dem, _) = read_geotiff(DEM_PATH).expect("Failed to read DEM");
    let (mean, min, max, count) = grid_stats(&dem);

    eprintln!("Gordon Gulch DEM: {count} valid pixels, elevation {min:.0}–{max:.0}m, mean {mean:.0}m");

    // Gordon Gulch: ~2377–2792m elevation (3DEP 10m DEM)
    assert!(min > 2300.0, "Min elevation {min} too low");
    assert!(max < 2900.0, "Max elevation {max} too high");
    assert!(mean > 2500.0 && mean < 2700.0, "Mean elevation {mean} out of expected range");
    assert!(count > 100_000, "Expected >100K valid pixels, got {count}");
}

#[test]
fn test_gordon_gulch_terrain_derivatives() {
    let (_dem, slope, aspect, _, _, _) = load_gordon_gulch();

    let (slope_mean, slope_min, slope_max, slope_count) = grid_stats(&slope);
    let (asp_mean, _asp_min, asp_max, asp_count) = grid_stats(&aspect);

    eprintln!("Slope: mean={slope_mean:.4} rad ({:.1}°), max={slope_max:.4} rad ({:.1}°), {slope_count} pixels",
        slope_mean.to_degrees(), slope_max.to_degrees());
    eprintln!("Aspect: mean={asp_mean:.1}°, max={asp_max:.1}°, {asp_count} pixels");

    // Edge pixels are nodata, so fewer than DEM valid pixels
    assert!(slope_count > 0, "No valid slope pixels");
    assert!(slope_min >= 0.0, "Slope should be non-negative");
    assert!(slope_max < std::f64::consts::FRAC_PI_2, "Slope should be < 90°");
    assert!(asp_max <= 360.0, "Aspect should be ≤ 360°");
}

#[test]
fn test_gordon_gulch_latlon_grid() {
    let (_, _, _, lat_grid, lon_grid, _) = load_gordon_gulch();

    // Gordon Gulch center: ~40.01°N, -105.47°W
    let center_lat = lat_grid.get(148, 217) as f64; // center pixel
    let center_lon = lon_grid.get(148, 217) as f64;

    let lat_deg = center_lat.to_degrees();
    let lon_deg = center_lon.to_degrees();

    eprintln!("Center pixel: {lat_deg:.4}°N, {lon_deg:.4}°W");

    assert!(lat_deg > 39.9 && lat_deg < 40.1, "Latitude {lat_deg}° out of range");
    assert!(lon_deg > -105.6 && lon_deg < -105.4, "Longitude {lon_deg}° out of range");
}

// ============================================================================
// Solar Radiation Tests — Single Day
// ============================================================================

#[test]
fn test_gordon_gulch_summer_solstice() {
    let (dem, slope, aspect, lat_grid, lon_grid, _) = load_gordon_gulch();

    let params = SolarParams {
        day: 172, // summer solstice
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    let (mean_rad, min_rad, max_rad, count) = grid_stats(&result.glob_rad);
    let (mean_insol, _, max_insol, _) = grid_stats(&result.insol_time);

    eprintln!("Summer solstice (day 172):");
    eprintln!("  glob_rad: mean={mean_rad:.0}, min={min_rad:.0}, max={max_rad:.0} Wh/m² ({count} pixels)");
    eprintln!("  insol_time: mean={mean_insol:.1}, max={max_insol:.1} hours");

    // Summer at 40°N, ~2600m: expect substantial radiation
    assert!(mean_rad > 4000.0, "Mean radiation {mean_rad} too low for summer");
    assert!(mean_rad < 10000.0, "Mean radiation {mean_rad} too high");
    assert!(min_rad >= 0.0, "Radiation should be non-negative");
    assert!(max_rad < 12000.0, "Max radiation {max_rad} unreasonably high");

    // Insolation: ~14-15h at this latitude in summer
    assert!(mean_insol > 8.0, "Mean insolation {mean_insol}h too low");
    assert!(max_insol <= 16.0, "Max insolation {max_insol}h too high");
}

#[test]
fn test_gordon_gulch_winter_solstice() {
    let (dem, slope, aspect, lat_grid, lon_grid, _) = load_gordon_gulch();

    let params = SolarParams {
        day: 355, // near winter solstice
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    let (mean_rad, _, _, _) = grid_stats(&result.glob_rad);
    let (mean_insol, _, _, _) = grid_stats(&result.insol_time);

    eprintln!("Winter solstice (day 355): glob_rad={mean_rad:.0} Wh/m², insol={mean_insol:.1}h");

    // Winter at 40°N: much lower radiation
    assert!(mean_rad > 500.0, "Mean radiation {mean_rad} too low");
    assert!(mean_rad < 5000.0, "Mean radiation {mean_rad} too high for winter");
    assert!(mean_insol > 4.0, "Mean insolation {mean_insol}h too low");
    assert!(mean_insol < 10.0, "Mean insolation {mean_insol}h too high for winter");
}

// ============================================================================
// Solar Radiation Tests — Seasonal Pattern
// ============================================================================

#[test]
fn test_gordon_gulch_seasonal_pattern() {
    let (dem, slope, aspect, lat_grid, lon_grid, _) = load_gordon_gulch();

    let seasonal_days = [355u16, 80, 172, 266]; // winter, spring, summer, fall
    let labels = ["Winter (355)", "Spring (80)", "Summer (172)", "Fall (266)"];
    let mut mean_rads = Vec::new();

    for &day in &seasonal_days {
        let params = SolarParams {
            day,
            step: 0.5,
            linke: 3.0,
            albedo: 0.2,
            solar_constant: 1367.0,
        };
        let result =
            rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);
        let (mean_rad, _, _, _) = grid_stats(&result.glob_rad);
        mean_rads.push(mean_rad);
    }

    for (i, label) in labels.iter().enumerate() {
        eprintln!("  {label}: {:.0} Wh/m²", mean_rads[i]);
    }

    // At 40°N: Winter < Spring ≈ Fall < Summer
    assert!(
        mean_rads[0] < mean_rads[1],
        "Winter ({:.0}) should be < Spring ({:.0})",
        mean_rads[0], mean_rads[1]
    );
    assert!(
        mean_rads[1] < mean_rads[2],
        "Spring ({:.0}) should be < Summer ({:.0})",
        mean_rads[1], mean_rads[2]
    );
    assert!(
        mean_rads[2] > mean_rads[3],
        "Summer ({:.0}) should be > Fall ({:.0})",
        mean_rads[2], mean_rads[3]
    );
    assert!(
        mean_rads[0] < mean_rads[3],
        "Winter ({:.0}) should be < Fall ({:.0})",
        mean_rads[0], mean_rads[3]
    );
}

// ============================================================================
// North vs South Facing Slope Analysis
// ============================================================================

#[test]
fn test_gordon_gulch_aspect_effect() {
    let (dem, slope, aspect, lat_grid, lon_grid, _) = load_gordon_gulch();

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    // Collect radiation for north-facing (315-45°) vs south-facing (135-225°) pixels
    // Only consider pixels with meaningful slope (>5°)
    let mut north_rads = Vec::new();
    let mut south_rads = Vec::new();
    let min_slope_rad = 5.0_f64.to_radians();

    for r in 1..dem.rows - 1 {
        for c in 1..dem.cols - 1 {
            let s = slope.get(r, c) as f64;
            let a = aspect.get(r, c) as f64;
            let rad = result.glob_rad.get(r, c) as f64;

            if s.is_nan() || a.is_nan() || rad.is_nan() || s < min_slope_rad {
                continue;
            }

            if a >= 315.0 || a <= 45.0 {
                north_rads.push(rad);
            } else if a >= 135.0 && a <= 225.0 {
                south_rads.push(rad);
            }
        }
    }

    let north_mean: f64 = north_rads.iter().sum::<f64>() / north_rads.len() as f64;
    let south_mean: f64 = south_rads.iter().sum::<f64>() / south_rads.len() as f64;

    eprintln!("North-facing: {:.0} Wh/m² ({} pixels)", north_mean, north_rads.len());
    eprintln!("South-facing: {:.0} Wh/m² ({} pixels)", south_mean, south_rads.len());

    // In Northern Hemisphere summer, south-facing slopes get more radiation
    assert!(
        south_mean > north_mean,
        "South-facing ({south_mean:.0}) should have more radiation than north-facing ({north_mean:.0})"
    );
}

// ============================================================================
// Nodata Handling
// ============================================================================

#[test]
fn test_gordon_gulch_nodata_preservation() {
    let (dem, slope, aspect, lat_grid, lon_grid, _) = load_gordon_gulch();

    let params = SolarParams::default();
    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    // Count nodata in DEM vs output
    let dem_nodata: usize = dem.data.iter().filter(|v| v.is_nan()).count();
    let rad_nodata: usize = result.glob_rad.data.iter().filter(|v| v.is_nan()).count();

    eprintln!("DEM nodata: {dem_nodata}, output nodata: {rad_nodata}");

    // Output should have at least as many nodata as input (edge pixels too)
    assert!(
        rad_nodata >= dem_nodata,
        "Output nodata ({rad_nodata}) should be >= DEM nodata ({dem_nodata})"
    );
}
