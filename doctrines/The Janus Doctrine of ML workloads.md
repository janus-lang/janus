<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





The Janus language must not just *support* machine learning workloads — it must be **engineered around them**. That means recognizing the **new physics** of computing: 
> Data is tensors, programs are graphs, execution is parallel, memory is shared between compute + model weights, and correctness is statistical rather than binary.

Here’s how we make Janus **native to ML hardware** (NPUs, TPUs, GPUs, ASICs):

## 🧠 1. Core Principle: **Tensor as a First-Class Citizen**

* **Primitive Types**: `tensor<f32, 2x2>` is as first-class as `i32` or `string`.
* **Compile-Time Shapes**: Dimensions and ranks must be tracked at compile time for safety (`tensor<f16, 128x128>`).
* **Lazy by Default**: Tensor operations should compile to **graphs**, not eager loops, allowing full hardware optimization.
* **Multi-Dispatch**: A function like `matmul` dispatches to CPU, GPU, or NPU kernels transparently.

👉 This means the Janus core must embed **shape algebra in the type system** — similar to dependent typing, but pragmatic.

---

## ⚡ 2. Execution Model: **Graph-Oriented Runtime**

* Programs are **dual representations**:

  * **Imperative control flow** for general logic.
  * **Dataflow graphs** for tensor compute.
* Compiler extracts tensor ops into a **graph IR**, schedules them across NPUs, and fuses them where possible.
* Janus must **own its graph IR**, not borrow TensorFlow or Torch. Something like MLIR, but stripped to Janus principles (no policy, pure mechanism).

👉 This IR is the bridge: one side is the language, the other side is the silicon.

---

## 🔒 3. Memory as a Shared Battlefield

* **Unified Memory Model**: CPU, GPU, NPU share tensors without explicit copies.
* **Pinned + Zero-Copy Buffers**: Default for tensor data.
* **Explicit Lifetime Control**: Programmers can control retention of activations for memory-critical workloads.
* **Arena Allocators for Models**: Entire models can be allocated in a dedicated capsule arena.

👉 Memory becomes a *weapon of scale*. Janus must make it explicit and predictable, not leave it to runtime garbage.

---

## 🛠️ 4. Compilation Pipeline: **Dual Backends**

* **Standard Backend**: LLVM/Zig IR for general systems code.
* **Tensor Backend**: Graph IR → ONNX / XLA / custom kernel fusion → NPU runtime.
* Every program can compile both **scalar code** and **tensor graphs** in one pipeline.
* Export tensors in UTCP manuals so agents can call models directly.

👉 This ensures Janus is **systems language + ML language** in one body.

---

## 🏗️ 5. Concurrency Model: **Streams + Capsules**

* Replace threads with **compute streams**: CPU stream, GPU stream, NPU stream.
* Streams synchronize via explicit events, not locks.
* Capsules can bind to a specific compute stream.
* Iterators (already built) must support streaming tensors: `tensor.iterator().map(f).batch(128)`.

👉 No hidden concurrency. All compute is stream-aware.

---

## 🧬 6. Security Doctrine: **Verifiable Models**

* Every tensor capsule must carry a **BLAKE3 hash of weights**.
* UTCP registry announces model metadata + hash → agents verify integrity.
* Signed leases extend to **models** as well as containers.
* Capabilities apply to *execution* of models (e.g. who can run inference).

👉 This ties the NPU-first design into the registry/sovereignty doctrine.

---

## 🌍 7. Developer Experience: **NPU as Default**

* Writing a matrix multiply in Janus should default to NPU if available.
* Debug mode: fall back to CPU with same semantics.
* Profiling tools baked in: show tensor graph, kernel fusion, memory usage.
* UTCP manuals can describe models so agents discover and invoke them.

👉 No framework hell. No PyTorch vs TensorFlow. The **language is the framework**.

---

## ⚔️ Strategic Advantage

Most languages are “systems-first” (C, Zig, Rust) or “ML-second” (Python → PyTorch).
Janus flips it: **ML-native systems language**.

That means:

* Write a kernel driver and a transformer model in the same language.
* Compile systems code and tensor graphs in one pipeline.
* Expose everything over UTCP → sovereign registries of code + models.
