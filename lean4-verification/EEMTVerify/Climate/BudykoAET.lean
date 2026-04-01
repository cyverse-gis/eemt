/-
  Budyko Actual Evapotranspiration Verification
  ===============================================
  Verifies the Zhang-Budyko curve for computing actual evapotranspiration.

  Source: eemt/eemt/reemt.sh (r.mapcalc expression)
  Docs: docs/algorithms/climate-integration.md lines 205-215
        docs/algorithms/eemt-calculations.md lines 184-214
-/

import Mathlib.Analysis.SpecialFunctions.Pow.Real
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Climate

open Real EEMTVerify.Constants

/-! ## Zhang-Budyko Equation

The Budyko framework relates actual evapotranspiration (AET) to
precipitation (P) and potential evapotranspiration (PET).

From docs/algorithms/eemt-calculations.md:
  AET/P = 1 + PET/P - (1 + (PET/P)^ω)^(1/ω)

Equivalently:
  AET = P × (1 + PET/P - (1 + (PET/P)^ω)^(1/ω))

where ω = 2.63 (Fu 1981 shape parameter).

From eemt/eemt/reemt.sh:
```bash
r.mapcalc "AET_zb = prcp*(1+(PET_topo/prcp)-(1+(PET_topo/prcp)^2.63)^(1/2.63))"
```
-/

/-- Aridity index: ratio of potential evapotranspiration to precipitation.
    AI = PET / P
    AI > 1: arid (energy-limited regime)
    AI < 1: humid (water-limited regime) -/
noncomputable def aridityIndex (pet : ℝ) (precip : ℝ) : ℝ :=
  pet / precip

/-- Zhang-Budyko AET ratio (AET/P as a function of aridity index).
    f(AI) = 1 + AI - (1 + AI^ω)^(1/ω) -/
noncomputable def budykoRatio (ai : ℝ) (ω : ℝ := budykoOmega) : ℝ :=
  1 + ai - (1 + ai ^ ω) ^ (1 / ω)

/-- Actual evapotranspiration [mm] from Budyko framework.
    AET = P × budykoRatio(PET/P) -/
noncomputable def budykoAET (precip pet : ℝ) (ω : ℝ := budykoOmega) : ℝ :=
  precip * budykoRatio (pet / precip) ω

/-- Effective precipitation (water surplus after ET).
    P_eff = P - AET -/
noncomputable def effectivePrecip (precip pet : ℝ) (ω : ℝ := budykoOmega) : ℝ :=
  precip - budykoAET precip pet ω

/-! ## Physical Bounds

The key constraints that any evapotranspiration model must satisfy:
1. AET ≥ 0 (can't have negative evaporation)
2. AET ≤ P (can't evaporate more water than falls)
3. AET ≤ PET (can't exceed potential evapotranspiration)

These are the "Budyko bounds" that define the feasible region.
-/

/-- **Budyko ratio is at most 1**: AET/P ≤ 1, i.e., AET ≤ P.
    This is the water balance constraint. -/
theorem budykoRatio_le_one (ai : ℝ) (hai : ai ≥ 0) (ω : ℝ) (hω : ω > 1) :
    budykoRatio ai ω ≤ 1 := by
  unfold budykoRatio
  -- Need: 1 + ai - (1 + ai^ω)^(1/ω) ≤ 1
  -- Equiv: ai ≤ (1 + ai^ω)^(1/ω)
  -- By Minkowski inequality: (1 + ai^ω)^(1/ω) ≥ (ai^ω)^(1/ω) = ai
  sorry -- Requires real power function inequalities

/-- **Budyko ratio is non-negative**: AET ≥ 0.
    Evapotranspiration cannot be negative. -/
theorem budykoRatio_nonneg (ai : ℝ) (hai : ai ≥ 0) (ω : ℝ) (hω : ω > 1) :
    budykoRatio ai ω ≥ 0 := by
  unfold budykoRatio
  -- Need: 1 + ai - (1 + ai^ω)^(1/ω) ≥ 0
  -- Equiv: 1 + ai ≥ (1 + ai^ω)^(1/ω)
  -- By concavity of x^(1/ω) for ω > 1: (1 + ai^ω)^(1/ω) ≤ 1 + ai
  sorry -- Requires Jensen's inequality / power mean inequality

/-- **Budyko ratio ≤ aridity index**: AET ≤ PET.
    Can't evaporate more than the atmosphere can absorb. -/
theorem budykoRatio_le_ai (ai : ℝ) (hai : ai ≥ 0) (ω : ℝ) (hω : ω > 1) :
    budykoRatio ai ω ≤ ai := by
  unfold budykoRatio
  -- Need: 1 + ai - (1 + ai^ω)^(1/ω) ≤ ai
  -- Equiv: 1 ≤ (1 + ai^ω)^(1/ω)
  -- Since 1 + ai^ω ≥ 1 and 1/ω > 0: (1 + ai^ω)^(1/ω) ≥ 1^(1/ω) = 1
  sorry -- Requires monotonicity of x^(1/ω) for x ≥ 1

/-! ## Limiting Behavior -/

/-- At zero aridity (AI = 0): AET/P = 0 (no evapotranspiration without energy). -/
theorem budykoRatio_at_zero (ω : ℝ) (hω : ω > 0) :
    budykoRatio 0 ω = 0 := by
  unfold budykoRatio
  simp [zero_rpow (ne_of_gt hω)]

/-! ## Effective Precipitation Properties -/

/-- Effective precipitation is non-negative when AET ≤ P. -/
theorem effectivePrecip_nonneg_of_aet_le_precip (P PET : ℝ)
    (hP : P > 0) (hPET : PET ≥ 0) (ω : ℝ) (hω : ω > 1)
    (h_ratio : budykoRatio (PET / P) ω ≤ 1) :
    effectivePrecip P PET ω ≥ 0 := by
  unfold effectivePrecip budykoAET
  nlinarith

/-! ## Structural Correspondence

Lean `budykoAET` matches reemt.sh:
```bash
r.mapcalc "AET_zb = prcp*(1+(PET_topo/prcp)-(1+(PET_topo/prcp)^2.63)^(1/2.63))"
```

The coefficients match exactly:
- ω = 2.63 = `budykoOmega`
- 1/ω = 1/2.63

**Note**: The reemt.sh expression assumes prcp > 0 (division by prcp).
This should be guarded against zero precipitation.
-/

end EEMTVerify.Climate
