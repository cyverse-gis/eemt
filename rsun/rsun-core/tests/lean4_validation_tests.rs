//! Lean 4 Formal Verification Validation Tests
//!
//! Each test validates that the Rust implementation produces values consistent
//! with bounds formally proven in `lean4-verification/EEMTVerify/Solar/`.
//!
//! Test naming convention: `test_lean4_{lean_file}_{theorem_name}`
//!
//! These tests serve as the bridge between the Lean 4 mathematical proofs
//! (which operate on exact reals) and the Rust implementation (which uses
//! IEEE 754 f64). The proven bounds have sufficient margin that f64 arithmetic
//! stays comfortably within them.

use approx::assert_relative_eq;
use rsun_core::radiation;
use rsun_core::solar;
use rsun_core::types::{Grid, SolarParams};
use std::f64::consts::PI;

// === Constants matching lean4-verification/EEMTVerify/Foundation/Constants.lean ===

const SOLAR_CONSTANT: f64 = 1367.0;
const ECCENTRICITY_COEFF: f64 = 0.03344;
const SCALE_HEIGHT: f64 = 8434.5;
/// arcsin(0.3978) — the maximum absolute value of solar declination (~23.44°)
const ARCSIN_AMPLITUDE: f64 = 0.40912;

// ============================================================================
// Group 1: Declination (Declination.lean)
// ============================================================================

/// Validates `declination_bounded`: δ ∈ [-arcsin(0.3978), arcsin(0.3978)]
/// for every day of the year.
#[test]
fn test_lean4_declination_bounded_all_days() {
    for day in 1..=365u16 {
        let decl = solar::declination(day);
        assert!(
            decl >= -ARCSIN_AMPLITUDE && decl <= ARCSIN_AMPLITUDE,
            "Day {day}: declination {decl} rad ({} deg) outside [-{ARCSIN_AMPLITUDE}, {ARCSIN_AMPLITUDE}]",
            decl.to_degrees()
        );
    }
}

/// Validates structural correctness: spring equinox (day ~80) has declination near zero.
#[test]
fn test_lean4_declination_equinox_near_zero() {
    let decl = solar::declination(80);
    assert!(
        decl.abs() < 0.05, // ~2.9 degrees tolerance for approximate equinox day
        "Equinox declination should be near zero, got {} deg",
        decl.to_degrees()
    );
}

// ============================================================================
// Group 2: Solar Constant (SolarConstant.lean)
// ============================================================================

/// Validates `eccentricityFactor_lower` and `eccentricityFactor_upper`:
/// eccentricity factor ∈ [0.96656, 1.03344] for all days.
#[test]
fn test_lean4_eccentricity_factor_range_all_days() {
    let lower = 1.0 - ECCENTRICITY_COEFF;
    let upper = 1.0 + ECCENTRICITY_COEFF;
    for day in 1..=365u16 {
        let factor = solar::corrected_solar_constant(day, 1.0);
        assert!(
            factor >= lower && factor <= upper,
            "Day {day}: eccentricity factor {factor} outside [{lower}, {upper}]"
        );
    }
}

/// Validates `correctedSolarConstant_default_range`:
/// G ∈ [0.96656 * 1367, 1.03344 * 1367] for all days.
#[test]
fn test_lean4_corrected_solar_constant_default_range() {
    let lower = (1.0 - ECCENTRICITY_COEFF) * SOLAR_CONSTANT; // ~1321.3
    let upper = (1.0 + ECCENTRICITY_COEFF) * SOLAR_CONSTANT; // ~1412.7
    for day in 1..=365u16 {
        let g = solar::corrected_solar_constant(day, SOLAR_CONSTANT);
        assert!(
            g >= lower && g <= upper,
            "Day {day}: corrected solar constant {g} W/m² outside [{lower}, {upper}]"
        );
    }
}

// ============================================================================
// Group 3: Sunrise/Sunset (SunriseSunset.lean)
// ============================================================================

/// Validates `hourToTimeAngle_noon`: ω(12) = 0.
#[test]
fn test_lean4_hour_to_time_angle_noon() {
    let omega = solar::hour_to_time_angle(12.0);
    assert_relative_eq!(omega, 0.0, epsilon = 1e-15);
}

/// Validates `hourToTimeAngle_morning`: ω < 0 for h < 12.
#[test]
fn test_lean4_hour_to_time_angle_morning_negative() {
    for hour in [0.0, 3.0, 6.0, 9.0, 11.0] {
        let omega = solar::hour_to_time_angle(hour);
        assert!(
            omega < 0.0,
            "Hour {hour}: time angle {omega} should be negative (morning)"
        );
    }
}

/// Validates `hourToTimeAngle_afternoon`: ω > 0 for h > 12.
#[test]
fn test_lean4_hour_to_time_angle_afternoon_positive() {
    for hour in [13.0, 15.0, 18.0, 21.0, 24.0] {
        let omega = solar::hour_to_time_angle(hour);
        assert!(
            omega > 0.0,
            "Hour {hour}: time angle {omega} should be positive (afternoon)"
        );
    }
}

/// Validates `sunrise_sunset_sum`: sunrise + sunset = 24 for all cases.
/// The Rust implementation returns (0, 24) for polar day and (12, 12) for
/// polar night, both summing to 24.
#[test]
fn test_lean4_sunrise_sunset_sum_24() {
    let latitudes_deg: &[f64] = &[-66.0, -45.0, -23.44, 0.0, 23.44, 45.0, 66.0];
    let days: &[u16] = &[1, 80, 172, 266, 355];

    for &lat_deg in latitudes_deg {
        let lat = lat_deg.to_radians();
        for &day in days {
            let decl = solar::declination(day);
            let (sunrise, sunset) = solar::sunrise_sunset(lat, decl);
            assert_relative_eq!(
                sunrise + sunset,
                24.0,
                epsilon = 1e-10,
            );
        }
    }
}

/// Validates `dayLength_nonneg` and `dayLength_le_24`:
/// day length ∈ [0, 24] for all latitude/day combinations.
#[test]
fn test_lean4_day_length_bounded() {
    let latitudes_deg: &[f64] = &[-80.0, -66.0, -45.0, 0.0, 45.0, 66.0, 80.0];
    let days: &[u16] = &[1, 80, 172, 266, 355];

    for &lat_deg in latitudes_deg {
        let lat = lat_deg.to_radians();
        for &day in days {
            let decl = solar::declination(day);
            let (sunrise, sunset) = solar::sunrise_sunset(lat, decl);
            let day_length = sunset - sunrise;
            assert!(
                day_length >= 0.0 && day_length <= 24.0,
                "Lat {lat_deg}° Day {day}: day length {day_length}h outside [0, 24]"
            );
        }
    }
}

/// Validates `equinox_twelve_hours`: at declination ≈ 0 (equinox),
/// day length ≈ 12h for non-polar latitudes.
#[test]
fn test_lean4_equinox_twelve_hours() {
    let decl = solar::declination(80); // near spring equinox
    let latitudes_deg: &[f64] = &[-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0];

    for &lat_deg in latitudes_deg {
        let lat = lat_deg.to_radians();
        let (sunrise, sunset) = solar::sunrise_sunset(lat, decl);
        let day_length = sunset - sunrise;
        assert_relative_eq!(
            day_length,
            12.0,
            epsilon = 0.5, // tolerance for day ~80 not being exact equinox
        );
    }
}

// ============================================================================
// Group 4: Solar Position (SolarPosition.lean)
// ============================================================================

/// Validates `solarAltitude_bounded`: altitude ∈ [-π/2, π/2].
#[test]
fn test_lean4_solar_altitude_bounded() {
    let test_cases = [
        (0.0_f64, 0.0_f64, 0.0_f64),       // equator, equinox, noon
        (45.0, 23.44, 0.0),                  // mid-lat, summer, noon
        (-45.0, -23.44, 0.0),                // southern mid-lat, winter, noon
        (66.0, 23.44, -PI / 4.0),            // high lat, summer, morning
        (0.0, 0.0, PI / 3.0),               // equator, equinox, afternoon
    ];

    for &(lat_deg, decl_deg, time_angle) in &test_cases {
        let lat = lat_deg.to_radians();
        let decl = decl_deg.to_radians();
        let (alt, _az) = solar::solar_position(lat, decl, time_angle);
        assert!(
            alt >= -PI / 2.0 - 1e-10 && alt <= PI / 2.0 + 1e-10,
            "Lat {lat_deg}° Decl {decl_deg}° TA {time_angle}: altitude {alt} rad outside [-π/2, π/2]"
        );
    }
}

/// Validates `noon_altitude_max`: solar altitude at noon (ω=0) is the
/// daily maximum for non-polar conditions.
#[test]
fn test_lean4_noon_altitude_maximum() {
    let latitudes_deg: &[f64] = &[0.0, 20.0, 40.0, 60.0];
    let days: &[u16] = &[80, 172, 266];

    for &lat_deg in latitudes_deg {
        let lat = lat_deg.to_radians();
        for &day in days {
            let decl = solar::declination(day);
            let (noon_alt, _) = solar::solar_position(lat, decl, 0.0);

            // Check several time angles away from noon
            for &ta in &[-PI / 4.0, -PI / 6.0, PI / 6.0, PI / 4.0] {
                let (alt, _) = solar::solar_position(lat, decl, ta);
                assert!(
                    noon_alt >= alt - 1e-10,
                    "Lat {lat_deg}° Day {day}: noon alt {:.4} < alt {:.4} at TA {ta}",
                    noon_alt, alt
                );
            }
        }
    }
}

// ============================================================================
// Group 5: Air Mass & Transmittance (AirMass.lean)
// ============================================================================

/// Validates `elevationCorrection_pos`, `_le_one`, and `_antitone`:
/// exp(-z/8434.5) is positive, ≤ 1, and decreasing with elevation.
#[test]
fn test_lean4_elevation_correction_properties() {
    let elevations = [0.0, 500.0, 1000.0, 2000.0, 3000.0, 5000.0, 8848.0];
    let mut prev_corr = f64::MAX;

    for &z in &elevations {
        let corr = (-z / SCALE_HEIGHT).exp();
        assert!(corr > 0.0, "Elevation {z}m: correction {corr} should be > 0");
        assert!(
            corr <= 1.0 + 1e-15,
            "Elevation {z}m: correction {corr} should be ≤ 1"
        );
        assert!(
            corr <= prev_corr,
            "Elevation {z}m: correction {corr} should be ≤ previous {prev_corr} (antitone)"
        );
        prev_corr = corr;
    }
}

/// Validates `beamTransmittance_pos` and `_le_one`:
/// beam transmittance ∈ (0, 1] for valid atmospheric conditions.
/// We extract transmittance as beam_h / (g_norm_extra * sin(solar_alt)).
#[test]
fn test_lean4_beam_transmittance_bounded() {
    let test_cases = [
        // (s0, solar_alt, elevation, linke)
        (0.8, 0.5, 0.0, 3.0),       // sea level, moderate altitude
        (0.9, 1.0, 0.0, 3.0),       // sea level, high sun
        (0.7, 0.3, 2500.0, 3.0),    // mountain
        (0.6, 0.8, 0.0, 1.0),       // very clear atmosphere
        (0.5, 0.4, 0.0, 6.0),       // turbid atmosphere
    ];

    let g_ext = 1367.0;

    for &(s0, alt, elev, linke) in &test_cases {
        let (_, beam_h) = radiation::brad(s0, alt, elev, linke, 1.0, g_ext);
        let sin_alt = alt.sin();
        if sin_alt > 0.0 && beam_h > 0.0 {
            let transmittance = beam_h / (g_ext * sin_alt);
            assert!(
                transmittance > 0.0,
                "Transmittance {transmittance} should be > 0 (alt={alt}, elev={elev}, TL={linke})"
            );
            assert!(
                transmittance <= 1.0 + 1e-10,
                "Transmittance {transmittance} should be ≤ 1 (alt={alt}, elev={elev}, TL={linke})"
            );
        }
    }
}

// ============================================================================
// Group 6: Beam Radiation (BeamRadiation.lean)
// ============================================================================

/// Validates `beamTilted_zero_facing_away`: beam = 0 when s0 ≤ 0.
#[test]
fn test_lean4_beam_zero_when_s0_negative() {
    let (beam, beam_h) = radiation::brad(-0.5, 0.8, 2500.0, 3.0, 1.0, 1380.0);
    assert_eq!(beam, 0.0, "Beam tilted should be 0 when s0 < 0");
    assert_eq!(beam_h, 0.0, "Beam horizontal should be 0 when s0 < 0");
}

/// Validates `beamTilted_zero_night`: beam = 0 when solar altitude ≤ 0.
#[test]
fn test_lean4_beam_zero_when_solar_alt_negative() {
    let (beam, beam_h) = radiation::brad(0.8, -0.1, 2500.0, 3.0, 1.0, 1380.0);
    assert_eq!(beam, 0.0, "Beam tilted should be 0 at night");
    assert_eq!(beam_h, 0.0, "Beam horizontal should be 0 at night");
}

/// Validates `beamTiltedSimplified_le_gExt`: beam ≤ g_norm_extra.
#[test]
fn test_lean4_beam_le_solar_constant() {
    let g_ext = 1380.0;
    let test_cases = [
        (0.99, 1.2, 0.0, 1.0),    // best case: high sun, clear, sea level
        (0.8, 0.8, 2500.0, 3.0),  // typical mountain
        (0.5, 0.3, 0.0, 5.0),     // low sun, turbid
    ];

    for &(s0, alt, elev, linke) in &test_cases {
        let (beam, _) = radiation::brad(s0, alt, elev, linke, 1.0, g_ext);
        assert!(
            beam <= g_ext + 1e-6,
            "Beam {beam} should be ≤ g_ext {g_ext} (s0={s0}, alt={alt})"
        );
    }
}

/// Validates `beamTilted_nonneg`: beam ≥ 0 for valid inputs.
#[test]
fn test_lean4_beam_nonneg() {
    let test_cases = [
        (0.8, 0.5, 0.0, 3.0, 1380.0),
        (0.3, 0.2, 5000.0, 6.0, 1350.0),
        (0.99, 1.4, 100.0, 1.5, 1400.0),
    ];

    for &(s0, alt, elev, linke, g_ext) in &test_cases {
        let (beam, beam_h) = radiation::brad(s0, alt, elev, linke, 1.0, g_ext);
        assert!(beam >= 0.0, "Beam tilted should be ≥ 0, got {beam}");
        assert!(beam_h >= 0.0, "Beam horizontal should be ≥ 0, got {beam_h}");
    }
}

// ============================================================================
// Group 7: Diffuse & Reflected Radiation (DiffuseRadiation.lean)
// ============================================================================

/// Validates `view_factors_sum_one`: F_sky + F_terrain = 1 for all slopes.
/// View factors are computed as (1 + cos(β))/2 and (1 - cos(β))/2.
#[test]
fn test_lean4_view_factors_sum_one() {
    let slopes = [0.0, 0.1, 0.3, 0.5, 1.0, PI / 4.0, PI / 3.0, PI / 2.0];
    for &slope in &slopes {
        let cos_s = slope.cos();
        let sky_vf = (1.0 + cos_s) / 2.0;
        let terrain_vf = (1.0 - cos_s) / 2.0;
        assert_relative_eq!(
            sky_vf + terrain_vf,
            1.0,
            epsilon = 1e-15,
        );
        assert!(sky_vf >= 0.0 && sky_vf <= 1.0, "Sky VF {sky_vf} out of [0,1]");
        assert!(
            terrain_vf >= 0.0 && terrain_vf <= 1.0,
            "Terrain VF {terrain_vf} out of [0,1]"
        );
    }
}

/// Validates `reflectedRadiation_flat`: reflected = 0 when slope = 0.
#[test]
fn test_lean4_reflected_radiation_flat_is_zero() {
    // Call drad with slope = 0 — reflected component should be 0
    let (_, reflected) = radiation::drad(
        0.8,  // s0
        500.0, // beam_h
        0.8,  // solar_alt
        PI,   // solar_azimuth
        0.0,  // slope = 0 (flat)
        0.0,  // aspect
        3.0,  // linke
        0.2,  // albedo
        1.0,  // cdh
        1380.0, // g_norm_extra
    );
    assert_eq!(
        reflected, 0.0,
        "Reflected radiation should be exactly 0 on a flat surface"
    );
}

/// Validates `reflectedRadiation_nonneg`: reflected ≥ 0 for various conditions.
#[test]
fn test_lean4_reflected_radiation_nonneg() {
    let test_cases = [
        // (s0, beam_h, solar_alt, slope, albedo)
        (0.8, 500.0, 0.8, 0.3, 0.2),
        (0.5, 300.0, 0.5, 0.5, 0.3),
        (0.3, 100.0, 0.3, 1.0, 0.8),
        (0.0, 0.0, 0.5, 0.5, 0.2), // shadowed
    ];

    for &(s0, beam_h, alt, slope, albedo) in &test_cases {
        let (_, reflected) = radiation::drad(
            s0, beam_h, alt, PI, slope, 0.0, 3.0, albedo, 1.0, 1380.0,
        );
        assert!(
            reflected >= -1e-10,
            "Reflected {reflected} should be ≥ 0 (slope={slope}, albedo={albedo})"
        );
    }
}

// ============================================================================
// Group 8: Cos Incidence (CosIncidence.lean)
// ============================================================================

/// Validates `cosIncidence_bounded`: |cos_incidence| ≤ 1.
#[test]
fn test_lean4_cos_incidence_bounded() {
    let test_cases = [
        // (slope, aspect, lat, decl, time_angle) — all in radians
        (0.0, 0.0, 0.7, 0.3, 0.0),
        (0.5, 1.0, 0.7, 0.3, -PI / 4.0),
        (1.0, PI, -0.5, -0.2, PI / 6.0),
        (0.3, PI / 2.0, 1.0, 0.4, -PI / 3.0),
        (PI / 4.0, 3.0, 0.0, 0.0, 0.0),
    ];

    for &(slope, aspect, lat, decl, ta) in &test_cases {
        let s0 = radiation::cos_incidence(slope, aspect, lat, decl, ta);
        assert!(
            s0 >= -1.0 - 1e-10 && s0 <= 1.0 + 1e-10,
            "cos_incidence = {s0} outside [-1, 1] (slope={slope}, aspect={aspect}, lat={lat})"
        );
    }
}

/// Validates `flat_surface_eq_altitude`: on a flat surface (slope=0),
/// cos_incidence ≈ sin(solar_altitude).
#[test]
fn test_lean4_flat_surface_equals_sin_altitude() {
    let test_cases = [
        (40.0_f64.to_radians(), 172u16, 0.0),      // mid-lat, summer, noon
        (40.0_f64.to_radians(), 172, -PI / 4.0),    // morning
        (0.0_f64.to_radians(), 80, PI / 6.0),       // equator, equinox
        (60.0_f64.to_radians(), 355, 0.0),           // high lat, winter, noon
    ];

    for &(lat, day, ta) in &test_cases {
        let decl = solar::declination(day);
        let (alt, _) = solar::solar_position(lat, decl, ta);
        let sin_alt = alt.sin();

        // Flat surface: slope=0, aspect=0
        let s0 = radiation::cos_incidence(0.0, 0.0, lat, decl, ta);

        assert_relative_eq!(
            s0,
            sin_alt,
            epsilon = 1e-6,
        );
    }
}

// ============================================================================
// Group 9: Total Radiation Integration (TotalRadiation.lean)
// ============================================================================

/// Helper: create a small synthetic flat DEM for integration tests.
fn make_synthetic_dem(elevation: f32, lat_deg: f32) -> (Grid, Grid, Grid, Grid, Grid) {
    let rows = 3;
    let cols = 3;
    let mut dem = Grid::new(rows, cols, f32::NAN);
    let mut slope = Grid::new(rows, cols, f32::NAN);
    let mut aspect = Grid::new(rows, cols, f32::NAN);
    let mut lat_grid = Grid::new(rows, cols, f32::NAN);
    let mut lon_grid = Grid::new(rows, cols, f32::NAN);

    for r in 0..rows {
        for c in 0..cols {
            dem.set(r, c, elevation);
            slope.set(r, c, 0.0);  // flat
            aspect.set(r, c, 0.0);
            lat_grid.set(r, c, lat_deg.to_radians());
            lon_grid.set(r, c, (-105.0_f32).to_radians());
        }
    }
    (dem, slope, aspect, lat_grid, lon_grid)
}

/// Validates `dailyRadiation_nonneg`: all glob_rad values ≥ 0 for valid pixels.
#[test]
fn test_lean4_daily_radiation_nonneg() {
    let (dem, slope, aspect, lat_grid, lon_grid) = make_synthetic_dem(2500.0, 40.0);

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    for r in 0..result.glob_rad.rows {
        for c in 0..result.glob_rad.cols {
            let val = result.glob_rad.get(r, c);
            if !val.is_nan() {
                assert!(
                    val >= 0.0,
                    "Pixel ({r},{c}): glob_rad {val} should be ≥ 0"
                );
            }
        }
    }
}

/// Validates `insolation_le_dayLength`: insolation time ≤ day length.
#[test]
fn test_lean4_insolation_bounded_by_day_length() {
    let lat_deg = 40.0_f32;
    let (dem, slope, aspect, lat_grid, lon_grid) = make_synthetic_dem(2500.0, lat_deg);

    let params = SolarParams {
        day: 172,
        step: 0.5,
        linke: 3.0,
        albedo: 0.2,
        solar_constant: 1367.0,
    };

    let decl = solar::declination(params.day);
    let (sunrise, sunset) = solar::sunrise_sunset((lat_deg as f64).to_radians(), decl);
    let day_length = sunset - sunrise;

    let result = rsun_core::compute_day(&dem, &slope, &aspect, &lat_grid, &lon_grid, None, &params);

    for r in 0..result.insol_time.rows {
        for c in 0..result.insol_time.cols {
            let val = result.insol_time.get(r, c) as f64;
            if !val.is_nan() {
                assert!(
                    val <= day_length + 0.5, // tolerance for step discretization
                    "Pixel ({r},{c}): insol_time {val}h > day_length {day_length}h"
                );
            }
        }
    }
}
