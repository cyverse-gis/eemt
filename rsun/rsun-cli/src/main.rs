use clap::{Parser, Subcommand};
use rsun_core::io::{read_geotiff, write_geotiff, compute_latlon_grid};
use rsun_core::terrain::slope_aspect;
use rsun_core::types::SolarParams;
use rsun_core::compute_day;

/// rsun — solar radiation toolkit (Rust port of GRASS GIS r.sun)
#[derive(Parser)]
#[command(name = "rsun", version = env!("CARGO_PKG_VERSION"), about = "Solar radiation computation toolkit")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Compute solar radiation for one or more days
    Compute {
        /// Input DEM GeoTIFF (must be in geographic coordinates, i.e. WGS84)
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
        /// Input DEM GeoTIFF
        #[arg(long)]
        dem: String,

        /// Output slope GeoTIFF (radians)
        #[arg(long)]
        slope_out: String,

        /// Output aspect GeoTIFF (degrees, GRASS cartographic: clockwise from North)
        #[arg(long)]
        aspect_out: String,
    },

    /// Show version and backend info
    Info,
}

/// Parse the day specification into a sorted Vec of day numbers.
/// Handles: "172", "1-365", "all" (respects --year for leap years).
fn parse_days(spec: &str, year: Option<u16>) -> Result<Vec<u16>, String> {
    let is_leap = year.map(is_leap_year).unwrap_or(false);
    let max_day: u16 = if is_leap { 366 } else { 365 };

    if spec == "all" {
        return Ok((1..=max_day).collect());
    }

    if let Some(dash_pos) = spec.find('-') {
        let start_str = &spec[..dash_pos];
        let end_str = &spec[dash_pos + 1..];
        let start: u16 = start_str
            .parse()
            .map_err(|_| format!("Invalid start day in range: '{}'", start_str))?;
        let end: u16 = end_str
            .parse()
            .map_err(|_| format!("Invalid end day in range: '{}'", end_str))?;
        if start < 1 || end > max_day || start > end {
            return Err(format!(
                "Day range {}-{} out of bounds (1-{})",
                start, end, max_day
            ));
        }
        return Ok((start..=end).collect());
    }

    // Single day
    let d: u16 = spec
        .parse()
        .map_err(|_| format!("Invalid day specification: '{}'", spec))?;
    if d < 1 || d > max_day {
        return Err(format!("Day {} out of bounds (1-{})", d, max_day));
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
            println!("Parallel compute: rayon");
        }

        Commands::Terrain { dem, slope_out, aspect_out } => {
            eprintln!("Reading DEM: {}", dem);
            let (dem_grid, geo) = read_geotiff(&dem)?;
            eprintln!("DEM size: {}x{} (rows x cols)", dem_grid.rows, dem_grid.cols);

            eprintln!("Computing slope and aspect...");
            let (slope_grid, aspect_grid) = slope_aspect(&dem_grid, geo.x_res, geo.y_res);

            write_geotiff(&slope_out, &slope_grid, &geo, Some(&dem))?;
            eprintln!("Slope written to: {}", slope_out);

            write_geotiff(&aspect_out, &aspect_grid, &geo, Some(&dem))?;
            eprintln!("Aspect written to: {}", aspect_out);
        }

        Commands::Compute {
            dem,
            day,
            step,
            linke,
            albedo,
            glob_rad,
            insol_time,
            output_dir,
            year,
        } => {
            // Parse day specification
            let days = parse_days(&day, year)?;
            let multi_day = days.len() > 1;

            if multi_day && output_dir.is_none() {
                return Err("--output-dir is required for multi-day computation".to_string());
            }
            if !multi_day && glob_rad.is_none() && insol_time.is_none() && output_dir.is_none() {
                return Err("At least one of --glob-rad, --insol-time, or --output-dir is required".to_string());
            }

            // Set up output directory structure for multi-day mode
            if let Some(ref out_dir) = output_dir {
                let glob_dir = format!("{}/global/daily", out_dir);
                let insol_dir = format!("{}/insol/daily", out_dir);
                std::fs::create_dir_all(&glob_dir)
                    .map_err(|e| format!("Failed to create {}: {}", glob_dir, e))?;
                std::fs::create_dir_all(&insol_dir)
                    .map_err(|e| format!("Failed to create {}: {}", insol_dir, e))?;
            }

            // Read DEM once
            eprintln!("Reading DEM: {}", dem);
            let (dem_grid, geo) = read_geotiff(&dem)?;
            eprintln!("DEM size: {}x{} (rows x cols)", dem_grid.rows, dem_grid.cols);

            // Compute lat/lon grids
            eprintln!("Computing lat/lon coordinate grids...");
            let (lat_grid, lon_grid) = compute_latlon_grid(dem_grid.rows, dem_grid.cols, &geo)?;

            // Compute slope/aspect
            eprintln!("Computing slope and aspect...");
            let (slope_grid, aspect_grid) = slope_aspect(&dem_grid, geo.x_res, geo.y_res);

            let total_days = days.len();

            for (i, &d) in days.iter().enumerate() {
                eprintln!(
                    "Processing day {}/{} (DOY {})...",
                    i + 1,
                    total_days,
                    d
                );

                let params = SolarParams {
                    day: d,
                    step,
                    linke,
                    albedo,
                    solar_constant: 1367.0,
                };

                let result = compute_day(
                    &dem_grid,
                    &slope_grid,
                    &aspect_grid,
                    &lat_grid,
                    &lon_grid,
                    None, // no horizon angles
                    &params,
                );

                // Determine output paths
                let (glob_path, insol_path) = if let Some(ref out_dir) = output_dir {
                    let g = format!("{}/global/daily/total_sun_day_{}.tif", out_dir, d);
                    let ins = format!("{}/insol/daily/hours_sun_day_{}.tif", out_dir, d);
                    (Some(g), Some(ins))
                } else {
                    (glob_rad.clone(), insol_time.clone())
                };

                if let Some(ref path) = glob_path {
                    write_geotiff(path, &result.glob_rad, &geo, Some(&dem))?;
                    eprintln!("  glob_rad  -> {}", path);
                }
                if let Some(ref path) = insol_path {
                    write_geotiff(path, &result.insol_time, &geo, Some(&dem))?;
                    eprintln!("  insol_time -> {}", path);
                }
            }

            eprintln!("Done. Processed {} day(s).", total_days);
        }
    }

    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
