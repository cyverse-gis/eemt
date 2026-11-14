/-
  Process Rate Predictions Verification
  =======================================
  Verifies empirical models predicting geomorphic process rates from EEMT.

  Docs: docs/algorithms/eemt-calculations.md lines 430-457
  References: Pelletier & Rasmussen (2009), Rasmussen et al. (2011)
-/

import Mathlib.Analysis.SpecialFunctions.ExpDeriv
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.EEMT

open Real EEMTVerify.Constants

/-! ## Soil Production Rate (Exponential Decay)

P = P₀ × exp(-k × EEMT)

From docs/algorithms/eemt-calculations.md lines 430-434:
- P₀ = 0.05 mm/yr (maximum production rate)
- k = 0.02 MJ⁻¹ m² yr (decay constant)

Physical interpretation: Higher EEMT increases weathering and transport,
reducing bedrock exposure, thus lowering soil production rate.
-/

/-- Soil production rate [mm/yr]. -/
noncomputable def soilProductionRate (eemtVal : ℝ) : ℝ :=
  0.05 * Real.exp (-0.02 * eemtVal)

/-- Soil production is strictly positive (exponential never reaches zero). -/
theorem soilProduction_pos (E : ℝ) : soilProductionRate E > 0 := by
  unfold soilProductionRate
  exact mul_pos (by norm_num) (Real.exp_pos _)

/-- **Soil production decreases with EEMT** (antitone).
    Higher energy flux → more weathering → less bedrock → less production. -/
theorem soilProduction_antitone : Antitone soilProductionRate := by
  intro a b hab
  unfold soilProductionRate
  apply mul_le_mul_of_nonneg_left _ (by norm_num)
  exact Real.exp_le_exp.mpr (by linarith)

/-- Soil production is bounded above by P₀ = 0.05 mm/yr. -/
theorem soilProduction_le_max (E : ℝ) (hE : E ≥ 0) :
    soilProductionRate E ≤ 0.05 := by
  unfold soilProductionRate
  have h : Real.exp (-0.02 * E) ≤ 1 :=
    Real.exp_le_one_iff.mpr (by nlinarith)
  nlinarith

/-! ## Chemical Denudation Rate (Linear)

D_chem = 0.15 × EEMT + 5

From docs/algorithms/eemt-calculations.md lines 436-438.
-/

/-- Chemical denudation rate [t/km²/yr]. -/
noncomputable def chemDenudation (eemtVal : ℝ) : ℝ :=
  0.15 * eemtVal + 5

/-- Chemical denudation has a positive baseline (5 t/km²/yr). -/
theorem chemDenudation_baseline : chemDenudation 0 = 5 := by
  unfold chemDenudation; ring

/-- Chemical denudation is positive for non-negative EEMT. -/
theorem chemDenudation_pos (E : ℝ) (hE : E ≥ 0) : chemDenudation E > 0 := by
  unfold chemDenudation; linarith

/-- **Chemical denudation increases with EEMT** (monotone). -/
theorem chemDenudation_monotone : Monotone chemDenudation := by
  intro a b hab
  unfold chemDenudation; linarith

/-- Chemical denudation is strictly increasing. -/
theorem chemDenudation_strictMono : StrictMono chemDenudation := by
  intro a b hab
  unfold chemDenudation; linarith

/-! ## Biomass Accumulation (Logistic)

Biomass = K / (1 + exp(-r × (EEMT - 70)))

From docs/algorithms/eemt-calculations.md lines 454-457:
- K = 50 kg/m² (carrying capacity)
- r = 0.05 MJ⁻¹ m² yr (growth rate)
- Inflection point = 70 MJ/m²/yr (regime threshold)
-/

/-- Biomass accumulation [kg/m²] — logistic model. -/
noncomputable def biomassAccum (eemtVal : ℝ) : ℝ :=
  50 / (1 + Real.exp (-0.05 * (eemtVal - 70)))

/-- Biomass is strictly positive. -/
theorem biomassAccum_pos (E : ℝ) : biomassAccum E > 0 := by
  unfold biomassAccum
  exact div_pos (by norm_num) (by linarith [Real.exp_pos (-0.05 * (E - 70))])

/-- **Biomass is bounded above by carrying capacity K = 50 kg/m²**. -/
theorem biomassAccum_lt_carrying (E : ℝ) : biomassAccum E < 50 := by
  unfold biomassAccum
  rw [div_lt_iff (by linarith [Real.exp_pos (-0.05 * (E - 70))])]
  nlinarith [Real.exp_pos (-0.05 * (E - 70))]

/-- At the regime threshold (EEMT = 70), biomass = K/2 = 25 kg/m². -/
theorem biomassAccum_at_threshold : biomassAccum 70 = 25 := by
  unfold biomassAccum
  simp [sub_self, mul_zero, neg_zero, Real.exp_zero]
  norm_num

/-! ## Structural Correspondence

All three process rate models are documented in
docs/algorithms/eemt-calculations.md. They are empirical correlations
from published literature — we verify structural correctness and
physical bounds, not derivation from first principles.

| Model | Equation | Reference |
|-------|----------|-----------|
| Soil production | P₀ × exp(-k×EEMT) | Pelletier & Rasmussen (2009) |
| Chemical denudation | 0.15×EEMT + 5 | Rasmussen et al. (2011) |
| Biomass accumulation | K/(1+exp(-r(EEMT-70))) | Logistic growth model |
-/

end EEMTVerify.EEMT
