# Sovereign Numerics

> "Math does not bow to kings."

Janus treats mathematics as a first-class sovereign citizen. We prioritize precision and predictability over convenience.

## Floating Point (f64)

Janus uses 64-bit IEEE 754 floating point numbers by default.
```janus
let pi: f64 = 3.14159265359;
```

## VectorF64

For heavy lifting, we provide `VectorF64`, a dynamic array handle managed by the runtime (Sovereign Heap).

### Usage

```janus
// Create a vector with capacity 10
let v: ptr = vector_create(10);

// Push values
vector_push(v, 1.618);
vector_push(v, 2.718);

// Access
let phi: f64 = vector_get(v, 0);

// Cleanup (Deterministic)
defer vector_free(v);
```

## Tensor Operations (NPU)
*Planned for v0.3.0*
