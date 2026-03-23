use clap::{Parser, Subcommand};
use rsun_core::io::{compute_latlon_grid, read_geotiff, write_geotiff};
use rsun_core::terrain::slope_aspect;
use rsun_core::types::SolarParams;
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

            let adapters = rsun_gpu::context::GpuContext::list_adapters();
            if adapters.is_empty() {
                println!("GPU: none detected");
            } else {
                println!("GPU adapters ({}):", adapters.len());
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

            // Try GPU
            let use_gpu = gpu != "cpu";
            let gpu_ctx = if use_gpu {
                eprintln!("Initializing GPU...");
                match rsun_gpu::context::GpuContext::new() {
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

            let total_days = days.len();
            let start_time = Instant::now();

            if let Some(ref ctx) = gpu_ctx {
                // === GPU PATH ===
                eprintln!("Uploading data to GPU...");
                let buffers = rsun_gpu::buffers::GpuBuffers::new(
                    ctx,
                    &dem_grid,
                    &slope_grid,
                    &aspect_grid,
                    &lat_grid,
                    &lon_grid,
                );
                let pipeline = rsun_gpu::pipeline::RadiationPipeline::new(ctx);
                eprintln!("GPU pipeline ready. Processing {} days...", total_days);

                for (i, &d) in days.iter().enumerate() {
                    let params = SolarParams {
                        day: d,
                        step,
                        linke,
                        albedo,
                        solar_constant: 1367.0,
                    };

                    let result = pipeline.compute_day(ctx, &buffers, &params);

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

                    write_outputs(&result, d, &glob_rad, &insol_time, &output_dir, &geo, &dem)?;
                }
            } else {
                // === CPU PATH ===
                eprintln!("Processing {} days on CPU...", total_days);

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
                        None,
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
                if gpu_ctx.is_some() { "GPU" } else { "CPU" }
            );
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

fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}
