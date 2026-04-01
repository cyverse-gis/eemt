/-
  Cosine of Solar Incidence Angle (Jenco Transformation)
  =======================================================
  Verifies the cos_incidence() function which computes the cosine of the
  angle between the sun's rays and a tilted surface normal.

  Source: rsun/rsun-core/src/radiation.rs `cos_incidence()`
  Origin: GRASS GIS lumcline2() — Jenco (1992) coordinate transformation
  Docs: docs/algorithms/solar-radiation.md lines 51-67
-/

import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Inverse
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Arctan
import EEMTVerify.Foundation.Constants
import EEMTVerify.Solar.SolarPosition

namespace EEMTVerify.Solar

open Real

/-! ## Jenco Transformation

The key idea: transform a tilted surface into an equivalent horizontal
surface at a different latitude and longitude, then compute the solar
altitude at that equivalent location.

For a surface with slope β and aspect α:
1. Compute equivalent latitude φ' and longitude λ'
2. The cos(incidence) = sin(altitude) at the equivalent location

From rsun-core/src/radiation.rs:
```rust
let cos_u = sin(slope);  // complement: u = π/2 - slope
let sin_u = cos(slope);
let cos_v = cos(π/2 + aspect);
let sin_v = sin(π/2 + aspect);

let sin_phi_l = -cos_lat * cos_u * sin_v + sin_lat * sin_u;
let q1 = sin_lat * cos_u * sin_v + cos_lat * sin_u;
let longit_l = atan(-cos_u * cos_v / q1);
// ... time offset logic ...
let s0 = cos(latid_l)*cos(decl)*cos(-ω - longit_l + offset) + sin_phi_l*sin(decl);
```
-/

/-- Equivalent latitude in the Jenco transformation.
    sin(φ') = -cos(φ)·sin(slope)·cos(aspect) + sin(φ)·cos(slope)

    Note: The Rust code uses `cos_u = sin(slope)`, `sin_u = cos(slope)`,
    `sin_v = sin(π/2 + aspect) = cos(aspect)`, so
    `sin_phi_l = -cos_lat * sin(slope) * cos(aspect) + sin_lat * cos(slope)` -/
noncomputable def jencoSinLatEquiv (lat : ℝ) (slope : ℝ) (aspect : ℝ) : ℝ :=
  -(Real.cos lat * Real.sin slope * Real.cos aspect) +
   Real.sin lat * Real.cos slope

/-- The q1 auxiliary for longitude computation.
    q1 = sin(φ)·sin(slope)·cos(aspect) + cos(φ)·cos(slope) -/
noncomputable def jencoQ1 (lat : ℝ) (slope : ℝ) (aspect : ℝ) : ℝ :=
  Real.sin lat * Real.sin slope * Real.cos aspect +
  Real.cos lat * Real.cos slope

/-- Equivalent longitude offset.
    λ' = atan(-sin(slope)·sin(aspect) / q1)

    Note: Rust uses cos_v = cos(π/2 + aspect) = -sin(aspect) and
    cos_u = sin(slope), giving: longit_l = atan(-sin(slope)*(-sin(aspect)) / q1)
    = atan(sin(slope)*sin(aspect) / q1)

    Wait — let me re-derive. In Rust:
    cos_v = cos(π/2 + aspect) = -sin(aspect)
    cos_u = sin(slope)
    numerator = -cos_u * cos_v = -sin(slope) * (-sin(aspect)) = sin(slope)*sin(aspect)
    So longit_l = atan(sin(slope)*sin(aspect) / q1) -/
noncomputable def jencoLongEquiv (lat : ℝ) (slope : ℝ) (aspect : ℝ) : ℝ :=
  Real.arctan (Real.sin slope * Real.sin aspect / jencoQ1 lat slope aspect)

/-- Cosine of solar incidence angle on a tilted surface.
    This is the "solar altitude" at the Jenco-transformed location.

    s0 = cos(φ')·cos(δ)·cos(-ω - λ' + offset) + sin(φ')·sin(δ)

    When s0 > 0: sunlight hits the front of the surface
    When s0 ≤ 0: surface faces away from sun (self-shadowed) -/
noncomputable def cosIncidence
    (slope aspect lat decl timeAngle : ℝ) (timeOffset : ℝ) : ℝ :=
  let sinPhiL := jencoSinLatEquiv lat slope aspect
  let longitL := jencoLongEquiv lat slope aspect
  let cosPhiL := Real.cos (Real.arcsin sinPhiL)
  cosPhiL * Real.cos decl * Real.cos (-timeAngle - longitL + timeOffset) +
  sinPhiL * Real.sin decl

/-! ## Key Properties -/

/-- **Flat surface identity**: When slope = 0, cos_incidence reduces to
    the sine of solar altitude.

    With slope = 0:
    - sin(φ') = -cos(φ)·0·cos(aspect) + sin(φ)·1 = sin(φ)
    - q1 = sin(φ)·0·cos(aspect) + cos(φ)·1 = cos(φ)
    - λ' = atan(0·sin(aspect) / cos(φ)) = 0
    - timeOffset = 0 (aspect doesn't matter when flat)
    - s0 = cos(φ)cos(δ)cos(-ω) + sin(φ)sin(δ) = sinSolarAltitude -/
theorem flat_surface_eq_altitude (lat decl ω : ℝ) :
    cosIncidence 0 0 lat decl ω 0 = sinSolarAltitude lat decl ω := by
  unfold cosIncidence jencoSinLatEquiv jencoLongEquiv jencoQ1 sinSolarAltitude
  -- With slope=0, aspect=0:
  -- sinPhiL = -cos(lat)*0*1 + sin(lat)*1 = sin(lat)
  -- q1 = sin(lat)*0*1 + cos(lat)*1 = cos(lat)
  -- longitL = atan(0*0/cos(lat)) = 0
  -- cosPhiL = cos(arcsin(sin(lat))) = cos(lat) (when lat ∈ [-π/2, π/2])
  -- s0 = cos(lat)*cos(decl)*cos(-ω) + sin(lat)*sin(decl)
  --    = cos(lat)*cos(decl)*cos(ω) + sin(lat)*sin(decl)
  --    = sinSolarAltitude
  sorry -- Requires arcsin(sin(lat))=lat and cos(arcsin(x)) simplification

/-- Cos incidence is bounded by [-1, 1].
    This follows because it equals sin(altitude) at an equivalent location,
    and sin(altitude) = cos(angle between two unit vectors). -/
theorem cosIncidence_bounded (slope aspect lat decl ω offset : ℝ) :
    |cosIncidence slope aspect lat decl ω offset| ≤ 1 := by
  -- The expression has the form cos(A)cos(B)cos(C) + sin(A')sin(B)
  -- where A and A' come from arcsin/cos of the same value.
  -- Proving |result| ≤ 1 requires showing it's a dot product of unit vectors.
  sorry -- Requires careful trig identity proof

/-- When the surface faces away from the sun (s0 ≤ 0), beam radiation is zero.
    This is the shadow self-occlusion condition. -/
theorem beam_zero_when_facing_away (s0 : ℝ) (hs : s0 ≤ 0) :
    max s0 0 = 0 := by
  exact max_eq_right hs

/-! ## Structural Correspondence

The Lean definitions correspond to rsun-core/src/radiation.rs `cos_incidence()`.

**Variable mapping**:
| Rust | Lean |
|------|------|
| `sin_phi_l` | `jencoSinLatEquiv` |
| `q1` | `jencoQ1` |
| `longit_l` | `jencoLongEquiv` |
| `s0` (return value) | `cosIncidence` |

**Implementation note**: The Rust code determines `time_offset` (0 or π)
based on the quadrant of the aspect angle and the sign of q1. In the Lean
model, `timeOffset` is an explicit parameter. The calling code must provide
the correct offset value matching the Rust logic.

**GRASS convention**: Aspect is measured as degrees counterclockwise from East
in the internal GRASS representation. The Rust code converts from the
cartographic convention (degrees clockwise from North) before calling
this function.
-/

end EEMTVerify.Solar
