//! Gordon Gulch DEM integration tests — GPU vs CPU comparison.
//!
//! Loads the real Gordon Gulch 10m DEM (434×296, ~128K pixels),
//! runs both CPU and GPU compute paths, and compares results
//! pixel-by-pixel with RMSE and max relative error metrics.
//!
//! Requires: GPU available, GDAL for I/O.

use rsun_core::io::{compute_latlon_grid, read_geotiff};
use rsun_core::terrain::slope_aspect;
use rsun_core::types::{Grid, SolarParams};
use rsun_gpu::buffers::GpuBuffers;
use rsun_gpu::context::GpuContext;
use rsun_gpu::pipeline::RadiationPipeline;

const DEM_PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../data/gordon_gulch/gordongulch_dem_10m_3dep_cog.tif"
);

/// Load Gordon Gulch DEM and compute all derived grids.
fn load_gordon_gulch() -> (Grid, Grid, Grid, Grid, Grid) {
    let (dem, geo) = read_geotiff(DEM_PATH).expect("Failed to read Gordon Gulch DEM");
    let (slope, aspect) = slope_aspect(&dem, geo.x_res, geo.y_res);
    let (lat_grid, lon_grid) =
        compute_latlon_grid(dem.rows, dem.cols, &geo).expect("Failed to compute lat/lon grid");
    (dem, slope, aspect, lat_grid, lon_grid)
}

/// Compare two grids pixel-by-pixel.
/// Returns (rmse, max_rel_error_pct, mean_rel_error_pct, n_compared).
fn compare_grids(gpu: &Grid, cpu: &Grid, min_threshold: f32) -> (f64, f64, f64, usize) {
    let mut sum_sq_err = 0.0_f64;
    let mut max_rel = 0.0_f64;
    let mut sum_rel = 0.0_f64;
    let mut count = 0usize;

    for i in 0..gpu.data.len() {
        let g = gpu.data[i];
        let c = cpu.data[i];

        if g.is_nan() || c.is_nan() || c.abs() < min_threshold {
            continue;
        }

        let diff = (g - c) as f64;
        sum_sq_err += diff * diff;

        let rel = (diff / c as f64).abs() * 100.0;
        if rel > max_rel {
            max_rel = rel;
        }
        sum_rel += rel;
        count += 1;
    }

    let rmse = if count > 0 {
        (sum_sq_err / count as f64).sqrt()
    } else {
        0.0
    };
    let mean_rel = if count > 0 {
        sum_rel / count as f64
    } else {
        0.0
    };

    (rmse, max_rel, mean_rel, count)
}

// ============================================================================
// GPU vs CPU — Single Day Comparison
// ============================================================================

#[test]
fn test_gordon_gulch_gpu_vs_cpu_summer() {
    let ctx = GpuContext::new().expect("GPU required for this test");
    let (dem, slope, aspect, lat_grid, lon_grid) = load_gordon_gulch();

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    // GPU path
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat_grid, &lon_grid);
    let pipeline = RadiationPipeline::new(&ctx);
    let gpu_result = pipeline.compute_day(&ctx, &buffers, &params);

    // CPU path
    let cpu_result =
        rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    // Compare glob_rad
    let (rmse, max_rel, mean_rel, count) =
        compare_grids(&gpu_result.glob_rad, &cpu_result.glob_rad, 10.0);
    eprintln!("Summer (day 172) glob_rad — GPU vs CPU:");
    eprintln!("  RMSE: {rmse:.2} Wh/m²");
    eprintln!("  Max relative error: {max_rel:.3}%");
    eprintln!("  Mean relative error: {mean_rel:.3}%");
    eprintln!("  Pixels compared: {count}");

    assert!(
        mean_rel < 2.0,
        "Mean relative error {mean_rel:.3}% exceeds 2% threshold"
    );
    assert!(
        max_rel < 10.0,
        "Max relative error {max_rel:.3}% exceeds 10% threshold"
    );

    // Compare insol_time
    let (insol_rmse, insol_max_rel, insol_mean_rel, _) =
        compare_grids(&gpu_result.insol_time, &cpu_result.insol_time, 1.0);
    eprintln!("Summer (day 172) insol_time — GPU vs CPU:");
    eprintln!("  RMSE: {insol_rmse:.2} hours");
    eprintln!("  Max relative error: {insol_max_rel:.3}%");
    eprintln!("  Mean relative error: {insol_mean_rel:.3}%");

    assert!(
        insol_mean_rel < 5.0,
        "Insol mean relative error {insol_mean_rel:.3}% exceeds 5%"
    );
}

#[test]
fn test_gordon_gulch_gpu_vs_cpu_winter() {
    let ctx = GpuContext::new().expect("GPU required for this test");
    let (dem, slope, aspect, lat_grid, lon_grid) = load_gordon_gulch();

    let params = SolarParams {
        day: 355,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat_grid, &lon_grid);
    let pipeline = RadiationPipeline::new(&ctx);
    let gpu_result = pipeline.compute_day(&ctx, &buffers, &params);
    let cpu_result =
        rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    let (rmse, max_rel, mean_rel, count) =
        compare_grids(&gpu_result.glob_rad, &cpu_result.glob_rad, 10.0);
    eprintln!("Winter (day 355) glob_rad — GPU vs CPU:");
    eprintln!("  RMSE: {rmse:.2} Wh/m², mean_rel: {mean_rel:.3}%, max_rel: {max_rel:.3}%, n={count}");

    assert!(
        mean_rel < 2.0,
        "Mean relative error {mean_rel:.3}% exceeds 2%"
    );
}

// ============================================================================
// GPU vs CPU — Seasonal Batch (reuse buffers)
// ============================================================================

#[test]
fn test_gordon_gulch_gpu_seasonal_batch() {
    let ctx = GpuContext::new().expect("GPU required for this test");
    let (dem, slope, aspect, lat_grid, lon_grid) = load_gordon_gulch();

    // Upload once, compute 4 days
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat_grid, &lon_grid);
    let pipeline = RadiationPipeline::new(&ctx);

    let seasonal_days = [1u16, 91, 172, 274];
    let labels = ["Winter", "Spring", "Summer", "Fall"];
    let mut gpu_means = Vec::new();
    let mut cpu_means = Vec::new();

    for (i, &day) in seasonal_days.iter().enumerate() {
        let params = SolarParams {
            day,
            step: 0.5,
            linke: 3.0,
            albedo: 0.2,
            solar_constant: 1367.0,
        };

        let gpu_result = pipeline.compute_day(&ctx, &buffers, &params);
        let cpu_result =
            rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

        let gpu_mean = valid_mean(&gpu_result.glob_rad);
        let cpu_mean = valid_mean(&cpu_result.glob_rad);

        let (_, _, mean_rel, _) =
            compare_grids(&gpu_result.glob_rad, &cpu_result.glob_rad, 10.0);

        eprintln!(
            "  {}: GPU={:.0}, CPU={:.0} Wh/m², mean_rel={:.3}%",
            labels[i], gpu_mean, cpu_mean, mean_rel
        );

        gpu_means.push(gpu_mean);
        cpu_means.push(cpu_mean);

        assert!(
            mean_rel < 2.0,
            "{}: mean relative error {mean_rel:.3}% exceeds 2%",
            labels[i]
        );
    }

    // Both GPU and CPU should show same seasonal pattern
    // Winter < Spring < Summer, Summer > Fall
    for means in [&gpu_means, &cpu_means] {
        assert!(means[0] < means[1], "Winter should be < Spring");
        assert!(means[1] < means[2], "Spring should be < Summer");
        assert!(means[2] > means[3], "Summer should be > Fall");
    }
}

// ============================================================================
// GPU Nodata Consistency
// ============================================================================

#[test]
fn test_gordon_gulch_gpu_nodata_consistency() {
    let ctx = GpuContext::new().expect("GPU required for this test");
    let (dem, slope, aspect, lat_grid, lon_grid) = load_gordon_gulch();

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat_grid, &lon_grid);
    let pipeline = RadiationPipeline::new(&ctx);
    let gpu_result = pipeline.compute_day(&ctx, &buffers, &params);
    let cpu_result =
        rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    // Both should have the same nodata pattern
    let gpu_valid: usize = gpu_result.glob_rad.data.iter().filter(|v| !v.is_nan() && **v != 0.0).count();
    let cpu_valid: usize = cpu_result.glob_rad.data.iter().filter(|v| !v.is_nan() && **v != 0.0).count();

    eprintln!("Valid pixels: GPU={gpu_valid}, CPU={cpu_valid}");

    // GPU may have slightly different nodata handling (validity mask vs NaN check)
    // but the difference should be small
    let diff = (gpu_valid as i64 - cpu_valid as i64).unsigned_abs();
    assert!(
        diff < 1000,
        "GPU ({gpu_valid}) and CPU ({cpu_valid}) valid pixel counts differ by {diff}"
    );
}

/// Mean of valid (non-NaN) pixels.
fn valid_mean(grid: &Grid) -> f64 {
    let mut sum = 0.0_f64;
    let mut count = 0usize;
    for &v in &grid.data {
        if !v.is_nan() {
            sum += v as f64;
            count += 1;
        }
    }
    if count > 0 {
        sum / count as f64
    } else {
        0.0
    }
}
