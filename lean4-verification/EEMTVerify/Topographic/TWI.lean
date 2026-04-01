/-
  Topographic Wetness Index (TWI) Verification
  ==============================================
  Verifies TWI = ln(A_s / tan(β)) and the Mass Conservative Wetness Index.

  Source: eemt/eemt/twi.sh (SAGA-GIS computation)
  Docs: docs/algorithms/topographic-analysis.md lines 16-23, 85-98
-/

import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

namespace EEMTVerify.Topographic

open Real

/-! ## Topographic Wetness Index

TWI = ln(A_s / tan(β))

where:
- A_s = specific contributing area [m²/m contour width]
- β = local slope angle [radians]
- tan(β) = local slope gradient

Physical interpretation:
- High TWI (>10): convergent areas, valleys, streams
- Low TWI (<4): ridges, steep slopes
- TWI captures the balance between water accumulation (A_s) and drainage (tan β)
-/

/-- Topographic Wetness Index.
    TWI = ln(A_s / tan(β)) -/
noncomputable def twi (area : ℝ) (slope : ℝ) : ℝ :=
  Real.log (area / Real.tan slope)

/-- TWI is well-defined when area > 0 and slope > 0 (tan > 0). -/
theorem twi_well_defined (A : ℝ) (β : ℝ)
    (hA : A > 0) (hβ : 0 < β) (hβ2 : β < Real.pi / 2) :
    twi A β = Real.log A - Real.log (Real.tan β) := by
  unfold twi
  rw [Real.log_div (ne_of_gt hA) (ne_of_gt (Real.tan_pos_of_pos_of_lt_pi_div_two hβ hβ2))]

/-- Steeper slope → lower TWI (better drainage). -/
theorem twi_decreasing_slope (A β₁ β₂ : ℝ)
    (hA : A > 0)
    (hβ1 : 0 < β₁) (hβ1' : β₁ < Real.pi / 2)
    (hβ2 : 0 < β₂) (hβ2' : β₂ < Real.pi / 2)
    (hlt : β₁ < β₂) :
    twi A β₂ < twi A β₁ := by
  unfold twi
  apply Real.log_lt_log
  · exact div_pos hA (Real.tan_pos_of_pos_of_lt_pi_div_two hβ2 hβ2')
  · -- A/tan(β₂) < A/tan(β₁) since tan(β₂) > tan(β₁) (tan increasing on (0,π/2))
    exact div_lt_div_of_pos_left hA
      (Real.tan_pos_of_pos_of_lt_pi_div_two hβ1 hβ1')
      (Real.tan_lt_tan_of_nonneg_of_lt_pi_div_two (le_of_lt hβ1) hβ2' hlt)

/-- Larger contributing area → higher TWI (more water). -/
theorem twi_increasing_area (A₁ A₂ β : ℝ)
    (hA1 : A₁ > 0) (_hA2 : A₂ > 0)
    (hβ : 0 < β) (hβ' : β < Real.pi / 2)
    (hlt : A₁ < A₂) :
    twi A₁ β < twi A₂ β := by
  unfold twi
  apply Real.log_lt_log
  · exact div_pos hA1 (Real.tan_pos_of_pos_of_lt_pi_div_two hβ hβ')
  · exact div_lt_div_of_pos_right hlt (Real.tan_pos_of_pos_of_lt_pi_div_two hβ hβ')

/-! ## Mass Conservative Wetness Index (MCWI)

MCWI normalizes TWI to conserve total precipitation mass:
  MCWI_i = TWI_i × (P̄ / TWI̅)

The key conservation law: Σ MCWI_i = Σ P_i
-/

/-- MCWI normalization factor. -/
noncomputable def mcwiScale (meanPrecip meanTWI : ℝ) : ℝ :=
  meanPrecip / meanTWI

/-- MCWI at a single point. -/
noncomputable def mcwi (twiVal meanPrecip meanTWI : ℝ) : ℝ :=
  twiVal * mcwiScale meanPrecip meanTWI

/-- MCWI is proportional to TWI (linear scaling preserves relative ordering). -/
theorem mcwi_monotone (meanP meanTWI : ℝ) (hTWI : meanTWI > 0) (hP : meanP > 0) :
    StrictMono (fun t => mcwi t meanP meanTWI) := by
  intro a b hab
  unfold mcwi mcwiScale
  exact mul_lt_mul_of_pos_right hab (div_pos hP hTWI)

/-! ## Structural Correspondence

TWI computation in eemt/eemt/twi.sh:
```bash
saga_cmd ta_hydrology 15  # SAGA TWI algorithm
```
This internally computes: TWI = ln(specific_catchment_area / tan(slope))

MCWI is computed in the EEMT workflow to redistribute precipitation
according to topographic wetness while conserving total mass.
-/

end EEMTVerify.Topographic
