/-
  Precipitation Energy Component (E_PPT) Verification
  =====================================================
  Verifies E_PPT = ρ_w × P_eff × c_w × ΔT, the thermal energy
  delivered to the subsurface by effective precipitation.

  Source: eemt/eemt/reemt.sh (r.mapcalc expressions)
  Docs: docs/algorithms/eemt-calculations.md lines 173-179, 220-244
-/

import EEMTVerify.Foundation.Constants

namespace EEMTVerify.EEMT

open EEMTVerify.Constants

/-! ## E_PPT Definition

E_PPT = ρ_w × P_eff × c_w × ΔT

where:
- ρ_w = 1000 kg/m³ (density of water)
- P_eff = effective precipitation [m/yr] (precipitation minus ET)
- c_w = 4180 J/(kg·K) (specific heat of water)
- ΔT = max(0, T - T_ref) [K] (temperature above freezing)
- E_PPT = thermal energy [J/m²/yr]

From docs/algorithms/eemt-calculations.md:
> "Energy delivered to subsurface via precipitation-driven water flux"
-/

/-- Temperature delta: temperature above freezing (zero for sub-zero). -/
noncomputable def tempDelta (T : ℝ) (tRef : ℝ := 0) : ℝ :=
  max 0 (T - tRef)

/-- Precipitation energy component [J/m²/yr].
    E_PPT = ρ_w × P_eff × c_w × ΔT -/
noncomputable def ePpt (pEff : ℝ) (T : ℝ) : ℝ :=
  rhoWater * pEff * cWater * tempDelta T

/-- E_PPT in MJ/m²/yr. -/
noncomputable def ePptMJ (pEff : ℝ) (T : ℝ) : ℝ :=
  ePpt pEff T / 1e6

/-! ## Temperature Delta Properties -/

/-- ΔT is non-negative by construction. -/
theorem tempDelta_nonneg (T : ℝ) (tRef : ℝ := 0) : tempDelta T tRef ≥ 0 := by
  unfold tempDelta
  exact le_max_left 0 (T - tRef)

/-- **ΔT is zero when temperature is at or below freezing**. -/
theorem tempDelta_zero_frozen (T : ℝ) (hT : T ≤ 0) : tempDelta T = 0 := by
  unfold tempDelta
  simp only [sub_zero]
  exact max_eq_left (by linarith)

/-- ΔT equals T for positive temperatures (with default ref = 0). -/
theorem tempDelta_eq_of_pos (T : ℝ) (hT : T > 0) : tempDelta T = T := by
  unfold tempDelta
  simp only [sub_zero]
  exact max_eq_right (le_of_lt hT)

/-- ΔT increases with temperature (monotone). -/
theorem tempDelta_monotone : Monotone (fun T => tempDelta T) := by
  intro a b hab
  unfold tempDelta
  exact max_le_max_left 0 (by linarith)

/-! ## E_PPT Properties -/

/-- **E_PPT is non-negative** when precipitation and temperature are physical. -/
theorem ePpt_nonneg (pEff T : ℝ) (hP : pEff ≥ 0) :
    ePpt pEff T ≥ 0 := by
  unfold ePpt
  apply mul_nonneg
  · apply mul_nonneg
    · apply mul_nonneg (le_of_lt rhoWater_pos) hP
    · exact le_of_lt cWater_pos
  · exact tempDelta_nonneg T

/-- **E_PPT is zero when temperature is at or below freezing**.
    No thermal energy transfer when water is frozen. -/
theorem ePpt_zero_frozen (pEff : ℝ) (T : ℝ) (hT : T ≤ 0) :
    ePpt pEff T = 0 := by
  unfold ePpt
  rw [tempDelta_zero_frozen T hT]
  ring

/-- **E_PPT is zero when there is no effective precipitation**. -/
theorem ePpt_zero_no_precip (T : ℝ) :
    ePpt 0 T = 0 := by
  unfold ePpt; ring

/-- E_PPT increases with temperature (when pEff > 0). -/
theorem ePpt_monotone_temp (pEff : ℝ) (hP : pEff ≥ 0) :
    Monotone (fun T => ePpt pEff T) := by
  intro a b hab
  unfold ePpt
  apply mul_le_mul_of_nonneg_left (tempDelta_monotone hab)
  apply mul_nonneg
  · exact mul_nonneg (le_of_lt rhoWater_pos) hP
  · exact le_of_lt cWater_pos

/-- E_PPT increases with precipitation (when T > 0). -/
theorem ePpt_monotone_precip (T : ℝ) :
    Monotone (fun P => ePpt P T) := by
  intro a b hab
  unfold ePpt
  apply mul_le_mul_of_nonneg_right _ (tempDelta_nonneg T)
  apply mul_le_mul_of_nonneg_right _ (le_of_lt cWater_pos)
  exact mul_le_mul_of_nonneg_left hab (le_of_lt rhoWater_pos)

/-! ## Structural Correspondence

From eemt/eemt/reemt.sh (simplified):
```bash
r.mapcalc "E_ppt_trad = if(prcp > 0, (prcp - PET_Trad*10)*4185.5, 0)"
```

Note: The reemt.sh uses `4185.5` as the combined constant ρ_w × c_w
(approximately 1000 × 4.186 = 4186 J/(m²·mm·K)), and folds the
temperature delta into the precipitation term.

The Lean model separates these for clarity:
- `ePpt pEff T` = ρ_w × pEff × c_w × max(0, T)
-/

end EEMTVerify.EEMT
