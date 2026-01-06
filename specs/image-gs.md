<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





<!-- `docs/spec/SPEC-image-gs.md` -->

# SPEC: Image-GS — Content-Adaptive Image Representation

**Status:** Draft v0.1.0
 **Author:** Self Sovereign Society Foundation
 **Date:** 2025-09-15
 **Profiles:** `:core` (decode), `:service` (compression/LOD), `:sovereign` (GPU training)
 **References:** [Image-GS: Content-Adaptive Image Representation via 2D Gaussians (NYU-ICL 2024)](https://github.com/NYU-ICL/image-gs)

------

## 0. Purpose

Provide a **content-adaptive, Gaussian-atom–based image representation** for Janus, suitable for:

- Texture compression
- Semantic/feature-aware compression
- Progressive image restoration
- Differentiable graphics workflows

The design must preserve **Syntactic Honesty**, expose **costs explicitly**, and integrate with **profiles** for progressive adoption.

------

## 1. Core Model

### 1.1 Gaussian Atom

```janus
type Gauss2D = {
  mean: (f32, f32),              // position in normalized [0,1]²
  covar: [[f32; 2]; 2],          // anisotropic covariance matrix
  color: (f32, f32, f32, f32),   // RGBA, premultiplied alpha
  weight: f32                    // contribution factor
}
```

Constraints:

- `covar` must be symmetric positive semi-definite → E2901_INVALID_COVAR if violated
- `weight >= 0` → negative = E2902_INVALID_WEIGHT
- `color` channels ∈ [0,1] unless `flags.allow_hdr`

### 1.2 Image-GS Container

```janus
type ImageGS = {
  atoms: []Gauss2D,              // sorted by weight (optional)
  width: u32,
  height: u32,
  lod_levels: []LODInfo,         // progressive hierarchy
}
type LODInfo = { error: f32, atom_count: usize }
```

------

## 2. Operations

### 2.1 Decoding

```janus
func gs.decode(gs: ImageGS, x: u32, y: u32) -> Color
```

- Cost: ~0.3K MACs per pixel (exposed in docs/diagnostics)
- Deterministic by default; GPU acceleration available under `:sovereign`

### 2.2 Loading & Saving

```janus
func gs.load(path: string, cap: CapFsRead, alloc: Alloc) -> ImageGS!Error
func gs.save(gs: ImageGS, path: string, cap: CapFsWrite) -> void!Error
```

- Uses binary format: header + atom list
- Explicit allocator sovereignty

### 2.3 Optimization & Compression

```janus
func gs.optimize(img: Raster, params: GSParams, cap: CapCuda?) -> ImageGS!Error
```

- `GSParams` includes atom budget, error thresholds, LOD steps
- Requires `CapCuda` or `CapForeignPython` in `:sovereign`
- Error-guided refinement, progressive optimization
- Returns E2903_OPTIMIZATION_FAILED if budget/params unsatisfiable

### 2.4 Progressive Refinement

```janus
func gs.refine(gs: ImageGS, budget: usize) -> ImageGS!Error
```

- Adds atoms guided by residual error
- Updates `lod_levels`

------

## 3. Profile Mapping

- **`:core`**:
  - `load`, `save`, `decode` only
  - CPU-only rasterization
  - No optimization or training
- **`:service`**:
  - Add `refine` for progressive decoding
  - Basic compression from raster inputs (CPU fallback)
- **`:sovereign`**:
  - Full differentiable optimization (`optimize`)
  - GPU/CUDA/foreign interop enabled
  - Semantic-aware compression allowed

------

## 4. Interop

- **Buffer Protocol**:
  - `ImageGS` atoms exposed as `Buffer` of `Gauss2D` (see `SPEC-buffer.md`)
  - Zero-copy Python bridge via PEP 3118 when possible
- **Foreign Training**:
  - Honest boundary: `foreign.python` blocks may run reference PyTorch CUDA optimization
  - Explicit capabilities: `CapForeignPython`, `CapCuda`

------

## 5. Error Codes (E29xx)

- **E2901_INVALID_COVAR** — covariance not positive semi-definite
- **E2902_INVALID_WEIGHT** — negative or NaN weight
- **E2903_OPTIMIZATION_FAILED** — optimization could not converge
- **E2905_ATOM_BUDGET_EXCEEDED** — refine exceeded requested budget
- **E2907_DEVICE_UNSUPPORTED** — GPU requested but not available in current profile

------

## 6. Testing

- **Decode Fidelity**: PSNR/SSIM against original raster for increasing atom counts
- **LOD Hierarchy**: Verify monotonic error decrease with refinement
- **Interop Tests**: Round-trip NumPy/PyTorch export/import
- **Determinism**: Identical decode outputs under `--deterministic`

------

## 7. Strategic Fit

- Aligns with **Janus Graphics Roadmap**: efficient, explicit primitives for textures and compression.
- Provides **Trojan Horse adoption vector** into ML + graphics communities.
- Demonstrates **profiles ladder**: minimal decode → compression → full differentiable optimization.

------

✅ **Doctrines upheld:**

- **Syntactic Honesty:** Gaussian atoms are explicit structs, no hidden neural nets.
- **Mechanism over Policy:** Expose Gaussians as a mechanism; don’t hardcode policies.
- **Revealed Complexity:** Costs (MACs per pixel, memory) are visible and documented.

------
