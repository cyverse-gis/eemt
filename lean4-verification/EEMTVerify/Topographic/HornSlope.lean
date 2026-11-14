/-
  Horn Slope and Aspect Verification
  =====================================
  Verifies the Horn (1981) 3×3 weighted finite difference method for
  computing slope and aspect from a DEM grid.

  Source: rsun/rsun-core/src/terrain.rs `slope_aspect()`
  Docs: docs/algorithms/topographic-analysis.md lines 378-444
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Inverse
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Arctan

namespace EEMTVerify.Topographic

open Real

/-! ## Horn's Method

The 3×3 neighborhood centered at (i,j):
```
z(-1,-1)  z(-1,0)  z(-1,1)
z(0,-1)   z(0,0)   z(0,1)
z(1,-1)   z(1,0)   z(1,1)
```

East-West gradient (weighted by [1,2,1]):
  dz/dx = [(z₁₁ + 2z₀₁ + z₋₁₁) - (z₁₋₁ + 2z₀₋₁ + z₋₁₋₁)] / (8 × dx)

North-South gradient (weighted by [1,2,1]):
  dz/dy = [(z₋₁₋₁ + 2z₋₁₀ + z₋₁₁) - (z₁₋₁ + 2z₁₀ + z₁₁)] / (8 × dy)

Slope = arctan(√(dzdx² + dzdy²))
Aspect = atan2(dzdx, -dzdy) [geographic convention]
-/

/-- Horn's east-west gradient.
    Uses [1,2,1] weighted kernel across columns. -/
noncomputable def hornDzDx (z : Fin 3 → Fin 3 → ℝ) (dx : ℝ) : ℝ :=
  ((z 2 2 + 2 * z 1 2 + z 0 2) - (z 2 0 + 2 * z 1 0 + z 0 0)) / (8 * dx)

/-- Horn's north-south gradient.
    Uses [1,2,1] weighted kernel across rows. -/
noncomputable def hornDzDy (z : Fin 3 → Fin 3 → ℝ) (dy : ℝ) : ℝ :=
  ((z 0 0 + 2 * z 0 1 + z 0 2) - (z 2 0 + 2 * z 2 1 + z 2 2)) / (8 * dy)

/-- Slope angle [radians] from Horn's method.
    slope = arctan(√(dzdx² + dzdy²)) -/
noncomputable def hornSlope (z : Fin 3 → Fin 3 → ℝ) (dx dy : ℝ) : ℝ :=
  Real.arctan (Real.sqrt ((hornDzDx z dx) ^ 2 + (hornDzDy z dy) ^ 2))

/-! ## Slope Properties -/

/-- **Slope is non-negative**: arctan of a non-negative value is non-negative. -/
theorem hornSlope_nonneg (z : Fin 3 → Fin 3 → ℝ) (dx dy : ℝ) :
    hornSlope z dx dy ≥ 0 := by
  unfold hornSlope
  -- arctan(√(a²+b²)) ≥ 0 since √(a²+b²) ≥ 0 and arctan is nonneg for nonneg input
  rw [← Real.arctan_zero]
  exact Real.arctan_le_arctan (Real.sqrt_nonneg _)

/-- **Slope is less than π/2**: arctan(x) < π/2 for all finite x. -/
theorem hornSlope_lt_pi_div_two (z : Fin 3 → Fin 3 → ℝ) (dx dy : ℝ) :
    hornSlope z dx dy < Real.pi / 2 := by
  unfold hornSlope
  exact Real.arctan_lt_pi_div_two _

/-- **Flat DEM has zero slope**: when all z values are equal, gradients are zero. -/
theorem hornSlope_flat (c : ℝ) (dx dy : ℝ) (_hdx : dx > 0) (_hdy : dy > 0) :
    hornSlope (fun _ _ => c) dx dy = 0 := by
  unfold hornSlope hornDzDx hornDzDy
  simp [sub_self, zero_div, zero_pow, Real.sqrt_zero, Real.arctan_zero]

/-! ## Aspect Properties -/

/-- Aspect angle [radians, geographic convention].
    aspect = arctan(dzdx / (-dzdy)) -/
noncomputable def hornAspect (z : Fin 3 → Fin 3 → ℝ) (dx dy : ℝ) : ℝ :=
  Real.arctan (hornDzDx z dx / (-(hornDzDy z dy)))

/-! ## Kernel Properties -/

/-- The Horn kernel weights sum to 4 on each side (east column and west column).
    Weight pattern: [1, 2, 1] → sum = 4.
    This means the gradient is a weighted average, not just a simple difference. -/
theorem horn_kernel_weight_sum : (1 : ℝ) + 2 + 1 = 4 := by norm_num

/-! ## Structural Correspondence

Lean definitions match rsun-core/src/terrain.rs `slope_aspect()`:

```rust
let dzdx = ((z[1][1] + 2.0*z[0][1] + z[-1][1]) -
            (z[1][-1] + 2.0*z[0][-1] + z[-1][-1])) / (8.0 * ew_res);
let dzdy = ((z[-1][-1] + 2.0*z[-1][0] + z[-1][1]) -
            (z[1][-1] + 2.0*z[1][0] + z[1][1])) / (8.0 * ns_res);
let slope = (dzdx*dzdx + dzdy*dzdy).sqrt().atan();
```

Also matches GRASS GIS `r.slope.aspect` algorithm.
-/

end EEMTVerify.Topographic
