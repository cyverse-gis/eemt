/-
  Biological Energy Component (E_BIO) Verification
  ==================================================
  Verifies E_BIO = NPP × h_BIO, the energy stored in biomass.

  Source: eemt/eemt/reemt.sh (r.mapcalc expressions)
  Docs: docs/algorithms/eemt-calculations.md lines 33-37
-/

import EEMTVerify.Foundation.Constants
import EEMTVerify.EEMT.NPPLieth

namespace EEMTVerify.EEMT

open EEMTVerify.Constants

/-! ## E_BIO Definition

E_BIO = NPP × h_BIO

where:
- NPP = Net Primary Production [g/m²/yr] (from Lieth model)
- h_BIO = Specific enthalpy of biomass = 22 × 10⁶ J/kg (from bomb calorimetry)
- E_BIO = Biological energy [J/m²/yr]

From eemt/eemt/reemt.sh:
```bash
r.mapcalc "E_bio_trad = if(tmean_loc > 0, NPP_trad*(22*10^6), 0)"
```
-/

/-- Biological energy component [J/m²/yr].
    E_BIO = NPP × h_BIO -/
noncomputable def eBio (npp : ℝ) : ℝ :=
  npp * hBio

/-- E_BIO in MJ/m²/yr (divide by 10⁶). -/
noncomputable def eBioMJ (npp : ℝ) : ℝ :=
  eBio npp / 1e6

/-! ## Properties -/

/-- **E_BIO is non-negative when NPP is non-negative**. -/
theorem eBio_nonneg (npp : ℝ) (h : npp ≥ 0) : eBio npp ≥ 0 := by
  unfold eBio
  exact mul_nonneg h (le_of_lt hBio_pos)

/-- **E_BIO is proportional to NPP** (structural identity). -/
theorem eBio_eq (npp : ℝ) : eBio npp = npp * hBio := by
  unfold eBio; rfl

/-- E_BIO is strictly positive when NPP is positive. -/
theorem eBio_pos (npp : ℝ) (h : npp > 0) : eBio npp > 0 := by
  unfold eBio
  exact mul_pos h hBio_pos

/-- E_BIO is zero when NPP is zero. -/
theorem eBio_zero : eBio 0 = 0 := by
  unfold eBio; ring

/-- **E_BIO increases with NPP** (monotone). -/
theorem eBio_strictMono : StrictMono eBio := by
  intro a b hab
  unfold eBio
  exact mul_lt_mul_of_pos_right hab hBio_pos

/-- E_BIO from the Lieth model is bounded above.
    Since NPP < 3000 g/m²/yr, E_BIO < 3000 × 22 × 10⁶ = 66 × 10⁹ J/m²/yr. -/
theorem eBio_lieth_bounded (T : ℝ) :
    eBio (nppTemp T) < nppMax * hBio := by
  unfold eBio
  exact mul_lt_mul_of_pos_right (nppTemp_lt_max T) hBio_pos

/-! ## Structural Correspondence

Lean `eBio` matches reemt.sh:
```bash
r.mapcalc "E_bio_trad = if(tmean_loc > 0, NPP_trad*(22*10^6), 0)"
r.mapcalc "E_bio_topo = if(tmean_loc > 0, NPP_topo*(22*10^6), 0)"
```

The `if(tmean_loc > 0, ...)` guard sets E_BIO = 0 for sub-zero temperatures.
In the Lean model, this is handled by the NPP model returning 0 for cold temps.

The constant `22*10^6` matches `hBio = 22.0e6`.
-/

end EEMTVerify.EEMT
