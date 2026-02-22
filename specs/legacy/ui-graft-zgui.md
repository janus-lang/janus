<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — UI Graft (zgui Integration)

**Version:** 0.1.0-draft
**Status:** DRAFT — UI grafting mechanism for interactive tooling
**Last Updated:** 2025-10-14
**Authority:** Language Architecture Team
Please have a look at the RFC for the full specification: ./docs/specs/RFC-ui-graft-zgui-integration.md

---

## Executive Summary

This specification defines the grafting mechanism for integrating zgui (Zig ImGui wrapper) to provide immediate-mode UI capabilities for Janus tooling. The graft enables interactive windows, widgets, and visualizations while maintaining doctrinal purity through explicit effects, capability security, and cost revelation.

**Core Thesis:** UI is not magic—every frame poll, widget render, and event loop must be explicit, capability-gated, and cost-revealed. zgui's immediate-mode paradigm aligns with Syntactic Honesty by making redraw costs visible and controllable.

---

## 🎯 Strategic Positioning

### zgui's Strengths (Target Integration)
- **Immediate Mode UI:** No retained state, explicit redraws per frame
- **Zig Native:** Zero-cost FFI with Zig ecosystem
- **ImGui Foundation:** Battle-tested widget set with GPU acceleration
- **Minimal Dependencies:** SDL2/OpenGL only, no heavy frameworks

### Janus's Control Mechanisms
- **Capability Security:** `CapUi*` tokens gate all UI operations
- **Effect Tracking:** Frame budgets and redraw costs in function signatures
- **ASTDB Integration:** Live UI synchronization with semantic database
- **Profile Agnostic:** UI graft works across all profiles without drift

### Integration Philosophy
**"UI grafting is contained anarchy"** — zgui provides widgets, Janus enforces discipline through capabilities and effects. No hidden redraws, no ambient UI authority, no surprise allocations.

---

## 📋 Requirements (EARS/BDD Format)

### Requirement 1: Profile-Agnostic Grafting

**Event:** Janus compiles under any profile (:core, :service, :cluster, :sovereign, :compute)  
**Stakeholders:** Platform maintainers, toolchain integrators  
**Acceptance Criteria:**

1. **WHEN** Janus compiles under any profile **THEN** the system SHALL include zgui bindings without semantic drift, using `repr(c)` for FFI compatibility
2. **WHEN** runtime initializes UI **THEN** the system SHALL expose core zgui functions with explicit effects in signatures:
   - `zgui.begin_window(name: str, flags: u32) -> bool !UiEffect`
   - `zgui.end_window() -> void !UiEffect`
   - `zgui.button(label: str) -> bool !UiEffect`
   - `zgui.text(fmt: str, args: ...) -> void !UiEffect`
   - `zgui.input_text(label: str, buf: []u8, flags: u32) -> bool !UiEffect`
3. **IF** grafting fails (missing symbols, version mismatch) **THEN** the system SHALL return `error.GraftFail` with diagnostic guidance

**Given** a Janus installation with zgui available  
**When** compiling code that imports `std.graft.ui.zgui`  
**Then** the graft SHALL resolve without profile conflicts

### Requirement 2: Capability-Secure UI Actions

**Event:** UI operations require explicit authorization  
**Stakeholders:** Security architects, capability stewards  
**Acceptance Criteria:**

1. **IF** code calls UI functions without `CapUi` token **THEN** the system SHALL reject with `error.CapDenyUi`, logging "UI access requires explicit grant via Context"
2. **WHEN** capability token issued **THEN** the system SHALL embed granular permissions:
   - `CapUiDisplay` for read-only widgets (text, labels)
   - `CapUiInteract` for input widgets (buttons, text fields)
   - `CapUiWindow` for window management (create, destroy, resize)
3. **WHEN** token revoked **THEN** the system SHALL invalidate pending UI calls, freeing resources without leaks (arena reset)

**Given** a Janus program with UI capabilities  
**When** attempting UI operations  
**Then** all actions SHALL require explicit capability grants

### Requirement 3: ASTDB-Synchronized Widgets

**Event:** UI widgets need live synchronization with semantic database  
**Stakeholders:** Tooling engineers, LSP integrators  
**Acceptance Criteria:**

1. **WHEN** ASTDB updates subscribed entity **THEN** the system SHALL notify UI widgets within 16ms frame budget, queueing if exceeded
2. **IF** widget subscribes to ASTDB query **THEN** the system SHALL return data with explicit lifetime (borrowed slice), desugaring to effects in signature
3. **IF** updates exceed frame budget **THEN** the system SHALL coalesce with backpressure, logging "dropped 5 events; dial frame_budget=32ms"

**Given** an active UI session with ASTDB subscriptions  
**When** semantic data changes  
**Then** UI SHALL update within frame budget with explicit cost tracking

### Requirement 4: Future Tooling Support

**Event:** UI needs to support LSP and debugger integration  
**Stakeholders:** IDE developers, debugger maintainers  
**Acceptance Criteria:**

1. **WHEN** new native UI components added **THEN** the system SHALL compose atop zgui without interface changes, using event hooks for extensibility
2. **IF** module registers UI elements (LSP panels, debugger views) **THEN** the system SHALL provide layout/event/teardown lifecycle with cost annotations
3. **WHEN** run headless **THEN** the system SHALL simulate UI interfaces deterministically, outputting JSON for testing and CI

**Given** a Janus development environment  
**When** integrating with LSP or debugger  
**Then** UI SHALL provide native integration points

### Requirement 5: UI Lifecycle Management

**Event:** UI contexts need explicit initialization and teardown  
**Stakeholders:** Resource managers, memory stewards  
**Acceptance Criteria:**

1. **WHEN** initializing UI context **THEN** the system SHALL allocate arena-scoped resources, requiring `CapUiInit` token
2. **IF** context teardown called **THEN** the system SHALL free all widgets without dangling references, logging resource reclamation details
3. **WHEN** profile switches mid-session **THEN** the system SHALL preserve UI state if compatible, or error with migration guidance

**Given** a Janus application with UI components  
**When** managing UI lifecycle  
**Then** all resources SHALL be explicitly managed with leak prevention

### Requirement 6: Performance Bounds

**Event:** UI rendering needs bounded latency for responsive tooling  
**Stakeholders:** Performance engineers, real-time system developers  
**Acceptance Criteria:**

1. **WHEN** rendering frame **THEN** the system SHALL complete under 16ms P99, exposing metrics via `janus query ui-perf`
2. **IF** redraw exceeds budget **THEN** the system SHALL drop non-critical widgets with graceful degradation, logging "dropped text widget; dial perf=high"
3. **WHEN** in `:compute` profile **THEN** the system SHALL offload renders to GPU if `CapGpu` granted, benchmarking vs CPU baseline

**Given** an interactive UI session  
**When** rendering frames  
**Then** performance SHALL be bounded and measurable

### Requirement 7: Interop & Migration

**Event:** UI needs to integrate with existing tools and migrate from other frameworks  
**Stakeholders:** Migration engineers, ecosystem integrators  
**Acceptance Criteria:**

1. **WHEN** grafting external ImGui **THEN** the system SHALL map zgui calls 1:1 with zero-copy buffers where safe
2. **IF** external tool integrates **THEN** the system SHALL support event callbacks with effects, desugaring to Janus signatures
3. **WHEN** migrating from other UI frameworks **THEN** the system SHALL provide bridge stubs with capability mapping guides

**Given** existing tools with UI requirements  
**When** integrating with Janus UI graft  
**Then** migration SHALL be supported with clear guidance

---

## 💰 Cost Matrices (Revealed Complexity)

### Requirement 1: Profile-Agnostic Grafting

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **zgui Bindings** | Interactive windows | FFI call overhead (50-200ns) | `--graft=zgui` |
| **Profile Compile** | No semantic drift | Extra dependency size (2MB) | `--profile=all` |
| **Cross-Profile Sync** | Consistent UI | Profile gate checks (10-50ns) | `--sync=explicit` |

### Requirement 2: Capability Security

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **Token Validation** | Zero-trust UI | Cap check overhead (20-100ns) | `--cap=fast-path` |
| **Granular Permissions** | Least-privilege UI | Token threading complexity | `--perm=granular` |
| **Audit Logging** | Security traceability | Log storage overhead (1KB/frame) | `--audit=minimal` |

### Requirement 3: ASTDB Synchronization

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **Live Updates** | Real-time tooling | Query latency (2-5ms) | `--budget=16ms` |
| **Subscription Mgmt** | Efficient updates | Memory for subscriptions (4KB/base) | `--sub=eager` |
| **Backpressure** | Frame stability | Coalescing complexity | `--pressure=drop` |

### Requirement 4: Tooling Support

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **LSP Integration** | Rich IDE experience | Event routing overhead (1-10ms) | `--lsp=async` |
| **Composition Hooks** | Extensible UI | Hook dispatch cost (50-200ns) | `--hooks=minimal` |
| **Headless Mode** | CI/Test support | Simulation overhead (2-5ms/frame) | `--headless=fast` |

### Requirement 5: Lifecycle Management

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **Arena Scoping** | Leak prevention | Arena setup/teardown (100-500ns) | `--arena=eager` |
| **State Preservation** | Session continuity | Serialization overhead (1-10ms) | `--state=minimal` |
| **Profile Migration** | Seamless upgrades | Compatibility checks (50-200ns) | `--migrate=strict` |

### Requirement 6: Performance Bounds

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **16ms Frame Budget** | Responsive UI | Dropping complexity | `--budget=16ms` |
| **GPU Offload** | Hardware acceleration | GPU sync overhead (1-5ms) | `--gpu=auto` |
| **Performance Monitoring** | Observable metrics | Query overhead (100-500ns) | `--metrics=minimal` |

### Requirement 7: Interop & Migration

| Feature | Benefit | Cost | Mitigation Dial |
|---------|---------|------|-----------------|
| **Zero-Copy Bridges** | Efficient data exchange | Buffer management complexity | `--copy=zero` |
| **FFI Compatibility** | External tool integration | ABI mismatch handling (50-200ns) | `--ffi=strict` |
| **Migration Stubs** | Smooth transition | Stub maintenance overhead | `--migrate=auto` |

---

## 🔧 Implementation Architecture

### Grafting Mechanism

```janus
// Core UI grafting module
module std.graft.ui {
    // zgui FFI bindings with explicit effects
    graft "zgui" {
        func begin_window(name: str, flags: u32) -> bool !UiEffect
        func end_window() -> void !UiEffect
        func button(label: str) -> bool !UiEffect
        func text(fmt: str, args: ...) -> void !UiEffect
        func input_text(label: str, buf: []u8, flags: u32) -> bool !UiEffect

        // Advanced widgets
        func slider_float(label: str, value: &f32, min: f32, max: f32) -> bool !UiEffect
        func checkbox(label: str, value: &bool) -> bool !UiEffect
        func combo_box(label: str, items: [str], current: &usize) -> bool !UiEffect
    }
}
```

### Capability Integration

```janus
// UI capability definitions
type UiCapabilities = {
    display: CapUiDisplay,      // Read-only widgets
    interact: CapUiInteract,    // Input widgets
    window: CapUiWindow,        // Window management
    gpu: CapGpu,               // GPU acceleration
}

// Usage in application
func create_ui_dashboard(data: ScientificData, caps: UiCapabilities) -> void !UiError do
    with caps do
        let window_open = zgui.begin_window("Scientific Dashboard")
        if window_open do
            // Display widgets
            with caps.display do
                zgui.text("Dataset: {}", data.name)
                zgui.text("Size: {} GB", data.size_gb)
            end

            // Interactive widgets
            with caps.interact do
                if zgui.button("Export Data") do
                    export_data(data)
                end

                var threshold: f64 = 0.5
                zgui.slider_float("Threshold", &threshold, 0.0, 1.0)
            end

            zgui.end_window()
        end
    end
end
```

### ASTDB Synchronization

```janus
// Live UI synchronization with semantic database
func setup_ui_subscriptions(db: ASTDB, caps: UiCapabilities) -> void !DbError do
    with caps do
        // Subscribe to function definitions
        db.subscribe("func where effects.contains('io.fs.write')") { |results|
            update_file_io_widgets(results)
        }

        // Subscribe to type definitions
        db.subscribe("type where size > 1000") { |results|
            update_type_size_display(results)
        }

        // Subscribe to performance metrics
        db.subscribe("perf where latency > 10ms") { |results|
            update_performance_gauge(results)
        }
    end
end
```

---

## 🎮 Usage Examples

### Basic Interactive Window

```janus
func create_demo_window(caps: UiCapabilities) -> void !UiError do
    with caps do
        let open = zgui.begin_window("Janus Demo")
        if open do
            zgui.text("Welcome to Janus UI!")
            zgui.text("Frame budget: 16ms")
            zgui.text("Capabilities: active")

            if zgui.button("Click me!") do
                log.info("Button clicked!")
            end

            var buffer: [256]u8 = [0; 256]
            if zgui.input_text("Enter text", &buffer, 0) do
                log.info("Input: {}", buffer)
            end

            zgui.end_window()
        end
    end
end
```

### Scientific Visualization

```janus
func render_scientific_plot(data: ND[f64], caps: UiCapabilities) -> void !UiError do
    with caps do
        let plot_open = zgui.begin_window("Scientific Plot", zgui.WindowFlags.NoCollapse)
        if plot_open do
            // Plot controls
            var show_grid = true
            zgui.checkbox("Show Grid", &show_grid)

            var line_width: f32 = 2.0
            zgui.slider_float("Line Width", &line_width, 0.5, 5.0)

            // Plot area
            zgui.text("Data points: {}", data.shape[0])

            // Simple line plot visualization
            for i in 0..data.shape[0]-1 do
                let x1 = i as f32 / data.shape[0] as f32 * 300.0
                let y1 = (1.0 - data[i]) * 200.0
                let x2 = (i+1) as f32 / data.shape[0] as f32 * 300.0
                let y2 = (1.0 - data[i+1]) * 200.0

                // Draw line segment (simplified)
                zgui.text("Line: ({:.1}, {:.1}) -> ({:.1}, {:.1})", x1, y1, x2, y2)
            end

            zgui.end_window()
        end
    end
end
```

### LSP Integration Example

```janus
func create_lsp_panel(diagnostics: [Diagnostic], caps: UiCapabilities) -> void !UiError do
    with caps do
        let panel_open = zgui.begin_window("LSP Diagnostics")
        if panel_open do
            for diag in diagnostics do
                match diag.severity {
                    .Error => zgui.text_colored("ERROR: {}", diag.message, color: Red)
                    .Warning => zgui.text_colored("WARN: {}", diag.message, color: Yellow)
                    .Info => zgui.text_colored("INFO: {}", diag.message, color: Blue)
                }

                if zgui.button("Fix: {}", diag.suggestion) do
                    apply_lsp_fix(diag)
                end
            end

            zgui.end_window()
        end
    end
end
```

---

## 🔒 Security Model

### Capability Hierarchy

```
CapUi (root)
├── CapUiDisplay (read-only widgets)
├── CapUiInteract (input widgets)
├── CapUiWindow (window management)
└── CapUiGpu (GPU acceleration)
```

### Effect Signatures

All UI functions declare explicit effects:
```janus
func zgui.begin_window(name: str, flags: u32) -> bool !UiEffect[ui.display + alloc.small]
func zgui.button(label: str) -> bool !UiEffect[ui.interact + alloc.tiny]
func zgui.input_text(label: str, buf: []u8, flags: u32) -> bool !UiEffect[ui.interact + io.stdin]
```

### Arena-Based Resource Management

```janus
func run_ui_session(ctx: Context) -> void !UiError do
    let ui_arena = ArenaAllocator.init(ctx.alloc)
    defer ui_arena.deinit()

    with ctx.ui_capabilities do
        create_main_window(ui_arena.allocator())
        // All UI resources automatically freed on scope exit
    end
end
```

---

## 📊 Performance Characteristics

### Frame Budget Enforcement

```janus
// Explicit frame timing with budget enforcement
func render_ui_frame(data: UiData, caps: UiCapabilities) -> FrameResult !UiError do
    let frame_start = clock.now()
    let budget_remaining = 16ms - (clock.now() - frame_start)

    with caps do
        let window_result = zgui.begin_window("Performance Monitor")

        if budget_remaining < 2ms do
            // Low budget - render only critical widgets
            zgui.text("Frame budget low: {}", budget_remaining)
            return FrameResult.BudgetExceeded(budget_remaining)
        end

        // Full rendering with budget tracking
        render_data_visualization(data, budget_remaining)
        render_controls(data, budget_remaining)

        zgui.end_window()
    end

    let frame_time = clock.now() - frame_start
    return FrameResult.Completed(frame_time)
end
```

### Cost Monitoring

```janus
// Real-time cost tracking
func monitor_ui_costs() -> CostReport !PerfError do
    let query = "
        func where effects.contains('ui')
        | group_by func_name
        | aggregate avg_latency, total_calls, memory_allocated
    "

    let results = try astdb.query(query)
    return format_cost_report(results)
end
```

---

## 🧪 Testing Strategy

### Unit Tests (Widget Functionality)

```janus
test "zgui button interaction" do
    let ctx = create_test_ui_context()
    defer ctx.deinit()

    with ctx.caps do
        let open = zgui.begin_window("Test Window")
        assert open

        let clicked = zgui.button("Test Button")
        assert !clicked  // No interaction in unit test

        zgui.end_window()
    end
end
```

### Integration Tests (ASTDB Sync)

```janus
test "ui synchronization with semantic changes" do
    let db = create_test_astdb()
    let ui = create_test_ui()

    // Subscribe UI to function changes
    db.subscribe("func where name = 'test_func'") { |results|
        ui.update_function_display(results)
    }

    // Modify function and verify UI updates
    modify_test_function(db)
    assert ui.received_update()
end
```

### Performance Tests (Frame Budget)

```janus
test "ui frame budget compliance" do
    let ui = create_heavy_ui_scene()

    for i in 0..100 do
        let frame_time = measure_frame_time(ui.render_frame)
        assert frame_time < 16ms, "Frame exceeded budget: {}", frame_time
    end
end
```

---

## 🎨 Doctrinal Alignment

### Syntactic Honesty
- **Explicit Frame Polls:** Every redraw declares `!UiEffect` in signature
- **Visible Costs:** Frame budgets and latency exposed in type system
- **No Hidden State:** Immediate-mode UI makes all state explicit

### Progressive Disclosure
- **Profile Agnostic:** UI graft works in `:core` (basic widgets) to `:sovereign` (advanced tooling)
- **Gradual Complexity:** Start with simple windows, add interactive widgets as needed
- **Feature Gates:** Advanced UI features gated by capability tokens

### Mechanism Over Policy
- **Composable Widgets:** Users combine primitives (buttons, text, inputs) freely
- **Dials for Performance:** `--budget=16ms`, `--backend=opengl` for customization
- **No Prescribed Patterns:** Users build dashboards, debuggers, or visualizations as needed

### Revealed Complexity
- **Cost Matrices:** All performance trade-offs documented and measurable
- **Effect Tracking:** UI operations declare their computational costs
- **Budget Enforcement:** Frame budgets prevent surprise performance degradation

---

## 📚 References

- **[zgui Documentation](https://github.com/zig-gamedev/zgui)** - Target grafting compatibility
- **[ImGui Manual](https://github.com/ocornut/imgui)** - Widget behavior reference
- **[Janus Grafting Doctrine](./docs/specs/SPEC-foreign.md)** - Foreign code integration principles
- **[UTCP Protocol](./docs/specs/SPEC-utcp-integration.md)** - Tooling capability declarations

---

**Specification Status:** DRAFT

This specification provides the complete requirements for grafting zgui to enable UI capabilities in Janus while maintaining doctrinal purity. The grafting mechanism is explicitly contained, capability-secured, and cost-revealed.

**Next Action:** Implement `std.graft.ui.zgui` with core widget bindings and capability integration.
