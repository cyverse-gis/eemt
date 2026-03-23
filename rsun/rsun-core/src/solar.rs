//! Solar position calculations.
//! Ported from GRASS GIS r.sun rsunlib.c (Hofierka & Suri 2002).
//! All angles in radians unless noted otherwise.

use std::f64::consts::PI;

const PI2: f64 = 2.0 * PI;
const HOURANGLE: f64 = PI / 12.0;

/// Solar declination for a given day of year.
/// From GRASS com_declin(). Returns radians.
pub fn declination(day: u16) -> f64 {
    let d1 = PI2 * (day as f64) / 365.25;
    asin_safe(0.3978 * (d1 - 1.4 + 0.0355 * (d1 - 0.0489).sin()).sin())
}

/// Solar constant corrected for Earth-Sun distance.
/// From GRASS com_sol_const().
pub fn corrected_solar_constant(day: u16, solar_constant: f64) -> f64 {
    let d1 = PI2 * (day as f64) / 365.25;
    solar_constant * (1.0 + 0.03344 * (d1 - 0.048869).cos())
}

/// Compute sunrise and sunset times in decimal hours (solar time).
/// From GRASS com_par_const().
pub fn sunrise_sunset(latitude: f64, declination: f64) -> (f64, f64) {
    let sin_lat = latitude.sin();
    let cos_lat = latitude.cos();
    let cos_decl = declination.cos();
    let sin_decl = declination.sin();
    let lum_c31 = cos_lat * cos_decl;
    let lum_c33 = sin_lat * sin_decl;

    if lum_c31.abs() < 1e-4 {
        if lum_c33 > 0.0 {
            return (0.0, 24.0);
        } else {
            return (12.0, 12.0);
        }
    }

    let pom = -lum_c33 / lum_c31;
    if pom.abs() <= 1.0 {
        let pom_deg = pom.acos().to_degrees();
        let sunrise = (90.0 - pom_deg) / 15.0 + 6.0;
        let sunset = (pom_deg - 90.0) / 15.0 + 18.0;
        (sunrise, sunset)
    } else if pom < 0.0 {
        (0.0, 24.0)
    } else {
        (12.0, 12.0)
    }
}

/// Compute solar altitude and azimuth for a given time angle.
/// From GRASS com_par(). time_angle: 0 = noon, negative = morning.
/// Returns (solar_altitude, solar_azimuth) in radians.
pub fn solar_position(latitude: f64, declination: f64, time_angle: f64) -> (f64, f64) {
    let sin_lat = latitude.sin();
    let cos_lat = latitude.cos();
    let cos_decl = declination.cos();
    let sin_decl = declination.sin();

    let lum_c11 = sin_lat * cos_decl;
    let lum_c13 = -cos_lat * sin_decl;
    let lum_c22 = cos_decl;
    let lum_c31 = cos_lat * cos_decl;
    let lum_c33 = sin_lat * sin_decl;

    let cos_time = time_angle.cos();
    let sin_time = time_angle.sin();

    let lum_lx = -lum_c22 * sin_time;
    let lum_ly = lum_c11 * cos_time + lum_c13;
    let sin_solar_alt = lum_c31 * cos_time + lum_c33;

    let solar_altitude = sin_solar_alt.asin();

    let pom = (lum_lx * lum_lx + lum_ly * lum_ly).sqrt();
    let solar_azimuth = if pom > 1e-4 {
        let mut az = (lum_ly / pom).acos();
        if lum_lx < 0.0 {
            az = PI2 - az;
        }
        az
    } else {
        0.0
    };

    (solar_altitude, solar_azimuth)
}

/// Time angle from decimal hour. Noon = 0.
pub fn hour_to_time_angle(hour: f64) -> f64 {
    (hour - 12.0) * HOURANGLE
}

/// HOURANGLE constant: pi/12 radians per hour.
pub fn hourangle() -> f64 {
    HOURANGLE
}

fn asin_safe(x: f64) -> f64 {
    x.clamp(-1.0, 1.0).asin()
}
