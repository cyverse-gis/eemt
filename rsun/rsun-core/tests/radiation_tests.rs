use approx::assert_relative_eq;
use rsun_core::radiation;

#[test]
fn test_beam_radiation_direct_overhead() {
    // High solar altitude, no slope: should get significant beam radiation
    let solar_alt = 1.0; // ~57 degrees - high sun
    let elevation = 2500.0; // meters
    let linke = 3.0;
    let s0 = 1.0; // cos(incidence) = 1 for flat surface at solar noon
    let g_norm_extra = 1380.0; // corrected solar constant

    let (beam, beam_h) = radiation::brad(s0, solar_alt, elevation, linke, 1.0, g_norm_extra);
    assert!(beam > 0.0, "Beam radiation should be positive");
    assert!(beam < g_norm_extra, "Beam can't exceed solar constant");
    assert!(beam_h > 0.0, "Horizontal beam should be positive");
}

#[test]
fn test_beam_radiation_zero_when_shadowed() {
    // When s0 <= 0 (surface facing away from sun), beam should be 0
    let (beam, _) = radiation::brad(-0.1, 0.5, 2500.0, 3.0, 1.0, 1380.0);
    assert_relative_eq!(beam, 0.0);
}

#[test]
fn test_diffuse_radiation_positive() {
    // Diffuse radiation should always be positive when sun is up
    let solar_alt = 0.5; // ~29 degrees
    let slope = 0.3; // ~17 degrees
    let aspect = 3.14; // south-facing
    let solar_azimuth = 3.14;
    let linke = 3.0;
    let albedo = 0.2;
    let beam_h = 500.0;
    let g_norm_extra = 1380.0;

    let (diffuse, reflected) = radiation::drad(
        0.8, beam_h, solar_alt, solar_azimuth,
        slope, aspect, linke, albedo, 1.0, g_norm_extra,
    );
    assert!(diffuse > 0.0, "Diffuse should be positive");
    assert!(reflected >= 0.0, "Reflected should be non-negative");
}

#[test]
fn test_flat_surface_no_reflected() {
    // On a flat surface (slope=0), reflected radiation should be 0
    let (_, reflected) = radiation::drad(
        1.0, 500.0, 0.8, 3.14,
        0.0, 0.0, // flat surface
        3.0, 0.2, 1.0, 1380.0,
    );
    assert_relative_eq!(reflected, 0.0, epsilon = 1e-6);
}
