use clap::{Parser, Subcommand};
use rsun_core::horizon::compute_horizons;
use rsun_core::io::{compute_latlon_grid, read_geotiff, write_geotiff};
use rsun_core::terrain::slope_aspect;
use rsun_core::types::{Grid, SolarParams, MONTHS, MONTH_DAYS, MONTH_DAYS_LEAP};
use std::time::Instant;

/// rsun — solar radiation toolkit (Rust port of GRASS GIS r.sun)
#[derive(Parser)]
#[command(name = "rsun", version = env!("CARGO_PKG_VERSION"), about = "GPU-accelerated solar radiation computation")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Compute solar radiation for one or more days
    Compute {
        /// Input DEM GeoTIFF
        #[arg(long)]
        dem: String,

        /// Day specification: single day ("172"), range ("1-365"), or "all"
        #[arg(long)]
        day: String,

        /// Time step in decimal hours (default: 0.5)
        #[arg(long, default_value_t = 0.5)]
        step: f64,

        /// Linke turbidity factor (default: 3.0)
        #[arg(long, default_value_t = 3.0)]
        linke: f64,

        /// Surface albedo (default: 0.2)
        #[arg(long, default_value_t = 0.2)]
        albedo: f64,

        /// GPU mode: "auto" (default), "cpu", or GPU device index
        #[arg(long, default_value = "auto")]
        gpu: String,

        /// Output global radiation GeoTIFF (single-day mode)
        #[arg(long)]
        glob_rad: Option<String>,

        /// Output insolation time GeoTIFF (single-day mode)
        #[arg(long)]
        insol_time: Option<String>,

        /// Output directory (multi-day mode)
        #[arg(long)]
        output_dir: Option<String>,

        /// Calendar year for leap year support
        #[arg(long)]
        year: Option<u16>,

        /// Number of horizon directions for topographic shading (0 = disabled, 36 = typical)
        #[arg(long, default_value_t = 0)]
        horizons: usize,

        /// Generate monthly sum GeoTIFFs after daily computation (multi-day mode only)
        #[arg(long)]
        monthly_sums: bool,
    },

    /// Compute slope and aspect from a DEM
    Terrain {
        #[arg(long)]
        dem: String,
        #[arg(long)]
        slope_out: String,
        #[arg(long)]
        aspect_out: String,
    },

    /// Show version, GPU, and backend info
    Info,
}

fn parse_days(spec: &str, year: Option<u16>) -> Result<Vec<u16>, String> {
    let is_leap = year.map(is_leap_year).unwrap_or(false);
    let max_day: u16 = if is_leap { 366 } else { 365 };

    if spec == "all" {
        return Ok((1..=max_day).collect());
    }
    if let Some(dash_pos) = spec.find('-') {
        let start: u16 = spec[..dash_pos]
            .parse()
            .map_err(|_| format!("Invalid start day: '{}'", &spec[..dash_pos]))?;
        let end: u16 = spec[dash_pos + 1..]
            .parse()
            .map_err(|_| format!("Invalid end day: '{}'", &spec[dash_pos + 1..]))?;
        if start < 1 || end > max_day || start > end {
            return Err(format!("Day range {start}-{end} out of bounds (1-{max_day})"));
        }
        return Ok((start..=end).collect());
    }
    let d: u16 = spec.parse().map_err(|_| format!("Invalid day: '{spec}'"))?;
    if d < 1 || d > max_day {
        return Err(format!("Day {d} out of bounds (1-{max_day})"));
    }
    Ok(vec![d])
}

fn is_leap_year(year: u16) -> bool {
    let y = year as u32;
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

fn run() -> Result<(), String> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Info => {
            println!("rsun v{}", env!("CARGO_PKG_VERSION"));
            println!("Backend: rsun-core (Rust port of GRASS GIS r.sun)");
            println!("GDAL support: enabled");
            println!();

            // CUDA devices
            #[cfg(feature = "cuda")]
            {
                let cuda_devs = rsun_cuda::CudaHorizonContext::list_devices();
                if cuda_devs.is_empty() {
                    println!("CUDA: not available");
                } else {
                    println!("CUDA devices ({}):", cuda_devs.len());
                    for d in &cuda_devs {
                        println!("  {d}");
                    }
                }
                println!();
            }

            // wgpu/Vulkan adapters
            let adapters = rsun_gpu::context::GpuContext::list_adapters();
            if adapters.is_empty() {
                println!("wgpu: none detected");
            } else {
                println!("wgpu adapters ({}):", adapters.len());
                for (i, a) in adapters.iter().enumerate() {
                    println!(
                        "  [{i}] {} ({}, {}, max_buffer={}MB)",
                        a.name,
                        a.backend,
                        a.device_type,
                        a.vram_bytes / (1024 * 1024)
                    );
                }
            }
        }

        Commands::Terrain {
            dem,
            slope_out,
            aspect_out,
        } => {
            eprintln!("Reading DEM: {dem}");
            let (dem_grid, geo) = read_geotiff(&dem)?;
            eprintln!(
                "DEM size: {}x{} (rows x cols)",
                dem_grid.rows, dem_grid.cols
            );
            eprintln!("Computing slope and aspect...");
            let (slope_grid, aspect_grid) = slope_aspect(&dem_grid, geo.x_res, geo.y_res);
            write_geotiff(&slope_out, &slope_grid, &geo, Some(&dem))?;
            write_geotiff(&aspect_out, &aspect_grid, &geo, Some(&dem))?;
            eprintln!("Wrote: {slope_out}, {aspect_out}");
        }

        Commands::Compute {
            dem,
            day,
            step,
            linke,
            albedo,
            gpu,
            glob_rad,
            insol_time,
            output_dir,
            year,
            horizons,
            monthly_sums,
        } => {
            let days = parse_days(&day, year)?;
            let multi_day = days.len() > 1;

            if multi_day && output_dir.is_none() {
                return Err("--output-dir required for multi-day computation".to_string());
            }
            if !multi_day && glob_rad.is_none() && insol_time.is_none() && output_dir.is_none() {
                return Err(
                    "At least one of --glob-rad, --insol-time, or --output-dir required"
                        .to_string(),
                );
            }

            if let Some(ref out_dir) = output_dir {
                std::fs::create_dir_all(format!("{out_dir}/global/daily"))
                    .map_err(|e| format!("Failed to create output dirs: {e}"))?;
                std::fs::create_dir_all(format!("{out_dir}/insol/daily"))
                    .map_err(|e| format!("Failed to create output dirs: {e}"))?;
                if monthly_sums {
                    std::fs::create_dir_all(format!("{out_dir}/global/monthly"))
                        .map_err(|e| format!("Failed to create output dirs: {e}"))?;
                    std::fs::create_dir_all(format!("{out_dir}/insol/monthly"))
                        .map_err(|e| format!("Failed to create output dirs: {e}"))?;
                }
            }

            // Read DEM
            eprintln!("Reading DEM: {dem}");
            let (dem_grid, geo) = read_geotiff(&dem)?;
            let n_pixels = dem_grid.rows * dem_grid.cols;
            eprintln!(
                "DEM size: {}x{} ({} pixels)",
                dem_grid.rows, dem_grid.cols, n_pixels
            );

            // Compute lat/lon and terrain
            eprintln!("Computing lat/lon coordinate grids...");
            let (lat_grid, lon_grid) =
                compute_latlon_grid(dem_grid.rows, dem_grid.cols, &geo)?;
            eprintln!("Computing slope and aspect...");
            let (slope_grid, aspect_grid) = slope_aspect(&dem_grid, geo.x_res, geo.y_res);

            // Try GPU (need context before horizons so we can use GPU horizon pipeline)
            // Try GPU
            let use_gpu = gpu != "cpu";
            let gpu_ctx = if use_gpu {
                eprintln!("Initializing GPU...");
                let ctx_opt = if let Ok(idx) = gpu.parse::<usize>() {
                    eprintln!("  Requesting GPU device index {idx}...");
                    rsun_gpu::context::GpuContext::with_index(idx)
                } else {
                    rsun_gpu::context::GpuContext::new()
                };
                match ctx_opt {
                    Some(ctx) => {
                        eprintln!(
                            "GPU: {} ({}, max_buffer={}MB)",
                            ctx.adapter_name,
                            ctx.backend,
                            ctx.vram_bytes / (1024 * 1024)
                        );
                        Some(ctx)
                    }
                    None => {
                        eprintln!("No GPU available, falling back to CPU");
                        None
                    }
                }
            } else {
                eprintln!("GPU disabled (--gpu cpu), using CPU backend");
                None
            };

            // Horizon pre-computation (optional topographic shading)
            // Priority: CUDA (no buffer limits) > wgpu (2GB limit) > CPU (rayon)
            let horizon_grid = if horizons > 0 {
                eprintln!("Computing horizon angles ({horizons} directions)...");
                let t0 = Instant::now();
                let horizon_buf_bytes = (n_pixels as u64) * (horizons as u64) * 4;

                let hg = compute_horizons_best(
                    &dem_grid, &slope_grid, &aspect_grid, &lat_grid, &lon_grid,
                    &geo, horizons, horizon_buf_bytes, &gpu, &gpu_ctx,
                )?;

                eprintln!("  Horizons computed in {:.1}s", t0.elapsed().as_secs_f64());
                Some(hg)
            } else {
                None
            };

            let total_days = days.len();
            let start_time = Instant::now();

            // Try CUDA radiation (supports horizons natively)
            let use_cuda = gpu != "cpu";
            #[cfg(feature = "cuda")]
            let cuda_radiation = if use_cuda {
                let cuda_device = if let Ok(idx) = gpu.parse::<usize>() { idx } else { 0 };
                match rsun_cuda::CudaRadiationContext::new(
                    cuda_device, &dem_grid, &slope_grid, &aspect_grid, &lat_grid,
                    horizon_grid.as_ref(),
                ) {
                    Ok(ctx) => {
                        eprintln!("CUDA radiation pipeline ready on {} ({} pixels uploaded)",
                            ctx.device_name, n_pixels);
                        Some(ctx)
                    }
                    Err(e) => {
                        eprintln!("CUDA radiation unavailable: {e}");
                        None
                    }
                }
            } else {
                None
            };
            #[cfg(not(feature = "cuda"))]
            let cuda_radiation: Option<()> = None;

            // Fallback: wgpu GPU radiation (no horizon support)
            let use_wgpu_radiation = cuda_radiation.is_none()
                && gpu_ctx.is_some()
                && horizon_grid.is_none();

            if false { let _ = &cuda_radiation; } // suppress unused warning

            #[cfg(feature = "cuda")]
            if let Some(ref cuda_ctx) = cuda_radiation {
                // === CUDA RADIATION PATH (with horizon shading) ===
                eprintln!("Processing {} days on CUDA{}...", total_days,
                    if horizon_grid.is_some() { " with horizon shading" } else { "" });

                for (i, &d) in days.iter().enumerate() {
                    let params = SolarParams {
                        day: d, step, linke, albedo, solar_constant: 1367.0,
                    };

                    let result = cuda_ctx.compute_day(&params)?;

                    if (i + 1) % 50 == 0 || i + 1 == total_days || total_days == 1 {
                        let elapsed = start_time.elapsed().as_secs_f64();
                        let rate = (i + 1) as f64 / elapsed;
                        eprintln!("  Day {}/{} (DOY {}) — {:.1} days/sec", i + 1, total_days, d, rate);
                    }

                    write_outputs(&result, d, &glob_rad, &insol_time, &output_dir, &geo, &dem)?;
                }
            } else if use_wgpu_radiation {
                let ctx = gpu_ctx.as_ref().unwrap();
                // === wgpu GPU RADIATION PATH (no horizons) ===
                eprintln!("Uploading data to wgpu GPU...");
                let buffers = rsun_gpu::buffers::GpuBuffers::new(
                    ctx, &dem_grid, &slope_grid, &aspect_grid, &lat_grid, &lon_grid,
                );
                let pipeline = rsun_gpu::pipeline::RadiationPipeline::new(ctx);
                eprintln!("wgpu radiation pipeline ready. Processing {} days...", total_days);

                for (i, &d) in days.iter().enumerate() {
                    let params = SolarParams {
                        day: d, step, linke, albedo, solar_constant: 1367.0,
                    };
                    let result = pipeline.compute_day(ctx, &buffers, &params);

                    if (i + 1) % 50 == 0 || i + 1 == total_days || total_days == 1 {
                        let elapsed = start_time.elapsed().as_secs_f64();
                        let rate = (i + 1) as f64 / elapsed;
                        eprintln!("  Day {}/{} (DOY {}) — {:.1} days/sec", i + 1, total_days, d, rate);
                    }
                    write_outputs(&result, d, &glob_rad, &insol_time, &output_dir, &geo, &dem)?;
                }
            } else {
                // === CPU RADIATION PATH ===
                if horizon_grid.is_some() {
                    eprintln!("Processing {} days on CPU with horizon shading...", total_days);
                } else {
                    eprintln!("Processing {} days on CPU...", total_days);
                }

                for (i, &d) in days.iter().enumerate() {
                    let params = SolarParams {
                        day: d,
                        step,
                        linke,
                        albedo,
                        solar_constant: 1367.0,
                    };

                    let result = rsun_core::compute_day(
                        &dem_grid,
                        &slope_grid,
                        &aspect_grid,
                        &lat_grid,
                        &lon_grid,
                        horizon_grid.as_ref(),
                        &params,
                    );

                    if (i + 1) % 50 == 0 || i + 1 == total_days || total_days == 1 {
                        let elapsed = start_time.elapsed().as_secs_f64();
                        let rate = (i + 1) as f64 / elapsed;
                        eprintln!(
                            "  Day {}/{} (DOY {}) — {:.1} days/sec",
                            i + 1,
                            total_days,
                            d,
                            rate
                        );
                    }

                    write_outputs(
                        &rsun_core::types::DayResult {
                            day: d,
                            glob_rad: result.glob_rad,
                            insol_time: result.insol_time,
                        },
                        d,
                        &glob_rad,
                        &insol_time,
                        &output_dir,
                        &geo,
                        &dem,
                    )?;
                }
            }

            let total_elapsed = start_time.elapsed();
            eprintln!(
                "Done. {} days in {:.1}s ({:.1} days/sec, {} backend)",
                total_days,
                total_elapsed.as_secs_f64(),
                total_days as f64 / total_elapsed.as_secs_f64(),
                if cuda_radiation.is_some() { "CUDA" }
                else if use_wgpu_radiation { "wgpu" }
                else { "CPU" }
            );

            // Monthly sum generation
            if monthly_sums {
                if let Some(ref out_dir) = output_dir {
                    eprintln!("Generating monthly sums...");
                    let is_leap = year.map(is_leap_year).unwrap_or(false);
                    let month_days = if is_leap { &MONTH_DAYS_LEAP } else { &MONTH_DAYS };

                    for (month_idx, &(start_day, end_day)) in month_days.iter().enumerate() {
                        // Collect daily files for this month that were actually computed
                        let month_days_in_range: Vec<u16> = (start_day..=end_day)
                            .filter(|d| days.contains(d))
                            .collect();

                        if month_days_in_range.is_empty() {
                            continue;
                        }

                        let month_name = MONTHS[month_idx];

                        // Sum glob_rad
                        let glob_sum = sum_daily_geotiffs(
                            &month_days_in_range,
                            &format!("{out_dir}/global/daily"),
                            "total_sun_day",
                        )?;
                        let glob_out = format!(
                            "{out_dir}/global/monthly/total_sun_{month_name}_sum.tif"
                        );
                        write_geotiff(&glob_out, &glob_sum, &geo, Some(&dem))?;

                        // Sum insol_time
                        let insol_sum = sum_daily_geotiffs(
                            &month_days_in_range,
                            &format!("{out_dir}/insol/daily"),
                            "hours_sun_day",
                        )?;
                        let insol_out = format!(
                            "{out_dir}/insol/monthly/hours_sun_{month_name}_sum.tif"
                        );
                        write_geotiff(&insol_out, &insol_sum, &geo, Some(&dem))?;

                        eprintln!(
                            "  {month_name}: {} days summed",
                            month_days_in_range.len()
                        );
                    }
                    eprintln!("Monthly sums complete.");
                }
            }
        }
    }

    Ok(())
}

fn write_outputs(
    result: &rsun_core::types::DayResult,
    day: u16,
    glob_rad: &Option<String>,
    insol_time: &Option<String>,
    output_dir: &Option<String>,
    geo: &rsun_core::types::GeoTransform,
    dem_path: &str,
) -> Result<(), String> {
    let (glob_path, insol_path) = if let Some(ref out_dir) = output_dir {
        (
            Some(format!("{out_dir}/global/daily/total_sun_day_{day}.tif")),
            Some(format!("{out_dir}/insol/daily/hours_sun_day_{day}.tif")),
        )
    } else {
        (glob_rad.clone(), insol_time.clone())
    };

    if let Some(ref path) = glob_path {
        write_geotiff(path, &result.glob_rad, geo, Some(dem_path))?;
    }
    if let Some(ref path) = insol_path {
        write_geotiff(path, &result.insol_time, geo, Some(dem_path))?;
    }
    Ok(())
}

/// Compute horizons using the best available backend: CUDA > wgpu > CPU.
fn compute_horizons_best(
    dem_grid: &Grid,
    slope_grid: &Grid,
    aspect_grid: &Grid,
    lat_grid: &Grid,
    lon_grid: &Grid,
    geo: &rsun_core::types::GeoTransform,
    horizons: usize,
    horizon_buf_bytes: u64,
    gpu_flag: &str,
    gpu_ctx: &Option<rsun_gpu::context::GpuContext>,
) -> Result<rsun_core::horizon::HorizonGrid, String> {
    // Try CUDA first (no buffer size limits)
    #[cfg(feature = "cuda")]
    {
        let cuda_device = if let Ok(idx) = gpu_flag.parse::<usize>() {
            idx
        } else {
            0
        };
        match rsun_cuda::CudaHorizonContext::new(cuda_device) {
            Ok(ctx) => {
                eprintln!("  Using CUDA horizon pipeline ({:.1} GB, {})...",
                    horizon_buf_bytes as f64 / 1e9, ctx.device_name);
                return ctx.compute_horizons(dem_grid, geo.x_res, geo.y_res, horizons);
            }
            Err(e) => {
                eprintln!("  CUDA unavailable: {e}");
            }
        }
    }

    // Try wgpu (2 GB buffer limit)
    let wgpu_ok = gpu_ctx.is_some() && horizon_buf_bytes < (2 << 30);
    if wgpu_ok {
        let ctx = gpu_ctx.as_ref().unwrap();
        eprintln!("  Using wgpu horizon pipeline ({:.1} GB buffer)...",
            horizon_buf_bytes as f64 / 1e9);
        let buffers = rsun_gpu::buffers::GpuBuffers::new(
            ctx, dem_grid, slope_grid, aspect_grid, lat_grid, lon_grid,
        );
        let h_pipeline = rsun_gpu::pipeline::HorizonPipeline::new(ctx);
        let h_buf = h_pipeline.create_buffer(ctx, buffers.n_pixels, horizons as u32);
        h_pipeline.compute(ctx, &buffers, &h_buf, geo.x_res, geo.y_res);
        let angles_flat = h_pipeline.readback(ctx, &h_buf);

        use std::f64::consts::PI;
        let azimuths: Vec<f64> = (0..horizons)
            .map(|d| 2.0 * PI * d as f64 / horizons as f64)
            .collect();
        return Ok(rsun_core::horizon::HorizonGrid {
            angles: angles_flat,
            rows: dem_grid.rows,
            cols: dem_grid.cols,
            n_directions: horizons,
            azimuths,
        });
    }

    // Fall back to CPU
    if gpu_ctx.is_some() {
        eprintln!("  Horizon buffer {:.1} GB exceeds wgpu limit, falling back to CPU...",
            horizon_buf_bytes as f64 / 1e9);
    }
    eprintln!("  Using CPU horizon computation (rayon parallel)...");
    Ok(compute_horizons(dem_grid, geo.x_res, geo.y_res, horizons))
}

/// Sum a set of daily GeoTIFFs into a single Grid (pixel-wise addition).
/// NaN values are propagated: a pixel is NaN if any contributing day is NaN.
fn sum_daily_geotiffs(days: &[u16], dir: &str, prefix: &str) -> Result<Grid, String> {
    let first_path = format!("{dir}/{prefix}_{}.tif", days[0]);
    let (first, _) = read_geotiff(&first_path)?;

    let mut sum_data: Vec<f64> = first.data.iter().map(|&v| v as f64).collect();

    for &day in &days[1..] {
        let path = format!("{dir}/{prefix}_{day}.tif");
        let (grid, _) = read_geotiff(&path)?;
        for (i, &v) in grid.data.iter().enumerate() {
            sum_data[i] += v as f64;
        }
    }

    let mut result = Grid::new(first.rows, first.cols, f32::NAN);
    result.data = sum_data.iter().map(|&v| v as f32).collect();
    Ok(result)
}

fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}
