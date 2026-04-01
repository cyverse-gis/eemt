/-
  Sunrise/Sunset Verification
  ============================
  Verifies the sunrise/sunset computation from spherical geometry.

  Source: rsun/rsun-core/src/solar.rs `sunrise_sunset()`
  Docs: docs/algorithms/solar-radiation.md
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Inverse
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Solar

open Real EEMTVerify.Constants

/-! ## Hour Angle Conversion

From rsun-core/src/solar.rs:
```rust
pub fn hour_to_time_angle(hour: f64) -> f64 {
    (hour - 12.0) * HOURANGLE  // HOURANGLE = π/12
}
```
-/

/-- Convert decimal hour to time angle [radians].
    ω = (hour - 12) × π/12
    At solar noon (hour=12): ω = 0
    Morning (hour<12): ω < 0
    Afternoon (hour>12): ω > 0 -/
noncomputable def hourToTimeAngle (hour : ℝ) : ℝ :=
  (hour - 12) * (Real.pi / 12)

/-- Time angle is zero at solar noon. -/
theorem hourToTimeAngle_noon : hourToTimeAngle 12 = 0 := by
  unfold hourToTimeAngle; ring

/-- Time angle is negative in the morning. -/
theorem hourToTimeAngle_morning (h : ℝ) (hlt : h < 12) :
    hourToTimeAngle h < 0 := by
  unfold hourToTimeAngle
  apply mul_neg_of_neg_of_pos
  · linarith
  · positivity

/-- Time angle is positive in the afternoon. -/
theorem hourToTimeAngle_afternoon (h : ℝ) (hgt : h > 12) :
    hourToTimeAngle h > 0 := by
  unfold hourToTimeAngle
  apply mul_pos
  · linarith
  · positivity

/-! ## Sunrise/Sunset Model

The sunrise hour angle ω₀ satisfies:
  cos(ω₀) = -tan(φ) × tan(δ)

Then:
  sunrise = 12 - ω₀ × (180/π) / 15
  sunset  = 12 + ω₀ × (180/π) / 15

From rsun-core/src/solar.rs `sunrise_sunset()`:
```rust
let pom = -lum_c33 / lum_c31;  // = -tan(lat)*tan(decl) when cos(lat)*cos(decl) ≠ 0
if pom.abs() <= 1.0 {
    let pom_deg = pom.acos().to_degrees();
    let sunrise = (90.0 - pom_deg) / 15.0 + 6.0;
    let sunset = (pom_deg - 90.0) / 15.0 + 18.0;
    (sunrise, sunset)
}
```
-/

/-- The sunrise hour angle argument: -tan(φ) × tan(δ).
    When |arg| ≤ 1, sun rises and sets normally.
    When arg < -1: polar day (sun never sets).
    When arg > 1: polar night (sun never rises). -/
noncomputable def sunriseArg (lat : ℝ) (decl : ℝ) : ℝ :=
  -(Real.tan lat * Real.tan decl)

/-- Sunrise time in decimal hours (normal case: |arg| ≤ 1).
    sunrise = (90 - arccos(arg)°) / 15 + 6 -/
noncomputable def sunriseHour (lat : ℝ) (decl : ℝ) : ℝ :=
  let arg := sunriseArg lat decl
  let pomDeg := Real.arccos arg * (180 / Real.pi)
  (90 - pomDeg) / 15 + 6

/-- Sunset time in decimal hours (normal case).
    sunset = (arccos(arg)° - 90) / 15 + 18 -/
noncomputable def sunsetHour (lat : ℝ) (decl : ℝ) : ℝ :=
  let arg := sunriseArg lat decl
  let pomDeg := Real.arccos arg * (180 / Real.pi)
  (pomDeg - 90) / 15 + 18

/-- Day length in hours. -/
noncomputable def dayLength (lat : ℝ) (decl : ℝ) : ℝ :=
  sunsetHour lat decl - sunriseHour lat decl

/-! ## Key Properties -/

/-- **Sunrise + Sunset = 24**: The day is symmetric around solar noon.
    This follows algebraically from the definitions. -/
theorem sunrise_sunset_sum (lat : ℝ) (decl : ℝ) :
    sunriseHour lat decl + sunsetHour lat decl = 24 := by
  unfold sunriseHour sunsetHour sunriseArg
  ring

/-- Day length equals sunset minus sunrise. -/
theorem dayLength_eq (lat : ℝ) (decl : ℝ) :
    dayLength lat decl = sunsetHour lat decl - sunriseHour lat decl := by
  unfold dayLength; rfl

/-- Day length is non-negative (when the formulas apply).
    dayLength = 2 × arccos(arg)° / 15 = 2 × ω₀ / 15
    Since arccos returns values in [0, π], dayLength ∈ [0, 24]. -/
theorem dayLength_nonneg (lat : ℝ) (decl : ℝ) :
    dayLength lat decl ≥ 0 := by
  -- dayLength = sunset - sunrise, and sunrise + sunset = 24
  -- sunset = 18 + (arccos(arg)° - 90)/15 ≥ 18 - 90/15 = 12
  -- sunrise = 6 + (90 - arccos(arg)°)/15 ≤ 6 + 90/15 = 12
  -- So dayLength = sunset - sunrise ≥ 0
  -- dayLength = sunset - sunrise
  -- = [(arccos(arg)° - 90)/15 + 18] - [(90 - arccos(arg)°)/15 + 6]
  -- = 2*arccos(arg)°/15 + 12 - 12 = 2*arccos(arg)*180/(π*15)
  -- arccos ≥ 0, so this is ≥ 0
  sorry -- Needs ring_nf then mul_nonneg chain after normalization

/-- Day length is at most 24 hours. -/
theorem dayLength_le_24 (lat : ℝ) (decl : ℝ) :
    dayLength lat decl ≤ 24 := by
  -- dayLength = 2*arccos(arg)*180/(π*15)
  -- arccos ≤ π, so dayLength ≤ 2*π*180/(π*15) = 2*180/15 = 24
  sorry -- Needs ring_nf then arccos_le_pi bound

/-- At equinox (declination = 0), day length is 12 hours everywhere. -/
theorem equinox_twelve_hours (lat : ℝ) :
    dayLength lat 0 = 12 := by
  unfold dayLength sunsetHour sunriseHour sunriseArg
  simp only [Real.tan_zero, mul_zero, neg_zero, Real.arccos_zero]
  have hpi : Real.pi ≠ 0 := Real.pi_ne_zero
  field_simp
  ring

/-! ## Polar Cases -/

/-- Polar day: when sunriseArg < -1, the sun never sets.
    The implementation returns (0.0, 24.0) → day length 24. -/
noncomputable def isPolarDay (lat : ℝ) (decl : ℝ) : Prop :=
  sunriseArg lat decl < -1

/-- Polar night: when sunriseArg > 1, the sun never rises.
    The implementation returns (12.0, 12.0) → day length 0. -/
noncomputable def isPolarNight (lat : ℝ) (decl : ℝ) : Prop :=
  sunriseArg lat decl > 1

/-! ## Structural Correspondence

The Lean definitions match:
- **Rust** (`rsun/rsun-core/src/solar.rs`): `sunrise_sunset(latitude, declination)`
  - Uses `lum_c31 = cos(lat)*cos(decl)`, `lum_c33 = sin(lat)*sin(decl)`
  - `pom = -lum_c33/lum_c31 = -tan(lat)*tan(decl)` (matches `sunriseArg`)
  - Handles degenerate cases: `|lum_c31| < 1e-4` (polar regions)

The algebraic equivalence:
  `(90 - arccos(pom)°) / 15 + 6`
  `= (90 - arccos(pom) × 180/π) / 15 + 6`
  `= 6 + 6 - arccos(pom) × 12/π`
  `= 12 - arccos(pom) / HOURANGLE`
  which is the standard sunrise formula.
-/

end EEMTVerify.Solar
