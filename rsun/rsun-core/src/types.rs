/// Parameters that are constant for a given day
#[derive(Debug, Clone, Copy)]
pub struct SolarParams {
    pub day: u16,
    pub step: f64,
    pub linke: f64,
    pub albedo: f64,
    pub solar_constant: f64,
}

impl Default for SolarParams {
    fn default() -> Self {
        Self {
            day: 1,
            step: 0.5,
            linke: 3.0,
            albedo: 0.2,
            solar_constant: 1367.0,
        }
    }
}

/// A 2D grid of f32 values with geographic metadata
#[derive(Debug, Clone)]
pub struct Grid {
    pub data: Vec<f32>,
    pub rows: usize,
    pub cols: usize,
    pub nodata: f32,
}

impl Grid {
    pub fn new(rows: usize, cols: usize, nodata: f32) -> Self {
        Self {
            data: vec![nodata; rows * cols],
            rows,
            cols,
            nodata,
        }
    }

    pub fn get(&self, row: usize, col: usize) -> f32 {
        self.data[row * self.cols + col]
    }

    pub fn set(&mut self, row: usize, col: usize, value: f32) {
        self.data[row * self.cols + col] = value;
    }

    pub fn is_nodata(&self, row: usize, col: usize) -> bool {
        let v = self.get(row, col);
        v.is_nan() || v == self.nodata
    }
}

/// Geographic metadata for a grid (from GeoTIFF)
#[derive(Debug, Clone)]
pub struct GeoTransform {
    pub x_origin: f64,
    pub y_origin: f64,
    pub x_res: f64,
    pub y_res: f64,
    pub crs_wkt: String,
}

/// Result of a single-day radiation computation
#[derive(Debug, Clone)]
pub struct DayResult {
    pub day: u16,
    pub glob_rad: Grid,
    pub insol_time: Grid,
}

/// Months and their day ranges (1-indexed, non-leap year)
pub const MONTHS: [&str; 12] = [
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
];

/// Day ranges for each month (1-indexed, inclusive, non-leap year)
pub const MONTH_DAYS: [(u16, u16); 12] = [
    (1, 31), (32, 59), (60, 90), (91, 120), (121, 151), (152, 181),
    (182, 212), (213, 243), (244, 273), (274, 304), (305, 334), (335, 365),
];

/// Day ranges for leap year
pub const MONTH_DAYS_LEAP: [(u16, u16); 12] = [
    (1, 31), (32, 60), (61, 91), (92, 121), (122, 152), (153, 182),
    (183, 213), (214, 244), (245, 274), (275, 305), (306, 335), (336, 366),
];
