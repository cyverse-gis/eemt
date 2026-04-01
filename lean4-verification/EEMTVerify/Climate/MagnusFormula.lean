/-
  Magnus Formula (Saturation Vapor Pressure) Verification
  =========================================================
  Verifies the Magnus-Tetens formula for saturation vapor pressure.

  Source: eemt/eemt/reemt.sh (r.mapcalc expressions)
  Docs: docs/algorithms/climate-integration.md lines 212-229, 310-334
-/

import Mathlib.Analysis.SpecialFunctions.ExpDeriv
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Climate

open Real EEMTVerify.Constants

/-! ## Magnus-Tetens Formula

The saturation vapor pressure over water:
  e_s(T) = 0.6108 × exp(17.27 × T / (T + 237.3))  [kPa]

This is the most widely used approximation in meteorology.
Valid for T ∈ [-40°C, 50°C] with <0.4% error.

From eemt/eemt/reemt.sh:
```bash
r.mapcalc "es_tmin_loc = if(tmin_loc > 0, 0.6108*exp((17.27*tmin_loc)/(tmin_loc+237.3)), 0)"
```
-/

/-- Magnus-Tetens saturation vapor pressure [kPa].
    e_s(T) = 0.6108 × exp(17.27 × T / (T + 237.3))

    Domain: T > -237.3°C (denominator must be positive).
    In practice, T ∈ [-60, 60]°C (DAYMET range). -/
noncomputable def magnus (T : ℝ) : ℝ :=
  magnusRef * Real.exp (magnusA * T / (T + magnusB))

/-- The Magnus exponent as a function of temperature. -/
noncomputable def magnusExponent (T : ℝ) : ℝ :=
  magnusA * T / (T + magnusB)

/-! ## Positivity -/

/-- **Magnus formula is strictly positive** for all T in its domain.
    This follows because exp(x) > 0 and 0.6108 > 0. -/
theorem magnus_pos (T : ℝ) : magnus T > 0 := by
  unfold magnus magnusRef
  apply mul_pos (by norm_num : (0.6108 : ℝ) > 0)
  exact Real.exp_pos _

/-- Magnus formula is non-negative (weaker version for convenience). -/
theorem magnus_nonneg (T : ℝ) : magnus T ≥ 0 := le_of_lt (magnus_pos T)

/-! ## Value at Key Temperatures -/

/-- At T = 0°C, the exponent is 0, so e_s = 0.6108 kPa. -/
theorem magnus_at_zero : magnus 0 = magnusRef := by
  unfold magnus magnusA magnusB
  simp [mul_zero, zero_div, Real.exp_zero, mul_one]

/-- The exponent is zero at T = 0. -/
theorem magnusExponent_zero : magnusExponent 0 = 0 := by
  unfold magnusExponent magnusA magnusB
  simp

/-- The exponent is positive for positive temperatures. -/
theorem magnusExponent_pos_of_pos (T : ℝ) (hT : T > 0) :
    magnusExponent T > 0 := by
  unfold magnusExponent magnusA magnusB
  apply div_pos
  · nlinarith
  · linarith

/-- The exponent is negative for negative temperatures (above -237.3). -/
theorem magnusExponent_neg_of_neg (T : ℝ) (hT : T < 0) (hdom : T > -magnusB) :
    magnusExponent T < 0 := by
  unfold magnusExponent magnusA magnusB at *
  apply div_neg_of_neg_of_pos
  · nlinarith
  · linarith

/-! ## Monotonicity -/

/-- **Magnus formula is strictly monotone increasing**.
    Warmer air holds more moisture — the fundamental physical constraint.

    Proof sketch: The exponent 17.27T/(T+237.3) has positive derivative
    17.27 × 237.3 / (T+237.3)² > 0, so exp of it is increasing,
    and multiplication by positive constant preserves monotonicity. -/
theorem magnus_strictMono_on (T₁ T₂ : ℝ)
    (h1 : T₁ > -magnusB) (h2 : T₂ > -magnusB) (hlt : T₁ < T₂) :
    magnus T₁ < magnus T₂ := by
  unfold magnus magnusRef
  apply mul_lt_mul_of_pos_left _ (by norm_num : (0.6108 : ℝ) > 0)
  apply Real.exp_lt_exp.mpr
  -- Need: magnusExponent T₁ < magnusExponent T₂
  unfold magnusA magnusB at *
  -- 17.27 * T₁ / (T₁ + 237.3) < 17.27 * T₂ / (T₂ + 237.3)
  rw [div_lt_div_iff (by linarith) (by linarith)]
  nlinarith

/-! ## Domain Properties -/

/-- Magnus denominator is positive in the DAYMET temperature range. -/
theorem magnus_denominator_pos (T : ℝ) (hT : T > -237.3) :
    T + magnusB > 0 := by
  unfold magnusB; linarith

/-- Magnus formula exceeds 0.6108 for positive temperatures. -/
theorem magnus_gt_ref_for_pos (T : ℝ) (hT : T > 0) :
    magnus T > magnusRef := by
  calc magnus T
      > magnus 0 := magnus_strictMono_on 0 T (by unfold magnusB; linarith)
                     (by unfold magnusB; linarith) hT
    _ = magnusRef := magnus_at_zero

/-! ## Relative Humidity

RH = (VP / e_s) × 100%

From docs/algorithms/climate-integration.md lines 310-334.
-/

/-- Relative humidity [%]. -/
noncomputable def relativeHumidity (vaporPressure : ℝ) (T : ℝ) : ℝ :=
  vaporPressure / magnus T * 100

/-- RH is bounded: 0 ≤ RH ≤ 100 when 0 ≤ VP ≤ e_s. -/
theorem rh_bounded (VP T : ℝ) (hVP_nn : VP ≥ 0) (hVP_le : VP ≤ magnus T) :
    0 ≤ relativeHumidity VP T ∧ relativeHumidity VP T ≤ 100 := by
  unfold relativeHumidity
  constructor
  · apply mul_nonneg
    · exact div_nonneg hVP_nn (magnus_nonneg T)
    · norm_num
  · have hm := magnus_pos T
    have hdiv : VP / magnus T ≤ 1 := div_le_one_of_le hVP_le (le_of_lt hm)
    linarith

/-! ## Structural Correspondence

The Lean `magnus` corresponds to multiple implementations:

**reemt.sh** (lines ~150-160):
```bash
r.mapcalc "es_tmin_loc = if(tmin_loc > 0, 0.6108*exp((17.27*tmin_loc)/(tmin_loc+237.3)), 0)"
r.mapcalc "es_tmax_loc = if(tmax_loc > 0, 0.6108*exp((17.27*tmax_loc)/(tmax_loc+237.3)), 0)"
```

Note: reemt.sh guards with `if(T > 0, ...)` which sets e_s = 0 for sub-zero
temperatures. This is a simplification — the true Magnus formula is valid
for negative temperatures. The guard should arguably be `if(T > -237.3, ...)`.

**docs/algorithms/climate-integration.md** uses the same coefficients:
  e_s = 0.6108 × exp(17.27T / (T+237.3))
-/

end EEMTVerify.Climate
