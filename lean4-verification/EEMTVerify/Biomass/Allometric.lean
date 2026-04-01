/-
  Allometric Biomass Equations Verification
  ==========================================
  Verifies the Jucker et al. (2017) gymnosperm allometric equation
  for estimating aboveground biomass from tree height and crown diameter.

  Docs: docs/energetics.md lines 66-84
  Reference: Jucker et al. (2017) — Allometric equations for remote sensing
-/

import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import EEMTVerify.Foundation.Constants

namespace EEMTVerify.Biomass

open Real EEMTVerify.Constants

/-! ## Jucker Allometric Model (Gymnosperms)

The allometric equation for aboveground biomass:
  log(AGB) = α + β × log(H × CD) + ε

Back-transformed with Snowdon (1991) bias correction:
  AGB = 0.109 × (H × CD)^1.79 × 1.02

where:
- AGB = Aboveground biomass [kg]
- H = Tree height from LiDAR [m]
- CD = Crown diameter from segmentation [m]
- α = 0.109 (intercept, back-transformed)
- β = 1.79 (scaling exponent)
- 1.02 = Snowdon bias correction factor
-/

/-- Jucker allometric equation for aboveground biomass [kg].
    AGB = α × (H × CD)^β × bias_correction -/
noncomputable def agb (height : ℝ) (crownDiam : ℝ) : ℝ :=
  juckerAlpha * (height * crownDiam) ^ juckerBeta * snowdonBias

/-- Simpler form: AGB = 0.109 × (H × CD)^1.79 × 1.02 -/
theorem agb_eq (H CD : ℝ) : agb H CD = 0.109 * (H * CD) ^ (1.79 : ℝ) * 1.02 := by
  unfold agb juckerAlpha juckerBeta snowdonBias; rfl

/-! ## Positivity -/

/-- **AGB is positive** when both height and crown diameter are positive. -/
theorem agb_pos (H CD : ℝ) (hH : H > 0) (hCD : CD > 0) : agb H CD > 0 := by
  unfold agb juckerAlpha juckerBeta snowdonBias
  apply mul_pos
  · apply mul_pos (by norm_num : (0.109 : ℝ) > 0)
    exact rpow_pos_of_pos (mul_pos hH hCD) _
  · norm_num

/-- AGB is non-negative when inputs are non-negative. -/
theorem agb_nonneg (H CD : ℝ) (hH : H ≥ 0) (hCD : CD ≥ 0) : agb H CD ≥ 0 := by
  unfold agb juckerAlpha juckerBeta snowdonBias
  apply mul_nonneg
  · apply mul_nonneg (by norm_num : (0.109 : ℝ) ≥ 0)
    exact rpow_nonneg (mul_nonneg hH hCD) _
  · norm_num

/-! ## Monotonicity -/

/-- **AGB increases with height** (taller trees have more biomass).
    Proof: (H × CD)^β is increasing in H when CD > 0, since
    x^β is increasing for x > 0 and β > 0. -/
theorem agb_strictMono_height (CD : ℝ) (hCD : CD > 0) :
    StrictMono (fun H => agb H CD) := by
  intro a b hab
  unfold agb juckerAlpha juckerBeta snowdonBias
  -- (a*CD)^1.79 < (b*CD)^1.79 since a < b and CD > 0
  sorry -- Needs rpow_lt_rpow for strictly increasing power function

/-- **AGB increases with crown diameter** (wider crowns → more biomass). -/
theorem agb_strictMono_crown (H : ℝ) (hH : H > 0) :
    StrictMono (fun CD => agb H CD) := by
  intro a b hab
  unfold agb juckerAlpha juckerBeta snowdonBias
  sorry -- Symmetric to height case: (H*a)^1.79 < (H*b)^1.79

/-! ## Tree Energy Content

E_i = AGB_i × HHV

From docs/energetics.md lines 105-108.
-/

/-- Energy content of a single tree [MJ].
    E = AGB × HHV where HHV = 20.25 MJ/kg for Pinus. -/
noncomputable def treeEnergy (height : ℝ) (crownDiam : ℝ) : ℝ :=
  agb height crownDiam * hhvPinus

/-- Tree energy is positive when tree dimensions are positive. -/
theorem treeEnergy_pos (H CD : ℝ) (hH : H > 0) (hCD : CD > 0) :
    treeEnergy H CD > 0 := by
  unfold treeEnergy
  exact mul_pos (agb_pos H CD hH hCD) hhvPinus_pos

/-- Tree energy is non-negative. -/
theorem treeEnergy_nonneg (H CD : ℝ) (hH : H ≥ 0) (hCD : CD ≥ 0) :
    treeEnergy H CD ≥ 0 := by
  unfold treeEnergy
  exact mul_nonneg (agb_nonneg H CD hH hCD) (le_of_lt hhvPinus_pos)

/-! ## Structural Correspondence

Lean `agb` matches the documented equation:
  AGB = 0.109 × (H × CD)^1.79 × 1.02

Gordon Gulch case study results (docs/energetics.md):
- Mean AGB per tree: 113.4 ± 138.9 kg
- Total AGB: 28,754 Mg across 253,476 trees
- Mean tree energy: 2,297 MJ
-/

end EEMTVerify.Biomass
