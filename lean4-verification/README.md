# EEMT Lean 4 Formal Verification

Formal verification of mathematical equations in the [Effective Energy and Mass Transfer (EEMT)](https://github.com/tyson-swetnam/eemt) geospatial modeling toolkit using [Lean 4](https://lean-lang.org/) and [Mathlib](https://leanprover-community.github.io/mathlib4_docs/).

## What This Verifies

~60 mathematical equations spanning 6 domains, implemented across 4 languages (Rust, WGSL, Bash/GRASS, Python):

| Domain | Equations | Status |
|--------|-----------|--------|
| Solar Radiation | 10 | In Progress |
| Climate Integration | 10 | In Progress |
| Topographic Analysis | 15 | Planned |
| EEMT Core | 15 | Planned |
| Biomass/Energetics | 5 | Planned |
| Thermodynamics | 5 | Planned |

## Project Structure

```
EEMTVerify/
  Foundation/     -- Physical constants, trig helpers, real analysis utilities
  Solar/          -- Declination, radiation, horizon angles
  Climate/        -- Magnus formula, PET, Budyko, precipitation
  Topographic/    -- Slope, aspect, TWI, flow direction
  EEMT/           -- NPP, E_BIO, E_PPT, core energy balance
  Biomass/        -- Allometric equations, landscape energy
  Thermodynamic/  -- Exergy, Critical Zone energy
  CrossImpl/      -- Cross-implementation consistency (Rust vs WGSL vs Bash)
  Properties/     -- Global properties (non-negativity, conservation, monotonicity)
  Numerical/      -- Floating-point error analysis
```

## Proof Pattern

Each equation follows this standard structure:

```lean
-- 1. Define the mathematical function over exact reals
noncomputable def myFunction (x : ℝ) : ℝ := ...

-- 2. Prove range bounds
theorem myFunction_bounded (x : ℝ) : a ≤ myFunction x ≤ b := by ...

-- 3. Prove monotonicity / continuity
theorem myFunction_monotone : Monotone myFunction := by ...

-- 4. Document which source files implement this function
/-! Corresponds to:
  - Rust: path/to/file.rs `function_name()`
  - WGSL: path/to/shader.wgsl line N
  - Docs: docs/algorithms/page.md
-/
```

## Verification Categories

| Category | Strategy | Example |
|----------|----------|---------|
| **Analytically derivable** | Full formal proof | Cos incidence angle, TWI definition |
| **Empirical with known bounds** | Structural def + range/monotonicity proofs | Magnus formula, Lieth NPP |
| **Purely empirical** | Structural def + dimensional plausibility | Process rates, allometric eqs |

## Building

```bash
# Install elan (Lean toolchain manager)
curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y

# Build (first time downloads Mathlib — takes several minutes)
cd lean4-verification
lake update
lake build
```

## Tracking `sorry`

Any theorem using `sorry` is incomplete. To find all remaining holes:

```bash
grep -rn "sorry" EEMTVerify/
```

The goal is to minimize `sorry` instances. Some may remain permanently where:
- Mathlib lacks needed lemmas (documented for upstream contribution)
- Numerical evaluation of transcendental functions is needed
- The property is empirical and cannot be formally derived

## References

- Hofierka & Suri (2002): r.sun solar radiation model
- Spencer (1971): Solar declination formula
- Kasten & Young (1989): Optical air mass
- Rasmussen et al. (2011): EEMT framework
- Lieth (1975): Miami NPP model
- Beven & Kirkby (1979): TWI
