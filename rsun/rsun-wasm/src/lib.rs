//! WebAssembly bindings for rsun solar radiation.
//!
//! Provides CPU-only computation for browser demos with small DEMs (<1M pixels).
//! Uses rsun-core directly (no GPU — WebGPU compute would require async JS interop).
//!
//! Build: wasm-pack build --target web rsun-wasm

use rsun_core::types::{Grid, SolarParams};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

/// Result returned to JavaScript.
#[derive(Serialize, Deserialize)]
pub struct WasmDayResult {
    pub day: u16,
    pub rows: usize,
    pub cols: usize,
    /// Flattened glob_rad array [Wh/m²], row-major
    pub glob_rad: Vec<f32>,
    /// Flattened insol_time array [hours], row-major
    pub insol_time: Vec<f32>,
}

/// Compute solar radiation for a single day on a flat-grid DEM.
///
/// All arrays are flattened row-major f32.
/// Latitude/longitude in radians.
///
/// # Arguments (from JavaScript)
/// * `dem_data` - elevation values [meters], length = rows * cols
/// * `rows` - number of rows
/// * `cols` - number of columns
/// * `latitude` - latitude in radians (single value, applied to all pixels)
/// * `longitude` - longitude in radians (single value)
/// * `day` - day of year (1-366)
/// * `step` - time step in decimal hours (e.g., 0.5)
#[wasm_bindgen]
pub fn compute_day(
    dem_data: &[f32],
    rows: usize,
    cols: usize,
    latitude: f32,
    longitude: f32,
    day: u16,
    step: f64,
) -> JsValue {
    let n = rows * cols;
    if dem_data.len() != n {
        return serde_wasm_bindgen::to_value(&"DEM data length does not match rows*cols")
            .unwrap_or(JsValue::NULL);
    }

    // Limit to ~1M pixels for browser performance
    if n > 1_000_000 {
        return serde_wasm_bindgen::to_value(&"DEM too large for WASM (max 1M pixels)")
            .unwrap_or(JsValue::NULL);
    }

    let dem = Grid {
        data: dem_data.to_vec(),
        rows,
        cols,
        nodata: f32::NAN,
    };

    // Compute slope/aspect
    let (slope, aspect) = rsun_core::terrain::slope_aspect(&dem, 1.0, 1.0);

    // Create uniform lat/lon grids
    let mut lat_grid = Grid::new(rows, cols, f32::NAN);
    let mut lon_grid = Grid::new(rows, cols, f32::NAN);
    for r in 0..rows {
        for c in 0..cols {
            if !dem.is_nodata(r, c) {
                lat_grid.set(r, c, latitude);
                lon_grid.set(r, c, longitude);
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

    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    let wasm_result = WasmDayResult {
        day,
        rows,
        cols,
        glob_rad: result.glob_rad.data,
        insol_time: result.insol_time.data,
    };

    serde_wasm_bindgen::to_value(&wasm_result).unwrap_or(JsValue::NULL)
}

/// Get solar declination for a day of year (returns radians).
#[wasm_bindgen]
pub fn declination(day: u16) -> f64 {
    rsun_core::solar::declination(day)
}

/// Get sunrise and sunset times for a latitude and day.
/// Returns [sunrise_hour, sunset_hour].
#[wasm_bindgen]
pub fn sunrise_sunset(latitude_rad: f64, day: u16) -> Vec<f64> {
    let decl = rsun_core::solar::declination(day);
    let (rise, set) = rsun_core::solar::sunrise_sunset(latitude_rad, decl);
    vec![rise, set]
}
