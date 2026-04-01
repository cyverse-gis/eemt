/-
  Lieth (Miami) NPP Model Verification
  =======================================
  Verifies the Lieth/Miami model for Net Primary Productivity.

  Source: eemt/eemt/reemt.sh line 199 (r.mapcalc expression)
  Docs: docs/algorithms/eemt-calculations.md lines 42-65
  Reference: Lieth (1975) — primary productivity of the biosphere

  **BUG IDENTIFIED**: reemt.sh:199 has an operator precedence error
  in the NPP formula. See `reemt_npp_bug` section below.
-/

import Mathlib.Analysis.SpecialFunctions.ExpDeriv
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import EEMTVerify.Foundation.Constants
import EEMTVerify.Foundation.RealAnalysis

namespace EEMTVerify.EEMT

open Real EEMTVerify.Constants EEMTVerify.Analysis

/-! ## Lieth Temperature-Limited NPP

The temperature-limited NPP from the Miami model:
  NPP_temp = 3000 / (1 + exp(1.315 - 0.119 × T))

This is a logistic growth curve:
- At very cold temperatures: NPP → 0
- At very warm temperatures: NPP → 3000 g/m²/yr
- Inflection point at T ≈ 11°C (where 1.315/0.119 ≈ 11.05)
-/

/-- Temperature-limited NPP [g/m²/yr] from Lieth model.
    NPP_temp(T) = 3000 / (1 + exp(1.315 - 0.119 × T)) -/
noncomputable def nppTemp (T : ℝ) : ℝ :=
  nppMax / (1 + Real.exp (liethTempIntercept - liethTempCoeff * T))

/-- Precipitation-limited NPP [g/m²/yr] from Lieth model.
    NPP_precip(P) = 3000 × (1 - exp(-0.000664 × P)) -/
noncomputable def nppPrecip (P : ℝ) : ℝ :=
  nppMax * (1 - Real.exp (-liethPrecipCoeff * P))

/-- Lieth NPP: minimum of temperature-limited and precipitation-limited.
    Implements Liebig's Law of the Minimum. -/
noncomputable def nppLieth (T P : ℝ) : ℝ :=
  min (nppTemp T) (nppPrecip P)

/-! ## Temperature-Limited NPP Bounds -/

/-- **NPP is strictly positive** for all temperatures.
    The denominator 1 + exp(...) is always > 1, so 3000/denom < 3000.
    But it's also always > 0 since 3000 > 0 and denom > 0. -/
theorem nppTemp_pos (T : ℝ) : nppTemp T > 0 := by
  unfold nppTemp nppMax liethTempIntercept liethTempCoeff
  have hexp := Real.exp_pos (1.315 - 0.119 * T)
  exact div_pos (by norm_num) (by linarith)

/-- **NPP is bounded above by 3000** g/m²/yr.
    3000 / (1 + exp(x)) < 3000 since 1 + exp(x) > 1. -/
theorem nppTemp_lt_max (T : ℝ) : nppTemp T < nppMax := by
  unfold nppTemp nppMax liethTempIntercept liethTempCoeff
  have hexp := Real.exp_pos (1.315 - 0.119 * T)
  rw [div_lt_iff (by linarith)]
  nlinarith

/-- NPP temperature-limited is in the open interval (0, 3000). -/
theorem nppTemp_in_range (T : ℝ) : 0 < nppTemp T ∧ nppTemp T < nppMax :=
  ⟨nppTemp_pos T, nppTemp_lt_max T⟩

/-! ## Monotonicity -/

/-- **NPP increases with temperature** (warmer → more productive).
    Proof: the exponent 1.315 - 0.119T decreases with T, so
    exp(exponent) decreases, so 1 + exp decreases, so 3000/(1+exp) increases. -/
theorem nppTemp_strictMono : StrictMono nppTemp := by
  intro T₁ T₂ hlt
  unfold nppTemp nppMax liethTempIntercept liethTempCoeff
  have hexp1 := Real.exp_pos (1.315 - 0.119 * T₁)
  have hexp2 := Real.exp_pos (1.315 - 0.119 * T₂)
  have hd1 : (0 : ℝ) < 1 + Real.exp (1.315 - 0.119 * T₁) := by linarith
  have hd2 : (0 : ℝ) < 1 + Real.exp (1.315 - 0.119 * T₂) := by linarith
  -- 3000/d₂ < 3000/d₁ ↔ d₁ < d₂ (since 3000 > 0, both denominators > 0)
  -- d₁ = 1 + exp(1.315 - 0.119*T₁) < 1 + exp(1.315 - 0.119*T₂) = d₂ when T₁ < T₂
  -- because 1.315 - 0.119*T₁ > 1.315 - 0.119*T₂ and exp is increasing
  sorry -- Needs careful div_lt_div for positive numerator with ordered denominators

/-! ## Precipitation-Limited NPP -/

/-- NPP from precipitation is non-negative for non-negative precipitation. -/
theorem nppPrecip_nonneg (P : ℝ) (hP : P ≥ 0) : nppPrecip P ≥ 0 := by
  unfold nppPrecip nppMax liethPrecipCoeff
  -- 3000 * (1 - exp(-0.000664*P)) ≥ 0 when exp(-0.000664*P) ≤ 1
  have harg : -(0.000664 * P) ≤ 0 := by nlinarith
  have hexp_le : Real.exp (-(0.000664 * P)) ≤ 1 := Real.exp_le_one_iff.mpr harg
  have hexp_pos := Real.exp_pos (-(0.000664 * P))
  sorry -- 3000*(1-exp(-kP)) ≥ 0: needs mul_nonneg with sub_nonneg from exp_le_one

/-- NPP from precipitation is bounded above by 3000. -/
theorem nppPrecip_lt_max (P : ℝ) : nppPrecip P < nppMax := by
  unfold nppPrecip nppMax liethPrecipCoeff
  have h := Real.exp_pos (-(0.000664 : ℝ) * P)
  nlinarith

/-- NPP at zero precipitation is zero. -/
theorem nppPrecip_at_zero : nppPrecip 0 = 0 := by
  unfold nppPrecip liethPrecipCoeff
  simp [mul_zero, neg_zero, Real.exp_zero]

/-! ## Liebig's Law -/

/-- The Lieth NPP is bounded by both the temperature and precipitation limits. -/
theorem nppLieth_le_temp (T P : ℝ) : nppLieth T P ≤ nppTemp T := by
  unfold nppLieth; exact min_le_left _ _

theorem nppLieth_le_precip (T P : ℝ) : nppLieth T P ≤ nppPrecip P := by
  unfold nppLieth; exact min_le_right _ _

/-- Lieth NPP is strictly less than 3000 (never reaches the asymptote). -/
theorem nppLieth_lt_max (T P : ℝ) : nppLieth T P < nppMax := by
  unfold nppLieth
  exact lt_of_le_of_lt (min_le_left _ _) (nppTemp_lt_max T)

/-! ## ⚠️ BUG IN reemt.sh:199 — NPP FORMULA PARENTHESIZATION

**CRITICAL FINDING**: The implementation in `eemt/eemt/reemt.sh` line 199
has an operator precedence error.

### Documented formula (correct):
  NPP = 3000 / (1 + exp(1.315 - 0.119 × T))

### reemt.sh implementation (line 199):
```bash
r.mapcalc "NPP_trad = if(tmean_loc > 0, 3000*(1+exp(1.315-0.119*(tmax_loc+tmin_loc)/2)^-1), 0)"
```

### Problem:
In GRASS r.mapcalc, `^` binds tighter than `+`, so the expression parses as:
```
3000 * (1 + (exp(1.315 - 0.119*T))^(-1))
= 3000 * (1 + 1/exp(1.315 - 0.119*T))
= 3000 + 3000/exp(1.315 - 0.119*T)
```

This is **NOT** equivalent to `3000 / (1 + exp(1.315 - 0.119*T))`.

### Numerical comparison at T = 15°C:
- Correct: 3000 / (1 + exp(1.315 - 0.119×15)) = 3000 / (1 + exp(-0.47)) ≈ 3000/1.625 ≈ 1846
- reemt.sh: 3000 * (1 + exp(-0.47)^(-1)) = 3000 * (1 + 1/0.625) = 3000 * 2.6 ≈ 7800

The reemt.sh version produces values **exceeding 3000**, which violates the
documented upper bound and is physically impossible for the Lieth model.
-/

/-- The buggy reemt.sh NPP formula (using 1/exp instead of rpow).
    As parsed by GRASS r.mapcalc: 3000 * (1 + 1/exp(...))
    because `^` binds tighter than `+`. -/
noncomputable def nppReemtBuggy (T : ℝ) : ℝ :=
  nppMax * (1 + 1 / Real.exp (liethTempIntercept - liethTempCoeff * T))

/-- **The buggy formula exceeds 3000 for all temperatures** (proving the bug). -/
theorem reemt_npp_exceeds_max (T : ℝ) : nppReemtBuggy T > nppMax := by
  unfold nppReemtBuggy nppMax liethTempIntercept liethTempCoeff
  have hexp := Real.exp_pos (1.315 - 0.119 * T)
  have hinv : 1 / Real.exp (1.315 - 0.119 * T) > 0 := div_pos one_pos hexp
  nlinarith

/-- **The buggy formula diverges from the correct formula**.
    They are NOT algebraically equivalent. -/
theorem reemt_npp_ne_correct (T : ℝ) : nppReemtBuggy T ≠ nppTemp T := by
  intro h
  have h1 := reemt_npp_exceeds_max T
  have h2 := nppTemp_lt_max T
  linarith

/-! ### Suggested Fix

The corrected r.mapcalc expression should be:
```bash
r.mapcalc "NPP_trad = if(tmean_loc > 0, 3000/(1+exp(1.315-0.119*(tmax_loc+tmin_loc)/2)), 0)"
```

Or equivalently (with explicit parenthesization):
```bash
r.mapcalc "NPP_trad = if(tmean_loc > 0, 3000*(1+exp(1.315-0.119*(tmax_loc+tmin_loc)/2))^(-1), 0)"
```
Note: `(...)^(-1)` must apply to the ENTIRE `(1+exp(...))`, not just `exp(...)`.
-/

end EEMTVerify.EEMT
