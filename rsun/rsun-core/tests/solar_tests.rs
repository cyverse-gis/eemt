use approx::assert_relative_eq;
use rsun_core::solar;

#[test]
fn test_declination_summer_solstice() {
    let decl = solar::declination(172);
    assert_relative_eq!(decl.to_degrees(), 23.44, epsilon = 0.5);
}

#[test]
fn test_declination_winter_solstice() {
    let decl = solar::declination(355);
    assert_relative_eq!(decl.to_degrees(), -23.44, epsilon = 0.5);
}

#[test]
fn test_declination_equinox() {
    let decl = solar::declination(80);
    assert!(decl.to_degrees().abs() < 2.0);
}

#[test]
fn test_solar_constant_correction() {
    let i0_jan = solar::corrected_solar_constant(3, 1367.0);
    assert!(i0_jan > 1367.0);
    assert!(i0_jan < 1420.0);
    let i0_jul = solar::corrected_solar_constant(185, 1367.0);
    assert!(i0_jul < 1367.0);
    assert!(i0_jul > 1320.0);
}

#[test]
fn test_sunrise_sunset_equinox_midlatitude() {
    let lat = 40.0_f64.to_radians();
    let decl = solar::declination(80);
    let (sunrise, sunset) = solar::sunrise_sunset(lat, decl);
    assert_relative_eq!(sunrise, 6.0, epsilon = 0.5);
    assert_relative_eq!(sunset, 18.0, epsilon = 0.5);
}

#[test]
fn test_solar_position_noon() {
    let lat = 40.0_f64.to_radians();
    let decl = solar::declination(172);
    let time_angle = 0.0;
    let (alt, _az) = solar::solar_position(lat, decl, time_angle);
    assert_relative_eq!(alt.to_degrees(), 73.4, epsilon = 1.0);
}
