/-
  Earth-Sun Distance Correction Verification
  ============================================
  Verifies the corrected solar constant (extraterrestrial irradiance)
  accounting for Earth's elliptical orbit.

  Source: rsun/rsun-core/src/solar.rs `corrected_solar_constant()`
  Docs: docs/algorithms/solar-radiation.md lines 16-23
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Bounds
import EEMTVerify.Foundation.Constants
import EEMTVerify.Solar.Declination

namespace EEMTVerify.Solar

open Real EEMTVerify.Constants

/-! ## Corrected Solar Constant

From rsun-core/src/solar.rs:
```rust
pub fn corrected_solar_constant(day: u16, solar_constant: f64) -> f64 {
    let d1 = 2.0 * PI * day as f64 / 365.25;
    solar_constant * (1.0 + 0.03344 * (d1 - 0.048869).cos())
}
```

The factor `1 + 0.03344 * cos(d1 - 0.048869)` accounts for Earth's
elliptical orbit. The eccentricity coefficient 0.03344 and perihelion
offset 0.048869 rad (~2.8°, corresponding to ~Jan 3) are from Spencer (1971).
-/

/-- Eccentricity correction factor for Earth-Sun distance.
    Range: [1 - 0.03344, 1 + 0.03344] = [0.96656, 1.03344] -/
noncomputable def eccentricityFactor (day : ℕ) : ℝ :=
  1 + 0.03344 * Real.cos (dayAngle day - 0.048869)

/-- Corrected solar constant (extraterrestrial irradiance) [W/m²].
    G(day) = G₀ × eccentricityFactor(day) -/
noncomputable def correctedSolarConstant (day : ℕ) (sc : ℝ) : ℝ :=
  sc * eccentricityFactor day

/-! ## Eccentricity Factor Bounds -/

/-- The eccentricity coefficient 0.03344 is positive. -/
theorem eccentricity_coeff_pos : (0.03344 : ℝ) > 0 := by norm_num

/-- The eccentricity coefficient is less than 1. -/
theorem eccentricity_coeff_lt_one : (0.03344 : ℝ) < 1 := by norm_num

/-- Eccentricity factor lower bound: 1 - 0.03344 = 0.96656 -/
theorem eccentricityFactor_lower (day : ℕ) :
    0.96656 ≤ eccentricityFactor day := by
  unfold eccentricityFactor
  have h := Real.neg_one_le_cos (dayAngle day - 0.048869)
  linarith

/-- Eccentricity factor upper bound: 1 + 0.03344 = 1.03344 -/
theorem eccentricityFactor_upper (day : ℕ) :
    eccentricityFactor day ≤ 1.03344 := by
  unfold eccentricityFactor
  have h := Real.cos_le_one (dayAngle day - 0.048869)
  linarith

/-- Eccentricity factor is strictly positive. -/
theorem eccentricityFactor_pos (day : ℕ) : eccentricityFactor day > 0 := by
  linarith [eccentricityFactor_lower day]

/-! ## Corrected Solar Constant Properties -/

/-- Corrected solar constant is positive when input is positive. -/
theorem correctedSolarConstant_pos (day : ℕ) (sc : ℝ) (hsc : sc > 0) :
    correctedSolarConstant day sc > 0 := by
  unfold correctedSolarConstant
  exact mul_pos hsc (eccentricityFactor_pos day)

/-- Corrected solar constant range: [0.96656 × sc, 1.03344 × sc]. -/
theorem correctedSolarConstant_range (day : ℕ) (sc : ℝ) (hsc : sc > 0) :
    0.96656 * sc ≤ correctedSolarConstant day sc ∧
    correctedSolarConstant day sc ≤ 1.03344 * sc := by
  unfold correctedSolarConstant
  constructor
  · calc 0.96656 * sc
        = sc * 0.96656 := by ring
      _ ≤ sc * eccentricityFactor day := by
          apply mul_le_mul_of_nonneg_left (eccentricityFactor_lower day) (le_of_lt hsc)
  · calc sc * eccentricityFactor day
        ≤ sc * 1.03344 := by
          apply mul_le_mul_of_nonneg_left (eccentricityFactor_upper day) (le_of_lt hsc)
      _ = 1.03344 * sc := by ring

/-- At default solar constant 1367 W/m², the range is approximately [1321, 1413]. -/
theorem correctedSolarConstant_default_range (day : ℕ) :
    0.96656 * 1367 ≤ correctedSolarConstant day 1367 ∧
    correctedSolarConstant day 1367 ≤ 1.03344 * 1367 :=
  correctedSolarConstant_range day 1367 (by norm_num)

/-- The corrected constant never exceeds 1.03344 times the input
    (conservation: can't create energy). -/
theorem correctedSolarConstant_bounded_by_input (day : ℕ) (sc : ℝ) (hsc : sc > 0) :
    correctedSolarConstant day sc ≤ 1.03344 * sc :=
  (correctedSolarConstant_range day sc hsc).2

/-! ## Structural Correspondence

The Lean definition matches exactly:
- **Rust** (`rsun/rsun-core/src/solar.rs`): `corrected_solar_constant(day, solar_constant)`
- **WGSL** (`rsun/rsun-gpu/src/shaders/radiation.wgsl`): uses `params.g_norm_extra` (pre-computed)

Both use coefficients: 0.03344 (eccentricity), 0.048869 (perihelion offset), 365.25 (tropical year).
-/

end EEMTVerify.Solar
