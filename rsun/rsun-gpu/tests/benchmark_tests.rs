use rsun_core::types::{Grid, SolarParams};
use rsun_gpu::buffers::GpuBuffers;
use rsun_gpu::context::GpuContext;
use rsun_gpu::pipeline::RadiationPipeline;
use std::time::Instant;

fn make_test_data(rows: usize, cols: usize) -> (Grid, Grid, Grid, Grid, Grid) {
    let mut dem = Grid::new(rows, cols, f32::NAN);
    let mut slope = Grid::new(rows, cols, f32::NAN);
    let mut aspect = Grid::new(rows, cols, f32::NAN);
    let mut lat = Grid::new(rows, cols, f32::NAN);
    let mut lon = Grid::new(rows, cols, f32::NAN);
    for r in 0..rows {
        for c in 0..cols {
            // Gentle slope to make it more realistic
            dem.set(r, c, 2500.0 + (r as f32) * 0.5);
            slope.set(r, c, 0.05);   // ~3 degrees
            aspect.set(r, c, 180.0); // south-facing
            lat.set(r, c, 40.0_f32.to_radians());
            lon.set(r, c, (-105.0_f32).to_radians());
        }
    }
    (dem, slope, aspect, lat, lon)
}

#[test]
fn test_multi_day_gpu_batch() {
    let ctx = GpuContext::new().expect("GPU required");
    let (dem, slope, aspect, lat, lon) = make_test_data(100, 100);
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = RadiationPipeline::new(&ctx);

    let days: Vec<u16> = (1..=365).collect();

    // GPU: batch all 365 days (DEM stays in GPU memory)
    let gpu_start = Instant::now();
    let mut gpu_results = Vec::new();
    for &day in &days {
        let params = SolarParams {
            day,
            step: 0.5,
            linke: 3.0,
            albedo: 0.2,
            solar_constant: 1367.0,
        };
        let result = pipeline.compute_day(&ctx, &buffers, &params);
        gpu_results.push(result.glob_rad.get(50, 50));
    }
    let gpu_elapsed = gpu_start.elapsed();

    // CPU: batch all 365 days
    let cpu_start = Instant::now();
    let mut cpu_results = Vec::new();
    for &day in &days {
        let params = SolarParams {
            day,
            step: 0.5,
            linke: 3.0,
            albedo: 0.2,
            solar_constant: 1367.0,
        };
        let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat, &lon, None, &params);
        cpu_results.push(result.glob_rad.get(50, 50));
    }
    let cpu_elapsed = cpu_start.elapsed();

    let speedup = cpu_elapsed.as_secs_f64() / gpu_elapsed.as_secs_f64();

    eprintln!("\n=== 365-Day Benchmark (100x100 = 10K pixels) ===");
    eprintln!("GPU: {:.2}s ({:.1}ms/day)", gpu_elapsed.as_secs_f64(), gpu_elapsed.as_millis() as f64 / 365.0);
    eprintln!("CPU: {:.2}s ({:.1}ms/day)", cpu_elapsed.as_secs_f64(), cpu_elapsed.as_millis() as f64 / 365.0);
    eprintln!("Speedup: {speedup:.1}x");

    // Verify GPU and CPU agree on seasonal pattern
    // Summer (day 172) should be highest
    let gpu_summer = gpu_results[171];
    let cpu_summer = cpu_results[171];
    let rel_err = ((gpu_summer - cpu_summer) / cpu_summer).abs() * 100.0;
    eprintln!("\nDay 172 comparison: GPU={gpu_summer:.1} CPU={cpu_summer:.1} err={rel_err:.2}%");

    assert!(
        rel_err < 1.0,
        "GPU vs CPU summer radiation error too large: {rel_err:.2}%"
    );

    // GPU should be faster (even at this small size, dispatch overhead should be < CPU compute)
    eprintln!("GPU speedup: {speedup:.1}x");
}

#[test]
fn test_gpu_throughput_larger_grid() {
    // Test with a larger grid to measure GPU utilization
    let ctx = GpuContext::new().expect("GPU required");
    let (dem, slope, aspect, lat, lon) = make_test_data(500, 500);
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = RadiationPipeline::new(&ctx);

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    // Warm up
    let _ = pipeline.compute_day(&ctx, &buffers, &params);

    // Benchmark: 10 days
    let gpu_start = Instant::now();
    for day in 170..180 {
        let p = SolarParams { day, ..params };
        let _ = pipeline.compute_day(&ctx, &buffers, &p);
    }
    let gpu_elapsed = gpu_start.elapsed();

    // CPU benchmark: 10 days
    let cpu_start = Instant::now();
    for day in 170..180 {
        let p = SolarParams { day, ..params };
        let _ = rsun_core::compute_day(&dem, &slope, &aspect, &lat, &lon, None, &p);
    }
    let cpu_elapsed = cpu_start.elapsed();

    let speedup = cpu_elapsed.as_secs_f64() / gpu_elapsed.as_secs_f64();
    let pixels = 500 * 500;

    eprintln!("\n=== 10-Day Benchmark (500x500 = 250K pixels) ===");
    eprintln!("GPU: {:.2}s ({:.0}ms/day, {:.0} Mpixels/s)",
        gpu_elapsed.as_secs_f64(),
        gpu_elapsed.as_millis() as f64 / 10.0,
        pixels as f64 * 10.0 / gpu_elapsed.as_secs_f64() / 1e6);
    eprintln!("CPU: {:.2}s ({:.0}ms/day, {:.0} Mpixels/s)",
        cpu_elapsed.as_secs_f64(),
        cpu_elapsed.as_millis() as f64 / 10.0,
        pixels as f64 * 10.0 / cpu_elapsed.as_secs_f64() / 1e6);
    eprintln!("Speedup: {speedup:.1}x");
}
