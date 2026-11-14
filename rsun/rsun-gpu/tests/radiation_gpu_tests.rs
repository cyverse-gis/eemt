use rsun_core::types::{Grid, SolarParams};
use rsun_gpu::buffers::GpuBuffers;
use rsun_gpu::context::GpuContext;
use rsun_gpu::pipeline::RadiationPipeline;

/// Helper: create a flat test DEM with uniform lat/lon
fn make_flat_test_data(rows: usize, cols: usize) -> (Grid, Grid, Grid, Grid, Grid) {
    let mut dem = Grid::new(rows, cols, f32::NAN);
    let mut slope = Grid::new(rows, cols, f32::NAN);
    let mut aspect = Grid::new(rows, cols, f32::NAN);
    let mut lat = Grid::new(rows, cols, f32::NAN);
    let mut lon = Grid::new(rows, cols, f32::NAN);

    for r in 0..rows {
        for c in 0..cols {
            dem.set(r, c, 2500.0);
            slope.set(r, c, 0.0);
            aspect.set(r, c, 0.0);
            lat.set(r, c, 40.0_f32.to_radians());
            lon.set(r, c, (-105.0_f32).to_radians());
        }
    }

    (dem, slope, aspect, lat, lon)
}

#[test]
fn test_gpu_radiation_flat_terrain() {
    let ctx = GpuContext::new().expect("GPU required");
    let (dem, slope, aspect, lat, lon) = make_flat_test_data(10, 10);
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = RadiationPipeline::new(&ctx);

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let result = pipeline.compute_day(&ctx, &buffers, &params);

    let gpu_rad = result.glob_rad.get(5, 5);
    let gpu_insol = result.insol_time.get(5, 5);

    eprintln!("GPU flat terrain (day 172): glob_rad={gpu_rad:.1} Wh/m², insol={gpu_insol:.1}h");

    assert!(gpu_rad > 1000.0, "GPU glob_rad should be >1000: got {gpu_rad}");
    assert!(gpu_rad < 12000.0, "GPU glob_rad should be <12000: got {gpu_rad}");
    assert!(gpu_insol > 10.0, "GPU insol should be >10h: got {gpu_insol}");
    assert!(gpu_insol < 18.0, "GPU insol should be <18h: got {gpu_insol}");
}

#[test]
fn test_gpu_vs_cpu_comparison() {
    // Run both GPU and CPU on the same input, compare results
    let ctx = GpuContext::new().expect("GPU required");
    let (dem, slope, aspect, lat, lon) = make_flat_test_data(10, 10);

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    // GPU
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = RadiationPipeline::new(&ctx);
    let gpu_result = pipeline.compute_day(&ctx, &buffers, &params);

    // CPU
    let cpu_result = rsun_core::compute_day(&dem, &slope, &aspect, &lat, &lon, None, &params);

    // Compare center pixel
    let gpu_rad = gpu_result.glob_rad.get(5, 5);
    let cpu_rad = cpu_result.glob_rad.get(5, 5);
    let gpu_insol = gpu_result.insol_time.get(5, 5);
    let cpu_insol = cpu_result.insol_time.get(5, 5);

    eprintln!("CPU: glob_rad={cpu_rad:.1}, insol={cpu_insol:.1}h");
    eprintln!("GPU: glob_rad={gpu_rad:.1}, insol={gpu_insol:.1}h");

    let rel_err_rad = ((gpu_rad - cpu_rad) / cpu_rad).abs() * 100.0;
    let rel_err_insol = ((gpu_insol - cpu_insol) / cpu_insol).abs() * 100.0;

    eprintln!("Relative error: glob_rad={rel_err_rad:.3}%, insol={rel_err_insol:.3}%");

    // Accept < 1% for radiation (primary output), < 5% for insol_time
    // (insol_time is more sensitive to f32 rounding in sunrise/sunset step alignment)
    assert!(
        rel_err_rad < 1.0,
        "GPU vs CPU glob_rad difference too large: {rel_err_rad:.3}%"
    );
    assert!(
        rel_err_insol < 5.0,
        "GPU vs CPU insol_time difference too large: {rel_err_insol:.3}%"
    );
}

#[test]
fn test_gpu_seasonal_variation() {
    let ctx = GpuContext::new().expect("GPU required");
    let (dem, slope, aspect, lat, lon) = make_flat_test_data(5, 5);
    let buffers = GpuBuffers::new(&ctx, &dem, &slope, &aspect, &lat, &lon);
    let pipeline = RadiationPipeline::new(&ctx);

    let mut seasonal_rad = Vec::new();
    for day in [1u16, 91, 172, 274] {
        let params = SolarParams {
            day,
            step: 0.5,
            linke: 3.0,
            albedo: 0.2,
            solar_constant: 1367.0,
        };
        let result = pipeline.compute_day(&ctx, &buffers, &params);
        let rad = result.glob_rad.get(2, 2);
        eprintln!("Day {day}: glob_rad={rad:.1} Wh/m²");
        seasonal_rad.push(rad);
    }

    // Winter < equinoxes < summer
    assert!(
        seasonal_rad[0] < seasonal_rad[1],
        "Winter ({:.0}) should be less than spring ({:.0})",
        seasonal_rad[0],
        seasonal_rad[1]
    );
    assert!(
        seasonal_rad[1] < seasonal_rad[2],
        "Spring ({:.0}) should be less than summer ({:.0})",
        seasonal_rad[1],
        seasonal_rad[2]
    );
    assert!(
        seasonal_rad[2] > seasonal_rad[3],
        "Summer ({:.0}) should be more than fall ({:.0})",
        seasonal_rad[2],
        seasonal_rad[3]
    );
}
