/-
  EEMT Core Theorem
  ==================
  The central verification: EEMT = E_BIO + E_PPT

  This is the most important theorem in the entire verification project.
  It establishes that the total effective energy and mass transfer is
  the sum of biological energy (photosynthesis) and precipitation energy
  (thermal water flux).

  Source: eemt/eemt/reemt.sh lines 201-202
  Docs: docs/algorithms/eemt-calculations.md lines 13-27
  Reference: Rasmussen et al. (2005, 2011)
-/

import EEMTVerify.EEMT.EBio
import EEMTVerify.EEMT.EPpt

namespace EEMTVerify.EEMT

open EEMTVerify.Constants

/-! ## EEMT Definition

EEMT = E_BIO + E_PPT [MJ/m²/yr]

From docs/algorithms/eemt-calculations.md:
> "EEMT quantifies the total energy available for pedogenic (soil-forming)
> processes, combining biological energy storage through photosynthesis
> with thermal energy delivered by effective precipitation."

From eemt/eemt/reemt.sh:
```bash
r.mapcalc "EEMT_Trad = (E_ppt_trad + E_bio_trad)/1000000"
```
-/

/-- **Effective Energy and Mass Transfer** [J/m²/yr].
    EEMT = E_BIO + E_PPT -/
noncomputable def eemt (npp : ℝ) (pEff : ℝ) (T : ℝ) : ℝ :=
  eBio npp + ePpt pEff T

/-- EEMT in MJ/m²/yr (the standard reporting unit). -/
noncomputable def eemtMJ (npp : ℝ) (pEff : ℝ) (T : ℝ) : ℝ :=
  eemt npp pEff T / 1e6

/-! ## The Central Theorem -/

/-- **EEMT Decomposition**: EEMT is exactly the sum of its two components.
    This is the fundamental structural identity. -/
theorem eemt_decomposition (npp pEff T : ℝ) :
    eemt npp pEff T = eBio npp + ePpt pEff T := by
  unfold eemt; rfl

/-- **EEMT is non-negative** under physical input constraints.
    When NPP ≥ 0 and P_eff ≥ 0, both components are non-negative. -/
theorem eemt_nonneg (npp pEff T : ℝ) (hNPP : npp ≥ 0) (hP : pEff ≥ 0) :
    eemt npp pEff T ≥ 0 := by
  unfold eemt
  linarith [eBio_nonneg npp hNPP, ePpt_nonneg pEff T hP]

/-- EEMT is strictly positive when at least one component is positive. -/
theorem eemt_pos_of_bio_pos (npp pEff T : ℝ) (hNPP : npp > 0) (hP : pEff ≥ 0) :
    eemt npp pEff T > 0 := by
  unfold eemt
  linarith [eBio_pos npp hNPP, ePpt_nonneg pEff T hP]

/-! ## Component Dominance -/

/-- E_BIO dominates in cold, arid climates (T ≤ 0 → E_PPT = 0). -/
theorem bio_dominates_cold (npp pEff : ℝ) (T : ℝ) (hT : T ≤ 0) :
    eemt npp pEff T = eBio npp := by
  unfold eemt
  rw [ePpt_zero_frozen pEff T hT]
  ring

/-- In the absence of vegetation (NPP = 0), only precipitation energy matters. -/
theorem ppt_only_barren (pEff T : ℝ) :
    eemt 0 pEff T = ePpt pEff T := by
  unfold eemt
  rw [eBio_zero]
  ring

/-- In the absence of effective precipitation, only biological energy matters. -/
theorem bio_only_dry (npp T : ℝ) :
    eemt npp 0 T = eBio npp := by
  unfold eemt
  rw [ePpt_zero_no_precip]
  ring

/-! ## Monotonicity -/

/-- **EEMT increases with NPP** (more vegetation → more energy). -/
theorem eemt_monotone_npp (pEff T : ℝ) (_hP : pEff ≥ 0) :
    Monotone (fun npp => eemt npp pEff T) := by
  intro a b hab
  unfold eemt
  exact add_le_add_right (eBio_strictMono.monotone hab) _

/-- **EEMT increases with temperature** (warmer → more energy from both components). -/
theorem eemt_monotone_temp (npp pEff : ℝ) (hP : pEff ≥ 0) :
    Monotone (fun T => eemt npp pEff T) := by
  intro a b hab
  unfold eemt
  exact add_le_add_left (ePpt_monotone_temp pEff hP hab) _

/-! ## Regime Classification

EEMT < 70 MJ/m²/yr → Water-limited regime
EEMT ≥ 70 MJ/m²/yr → Energy-limited regime

From docs/algorithms/eemt-calculations.md lines 383-414.
-/

/-- Water-limited regime predicate. -/
def isWaterLimited (eemtVal : ℝ) : Prop := eemtVal < eemtRegimeThreshold

/-- Energy-limited regime predicate. -/
def isEnergyLimited (eemtVal : ℝ) : Prop := eemtVal ≥ eemtRegimeThreshold

/-- The two regimes are complementary (partition of all possible EEMT values). -/
theorem regime_partition (eemtVal : ℝ) :
    isWaterLimited eemtVal ∨ isEnergyLimited eemtVal := by
  unfold isWaterLimited isEnergyLimited
  exact lt_or_ge eemtVal eemtRegimeThreshold

/-- The two regimes are mutually exclusive. -/
theorem regime_exclusive (eemtVal : ℝ) :
    ¬(isWaterLimited eemtVal ∧ isEnergyLimited eemtVal) := by
  unfold isWaterLimited isEnergyLimited
  intro ⟨h1, h2⟩
  linarith

/-! ## Physical Bounds -/

/-- EEMT is bounded in the documented range [0.1, 500] MJ/m²/yr
    under physical input constraints. -/
-- This requires specifying the full input domain; stated as a specification.
def validEEMTRange (eemtMJVal : ℝ) : Prop :=
  eemtMin ≤ eemtMJVal ∧ eemtMJVal ≤ eemtMax

/-! ## Structural Correspondence

Lean `eemt` matches reemt.sh:
```bash
r.mapcalc "EEMT_Trad = (E_ppt_trad + E_bio_trad)/1000000"
r.mapcalc "EEMT_Topo = (E_ppt_topo + E_bio_topo)/1000000"
```

The `/1000000` converts from J/m²/yr to MJ/m²/yr, matching `eemtMJ`.

**Extended energy balance** (background/index.md):
  E_Total = E_ET + E_PPT + E_BIO + E_ELEV + E_GEO

EEMT focuses on the two components that drive pedogenesis:
  EEMT = E_BIO + E_PPT

The remaining terms (E_ET returns to atmosphere, E_ELEV drives physical
denudation, E_GEO drives chemical weathering) are not included in EEMT
but are part of the full Critical Zone energy balance.
-/

end EEMTVerify.EEMT
