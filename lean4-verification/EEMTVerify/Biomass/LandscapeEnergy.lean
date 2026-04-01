/-
  Landscape Energy Census Verification
  ======================================
  Verifies E_total = Σ E_i and spatial energy density calculations.

  Docs: docs/energetics.md lines 111-116
-/

import EEMTVerify.Biomass.Allometric

namespace EEMTVerify.Biomass

open EEMTVerify.Constants

/-! ## Landscape Energy

E_total = Σᵢ E_i = Σᵢ (AGB_i × HHV)
E_density = E_total / Area

From docs/energetics.md:
> "The landscape energy census sums individual tree energies
> to quantify total stored chemical energy across the study area."
-/

/-- Total landscape energy [MJ] as sum of individual tree energies. -/
noncomputable def landscapeEnergy (treeEnergies : List ℝ) : ℝ :=
  treeEnergies.sum

/-- Energy density [MJ/m²] = total energy / area. -/
noncomputable def energyDensity (totalEnergy : ℝ) (area : ℝ) : ℝ :=
  totalEnergy / area

/-! ## Properties -/

/-- **Landscape energy is additive**: adding a tree increases total. -/
theorem landscapeEnergy_cons (e : ℝ) (es : List ℝ) :
    landscapeEnergy (e :: es) = e + landscapeEnergy es := by
  unfold landscapeEnergy
  exact List.sum_cons

/-- Landscape energy of empty forest is zero. -/
theorem landscapeEnergy_nil : landscapeEnergy [] = 0 := by
  unfold landscapeEnergy; simp

/-- **Landscape energy is non-negative** when all tree energies are non-negative. -/
theorem landscapeEnergy_nonneg (es : List ℝ) (h : ∀ e ∈ es, e ≥ 0) :
    landscapeEnergy es ≥ 0 := by
  unfold landscapeEnergy
  induction es with
  | nil => simp
  | cons x xs ih =>
    rw [List.sum_cons]
    have hx := h x (List.mem_cons_self x xs)
    have hxs := ih (fun e he => h e (List.mem_cons_of_mem x he))
    linarith

/-- Adding more trees never decreases landscape energy (when trees have non-neg energy). -/
theorem landscapeEnergy_monotone (es : List ℝ) (e : ℝ) (he : e ≥ 0) :
    landscapeEnergy es ≤ landscapeEnergy (e :: es) := by
  rw [landscapeEnergy_cons]
  linarith

/-- Energy density is non-negative when total energy and area are positive. -/
theorem energyDensity_nonneg (E A : ℝ) (hE : E ≥ 0) (hA : A > 0) :
    energyDensity E A ≥ 0 := by
  unfold energyDensity
  exact div_nonneg hE (le_of_lt hA)

/-- Doubling the area halves the energy density. -/
theorem energyDensity_double_area (E A : ℝ) (_hA : A > 0) :
    energyDensity E (2 * A) = energyDensity E A / 2 := by
  unfold energyDensity
  rw [div_div, mul_comm]

/-! ## Linearity of Energy Summation -/

/-- Landscape energy equals HHV × total AGB (by linearity). -/
theorem landscapeEnergy_eq_hhv_times_total_agb (agbs : List ℝ) :
    landscapeEnergy (agbs.map (· * hhvPinus)) = landscapeEnergy agbs * hhvPinus := by
  unfold landscapeEnergy
  induction agbs with
  | nil => simp
  | cons x xs ih =>
    simp [List.sum_cons, ih]
    ring

/-! ## Structural Correspondence

From docs/energetics.md:
```
E_total = Σᵢ E_i
E_density = E_total / Area
```

Gordon Gulch results:
- n = 253,476 trees
- E_total = 5.82 × 10⁸ MJ
- E_density = 2.24 × 10⁵ MJ/ha = 2.24 × 10¹ MJ/m²
-/

end EEMTVerify.Biomass
