/-
  Solar Declination Verification
  ==============================
  Verifies the Spencer (1971) solar declination formula used in:
  - Rust: rsun/rsun-core/src/solar.rs `declination()`
  - WGSL: rsun/rsun-gpu/src/shaders/radiation.wgsl
  - Docs: docs/algorithms/solar-radiation.md

  The declination angle δ determines the sun's position relative to
  Earth's equatorial plane, varying from -23.44° to +23.44° over the year.
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Bounds
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Inverse
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Solar

open Real EEMTVerify.Constants

/-! ## Declination Formula

The Spencer (1971) formula as implemented in rsun-core/src/solar.rs:

```rust
pub fn declination(day: u16) -> f64 {
    let d1 = 2.0 * PI * day as f64 / 365.25;
    (0.3978 * (d1 - 1.4 + 0.0355 * (d1 - 0.0489).sin()).sin()).asin()
}
```
-/

/-- Day angle: converts day of year to radians in the orbital cycle.
    d1 = 2π × day / 365.25 -/
noncomputable def dayAngle (day : ℕ) : ℝ :=
  2 * Real.pi * (day : ℝ) / 365.25

/-- Inner sine argument for the declination formula.
    arg = d1 - 1.4 + 0.0355 × sin(d1 - 0.0489) -/
noncomputable def declinationArg (day : ℕ) : ℝ :=
  let d1 := dayAngle day
  d1 - 1.4 + 0.0355 * Real.sin (d1 - 0.0489)

/-- Solar declination angle [radians] using Spencer (1971) formula.
    δ = arcsin(0.3978 × sin(declinationArg(day)))

    The coefficient 0.3978 ≈ sin(23.44°) encodes Earth's axial tilt. -/
noncomputable def declination (day : ℕ) : ℝ :=
  Real.arcsin (0.3978 * Real.sin (declinationArg day))

/-! ## Core Properties -/

/-- The amplitude coefficient 0.3978 is less than 1, ensuring the
    arcsin argument stays in [-1, 1]. -/
theorem amplitude_bound : (0.3978 : ℝ) < 1 := by norm_num

/-- The amplitude coefficient is positive. -/
theorem amplitude_pos : (0.3978 : ℝ) > 0 := by norm_num

/-- The arcsin argument is bounded: |0.3978 × sin(θ)| ≤ 0.3978 < 1.
    This ensures declination is always well-defined. -/
theorem arcsin_arg_bounded (day : ℕ) :
    |0.3978 * Real.sin (declinationArg day)| ≤ 1 := by
  calc |0.3978 * Real.sin (declinationArg day)|
      = 0.3978 * |Real.sin (declinationArg day)| := by
        rw [abs_mul, abs_of_pos amplitude_pos]
    _ ≤ 0.3978 * 1 := by
        apply mul_le_mul_of_nonneg_left (abs_sin_le_one _) (le_of_lt amplitude_pos)
    _ = 0.3978 := by ring
    _ ≤ 1 := by norm_num

/-- The arcsin argument is in [-1, 1]. -/
theorem arcsin_arg_mem_range (day : ℕ) :
    0.3978 * Real.sin (declinationArg day) ∈ Set.Icc (-1 : ℝ) 1 := by
  constructor
  · linarith [neg_abs_le (0.3978 * Real.sin (declinationArg day)),
              arcsin_arg_bounded day]
  · linarith [le_abs_self (0.3978 * Real.sin (declinationArg day)),
              arcsin_arg_bounded day]

/-- **Declination is bounded by ±arcsin(0.3978) ≈ ±23.44°**.
    This is the key range theorem: the declination angle never exceeds
    Earth's axial tilt.

    Formally: -arcsin(0.3978) ≤ δ(day) ≤ arcsin(0.3978) for all days. -/
theorem declination_bounded (day : ℕ) :
    declination day ∈ Set.Icc (-(Real.arcsin 0.3978)) (Real.arcsin 0.3978) := by
  unfold declination
  -- arcsin is monotone (Mathlib: monotone_arcsin), and
  -- -0.3978 ≤ 0.3978 * sin(θ) ≤ 0.3978 for all θ.
  -- Combined with arcsin(-x) = -arcsin(x), we get the result.
  constructor
  · -- Lower bound: -arcsin(0.3978) ≤ arcsin(0.3978 * sin(...))
    rw [← Real.arcsin_neg]
    apply Real.monotone_arcsin
    calc -(0.3978 : ℝ)
        = 0.3978 * (-1) := by ring
      _ ≤ 0.3978 * Real.sin (declinationArg day) := by
          apply mul_le_mul_of_nonneg_left (Real.neg_one_le_sin _) (le_of_lt amplitude_pos)
  · -- Upper bound: arcsin(0.3978 * sin(...)) ≤ arcsin(0.3978)
    apply Real.monotone_arcsin
    calc 0.3978 * Real.sin (declinationArg day)
        ≤ 0.3978 * 1 := by
          apply mul_le_mul_of_nonneg_left (Real.sin_le_one _) (le_of_lt amplitude_pos)
      _ = 0.3978 := by ring

/-- Declination at day 0 (approximately Jan 1): δ is negative (winter in NH). -/
theorem declination_january_negative : declination 0 < 0 := by
  sorry -- Requires numerical evaluation; will use native_decide or norm_num extensions

/-! ## Day Angle Properties -/

/-- Day angle is non-negative for valid days. -/
theorem dayAngle_nonneg (day : ℕ) : dayAngle day ≥ 0 := by
  unfold dayAngle
  apply mul_nonneg
  · apply mul_nonneg
    · linarith [Real.pi_pos]
    · exact Nat.cast_nonneg day
  · norm_num

/-- Day angle at day 0 is 0. -/
theorem dayAngle_zero : dayAngle 0 = 0 := by
  unfold dayAngle
  simp

/-- Day angle increases with day of year. -/
theorem dayAngle_monotone : Monotone (fun d : ℕ => dayAngle d) := by
  intro a b hab
  unfold dayAngle
  apply mul_le_mul_of_nonneg_right
  · apply mul_le_mul_of_nonneg_left
    · exact Nat.cast_le.mpr hab
    · linarith [Real.pi_pos]
  · norm_num

/-! ## Structural Correspondence

The Lean definition `declination` corresponds exactly to:

**Rust** (`rsun/rsun-core/src/solar.rs`):
```rust
pub fn declination(day: u16) -> f64 {
    let d1 = 2.0 * PI * day as f64 / 365.25;
    (0.3978 * (d1 - 1.4 + 0.0355 * (d1 - 0.0489).sin()).sin()).asin()
}
```

**WGSL** (`rsun/rsun-gpu/src/shaders/radiation.wgsl`):
```wgsl
let d1 = 2.0 * PI * f32(params.day) / 365.25;
let decl = asin(0.3978 * sin(d1 - 1.4 + 0.0355 * sin(d1 - 0.0489)));
```

Both implementations use identical coefficients (0.3978, 1.4, 0.0355, 0.0489, 365.25).
The Lean definition uses `ℝ` (exact reals); implementations use f64/f32 (IEEE 754).
-/

end EEMTVerify.Solar
