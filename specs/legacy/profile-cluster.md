<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — :cluster Profile (SPEC-P-CLUSTER)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-profile-elixir v0.3.0

## 1. Profile Purpose

The `:cluster` profile specializes Janus for **distributed systems and fault-tolerant cloud logic**. It introduces the Actor Model, Virtual Grains, and location-transparent messaging.

## 2. Capability Set ⧉

[PCLUST:2.1.1] The `:cluster` profile SHALL inherit all capabilities of the `:service` profile.

[PCLUST:2.1.2] **Actor Model:** The `:cluster` profile SHALL support the `actor` keyword, sequential message processing, and internal state isolation.

[PCLUST:2.1.3] **Virtual Grains:** In the `:cluster` profile, actors MAY be managed as Grains, providing automatic scaling and persistence across a cluster fabric.

## 3. Execution Mode: Fluid ⟁

[PCLUST:3.1.1] The `:cluster` profile SHALL default to **Fluid Mode** (`:cluster!`), emphasizing responsiveness and dynamic topology management, but MAY be compiled in **Strict Mode** for predictable high-performance nodes.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge
