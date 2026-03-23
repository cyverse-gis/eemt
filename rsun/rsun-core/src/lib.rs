pub mod types;
pub mod solar;
pub mod radiation;
pub mod horizon;
pub mod terrain;

#[cfg(feature = "io")]
pub mod io;

use rayon::prelude::*;

use crate::types::{Grid, SolarParams, DayResult};
use crate::horizon::HorizonGrid;
use crate::solar::{declination, corrected_solar_constant, sunrise_sunset, solar_position, hour_to_time_angle, hourangle};
use crate::radiation::{brad, drad, cos_incidence};

/// Compute a full day of solar radiation for every pixel in the DEM.
///
/// Ported from GRASS GIS r.sun `joules2()` + `calculate()`.
///
/// # Arguments
/// * `dem`       - Elevation grid [metres]
/// * `slope`     - Slope grid [radians]
/// * `aspect`    - Aspect grid [degrees, GRASS cartographic: clockwise from North]
/// * `lat_grid`  - Latitude grid [radians]
/// * `lon_grid`  - Longitude grid [radians] (reserved for future use)
/// * `horizons`  - Optional pre-computed horizon angles; if `None` shadows are not checked
/// * `params`    - Day-constant parameters (day, step, linke, albedo, solar_constant)
///
/// Returns a [`DayResult`] containing:
/// * `glob_rad`  - Global radiation [Wh/m²]
/// * `insol_time`- Sunshine duration [hours]
pub fn compute_day(
    dem: &Grid,
    slope: &Grid,
    aspect: &Grid,
    lat_grid: &Grid,
    _lon_grid: &Grid,
    horizons: Option<&HorizonGrid>,
    params: &SolarParams,
) -> DayResult {
    let rows = dem.rows;
    let cols = dem.cols;

    // Day-level constants
    let decl = declination(params.day);
    let g_norm_extra = corrected_solar_constant(params.day, params.solar_constant);
    let step_h = params.step;          // time step in hours
    let ha_step = step_h * hourangle(); // time step in radians

    // Output buffers initialised to nodata (NaN)
    let n = rows * cols;
    let mut glob_flat = vec![0.0_f32; n];
    let mut insol_flat = vec![0.0_f32; n];

    // Mark pixels that are nodata in the dem so we can skip them
    let valid: Vec<bool> = (0..n)
        .map(|i| {
            let r = i / cols;
            let c = i % cols;
            !dem.is_nodata(r, c) && !lat_grid.is_nodata(r, c)
        })
        .collect();

    // --- Parallel computation over pixels ---
    let results: Vec<(usize, f32, f32)> = (0..n)
        .into_par_iter()
        .filter(|&i| valid[i])
        .map(|i| {
            let row = i / cols;
            let col = i % cols;

            let lat = lat_grid.get(row, col) as f64;   // radians
            let elev = dem.get(row, col) as f64;         // metres
            let slope_rad = slope.get(row, col) as f64; // radians

            // Convert GRASS cartographic aspect (degrees CW from North) to
            // r.sun internal convention (radians, 0 = east, CCW positive).
            let asp_deg = aspect.get(row, col) as f64;
            let aspect_rad: f64 = if asp_deg == 0.0 {
                0.0
            } else if asp_deg < 90.0 {
                (90.0 - asp_deg).to_radians()
            } else {
                (450.0 - asp_deg).to_radians()
            };

            // Sunrise / sunset for this latitude and day
            let (sunrise_h, sunset_h) = sunrise_sunset(lat, decl);

            // Snap first time step to the grid of step_h intervals that
            // GRASS uses: first angle = ceil(sunrise / step) * step, clamped.
            let first_h = if sunrise_h <= 0.0 {
                step_h
            } else {
                let n_steps = (sunrise_h / step_h).ceil();
                n_steps * step_h
            };

            let first_angle = hour_to_time_angle(first_h);
            let last_angle = hour_to_time_angle(sunset_h);

            let mut glob_acc: f64 = 0.0;
            let mut insol_acc: f64 = 0.0;

            let mut time_angle = first_angle;
            while time_angle <= last_angle + 1e-9 {
                let (solar_alt, solar_az) = solar_position(lat, decl, time_angle);

                if solar_alt > 0.0 {
                    // --- Shadow check via horizon interpolation ---
                    let shadowed = if let Some(hgrid) = horizons {
                        let horizon_alt = hgrid.interpolate(row, col, solar_az);
                        solar_alt <= horizon_alt
                    } else {
                        false
                    };

                    // Cosine of incidence on the tilted surface
                    let s0 = cos_incidence(slope_rad, aspect_rad, lat, decl, time_angle);

                    // Beam radiation (only when not shadowed and s0 > 0)
                    let beam_contrib = if !shadowed && s0 > 0.0 {
                        let (beam_t, beam_h) = brad(s0, solar_alt, elev, params.linke, 1.0, g_norm_extra);
                        let (diff_t, refl_t) = drad(
                            s0, beam_h, solar_alt, solar_az,
                            slope_rad, aspect_rad,
                            params.linke, params.albedo, 1.0, g_norm_extra,
                        );
                        beam_t + diff_t + refl_t
                    } else {
                        // Diffuse + reflected even when shadowed (sky is still visible)
                        let (diff_t, refl_t) = drad(
                            0.0, 0.0, solar_alt, solar_az,
                            slope_rad, aspect_rad,
                            params.linke, params.albedo, 1.0, g_norm_extra,
                        );
                        diff_t + refl_t
                    };

                    glob_acc += beam_contrib * step_h;

                    // Insol time: increment by step if beam reaches the surface
                    if !shadowed && s0 > 0.0 {
                        insol_acc += step_h;
                    }
                }

                time_angle += ha_step;
            }

            (i, glob_acc as f32, insol_acc as f32)
        })
        .collect();

    for (i, grad, insol) in results {
        glob_flat[i] = grad;
        insol_flat[i] = insol;
    }

    // Mark nodata pixels as NaN in the output
    for i in 0..n {
        if !valid[i] {
            glob_flat[i] = f32::NAN;
            insol_flat[i] = f32::NAN;
        }
    }

    let mut glob_grid = Grid::new(rows, cols, f32::NAN);
    glob_grid.data = glob_flat;

    let mut insol_grid = Grid::new(rows, cols, f32::NAN);
    insol_grid.data = insol_flat;

    DayResult {
        day: params.day,
        glob_rad: glob_grid,
        insol_time: insol_grid,
    }
}
