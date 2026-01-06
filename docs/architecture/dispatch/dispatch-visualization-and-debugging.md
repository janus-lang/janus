<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Dispatch Visualization and Debugging Tools

This document describes the comprehensive visualization and debugging tools for Janus's multiple dispatch system, providing developers with powerful insights into dispatch behavior, performance characteristics, and debugging capabilities.

## Overview

The dispatch visualization and debugging system consists of two main components:

1. **DispatchVisualizer**: Generates visual representations of dispatch data in multiple formats
2. **DispatchDebugger**: Provides interactive debugging capabilities with breakpoints, watches, and execution tracing

These tools work together with the profiling system to provide a complete development and optimization workflow.

## Architecture

### System Components

```
┌─────────────────────┐    ┌──────────────────────────┐    ┌─────────────────────┐
│  DispatchVisualizer │    │   DispatchDebugger       │    │  Development Tools  │
├─────────────────────┤    ├──────────────────────────┤    ├─────────────────────┤
│ - Multiple formats  │    │ - Interactive debugging  │    │ - IDE integration   │
│ - Performance views │    │ - Breakpoints & watches  │    │ - Command line tools│
│ - Interactive HTML  │    │ - Execution tracing      │    │ - Build system      │
│ - Export capabilities│    │ - Debug reports          │    │ - CI/CD integration │
└─────────────────────┘    └──────────────────────────┘    └─────────────────────┘
```

### Data Flow

1. **Profiling**: Runtime data collection from dispatch calls
2. **Analysis**: Processing profiling data to identify patterns
3. **Visualization**: Generating visual representations in multiple formats
4. **Debugging**: Interactive analysis with breakpoints and watches
5. **Optimization**: Using insights to improve performance

## Visualization System

### Supported Formats

The visualizer generates multiple output formats for different use cases:

#### ASCII Text Visualizations
- **Dispatch Graph**: Text-based overview of call sites with performance indicators
- **Call Hierarchy**: Tree view of dispatch calls organized by signature
- **Performance Heatmap**: Visual representation of performance hotspots

#### SVG Graphics
- **Dispatch Graph**: Scalable vector graphics showing call relationships
- **Decision Tree**: Visual representation of dispatch resolution logic
- **Hot Path Flow**: Flow diagrams of critical execution paths

#### Interactive HTML
- **Comprehensive Dashboard**: Interactive tables and charts
- **Performance Analysis**: Sortable data with filtering capabilities
- **Real-time Updates**: Dynamic content with JavaScript integration

#### DOT/Graphviz
- **Graph Visualization**: Professional graph layouts using Graphviz
- **Customizable Styling**: Flexible visual appearance options
- **Export Capabilities**: High-quality output for documentation

### Usage Examples

#### Basic Visualization Generation

```zig
const std = @import("std");
const DispatchVisualizer = @import("dispatch_visualizer.zig").DispatchVisualizer;

pub fn generateVisualizations(profiler: *DispatchProfiler) !void {
    const allocator = std.heap.page_allocator;

    // Configure visualization options
    const config = DispatchVisualizer.VisualizationConfig{
        .generate_svg = true,
        .generate_html = true,
        .generate_ascii = true,
        .color_scheme = .performance_heatmap,
        .show_performance_data = true,
        .focus_hot_paths = true,
    };

    // Initialize visualizer
    var visualizer = DispatchVisualizer.init(allocator, config);
    defer visualizer.deinit();

    // Generate all visualizations
    try visualizer.generateVisualizations(profiler);

    // Save to files
    try visualizer.saveAllVisualizations("output/visualizations");

    // Get specific visualization types
    const ascii_vizs = visualizer.getVisualizationsByFormat(.ascii);
    defer allocator.free(ascii_vizs);

    for (ascii_vizs) |viz| {
        std.debug.print("Generated: {s}\n", .{viz.title});
        std.debug.print("{s}\n", .{viz.content});
    }
}
```

#### Custom Visualization Configuration

```zig
const config = DispatchVisualizer.VisualizationConfig{
    // Output formats
    .generate_svg = true,
    .generate_html = true,
    .generate_dot = false,
    .generate_ascii = true,

    // Visual styling
    .color_scheme = .high_contrast,
    .layout_algorithm = .hierarchical,
    .show_performance_data = true,
    .show_type_information = false,
    .show_source_locations = true,

    // Filtering options
    .min_call_frequency = 100,
    .max_nodes = 50,
    .focus_hot_paths = true,
};
```

### Visualization Types

#### 1. Dispatch Graph
Shows the relationship between call sites and their performance characteristics.

**ASCII Example:**
```
Dispatch Graph (ASCII)
=====================

🔥 ✓ main.jan:42 (process_data)
    Calls: 10000 (5000.0/sec)
    Dispatch: 2.1μs avg
    Cache: 85.5% hit ratio
    Implementations: 3

  ~ utils.jan:15 (transform)
    Calls: 1500 (750.0/sec)
    Dispatch: 1.2μs avg
    Cache: 67.2% hit ratio
    Implementations: 2
```

#### 2. Call Hierarchy
Organizes dispatch calls by signature in a tree structure.

**ASCII Example:**
```
Call Hierarchy (ASCII)
======================

📋 process_data (12500 total calls)
├── 🔥 main.jan:42 (10000 calls)
├── utils.jan:67 (2000 calls)
└── helper.jan:23 (500 calls)

📋 transform (3000 total calls)
├── 🔥 utils.jan:15 (1500 calls)
└── data.jan:89 (1500 calls)
```

#### 3. Performance Heatmap
Visual representation of performance hotspots with color coding.

**ASCII Example:**
```
Performance Heatmap (ASCII)
===========================

Legend: 🟥 Critical  🟧 High  🟨 Medium  🟩 Low

🟥 main.jan:42 (process_data)
    Score: 15.2 | Calls: 10000 | Time: 2.1μs | Cache: 85%
    ███████████████

🟧 utils.jan:15 (transform)
    Score: 8.7 | Calls: 1500 | Time: 1.2μs | Cache: 67%
    ████████

🟩 helper.jan:23 (validate)
    Score: 1.3 | Calls: 100 | Time: 0.5μs | Cache: 95%
    █
```

## Debugging System

### Interactive Debugging Features

The debugger provides comprehensive debugging capabilities:

- **Breakpoints**: Conditional stopping points in dispatch execution
- **Watch Expressions**: Monitor specific values and metrics
- **Execution Tracing**: Step-by-step dispatch resolution analysis
- **Debug Reports**: Comprehensive analysis of debugging sessions

### Breakpoint Types

#### 1. Call Site Breakpoints
Break when specific source locations are reached.

```zig
const bp_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
    .call_site = .{
        .source_file = "main.jan",
        .line = 42,
        .signature_name = "process_data", // Optional
    },
};

const bp_id = try debugger.addBreakpoint(.call_site, bp_condition);
```

#### 2. Signature Breakpoints
Break when specific function signatures are dispatched.

```zig
const bp_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
    .signature = .{
        .name = "process_data",
        .module = "main", // Optional
    },
};
```

#### 3. Performance Breakpoints
Break when performance thresholds are exceeded.

```zig
// Break on slow dispatch (> 5μs)
const slow_dispatch_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
    .slow_dispatch = .{ .threshold_ns = 5000 },
};

// Break on cache miss
const cache_miss_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
    .cache_miss = .{ .consecutive_misses = 3 },
};

// Break on ambiguous dispatch
const ambiguous_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
    .ambiguous_dispatch = .{ .min_candidates = 2 },
};
```

### Watch Expressions

Monitor specific metrics during execution:

```zig
// Watch call frequency for a signature
const freq_watch = DispatchDebugger.Watch.WatchExpression{
    .call_frequency = .{ .signature_name = "process_data" },
};
const watch_id = try debugger.addWatch("Process Data Frequency", freq_watch);

// Watch dispatch time for a call site
const time_watch = DispatchDebugger.Watch.WatchExpression{
    .dispatch_time = .{ .call_site = call_site },
};

// Watch cache hit ratio
const cache_watch = DispatchDebugger.Watch.WatchExpression{
    .cache_hit_ratio = .{ .signature_name = "process_data" },
};

// Watch implementation count
const impl_watch = DispatchDebugger.Watch.WatchExpression{
    .implementation_count = .{ .signature_name = "process_data" },
};
```

### Execution Tracing

Detailed step-by-step analysis of dispatch resolution:

```zig
pub fn debugDispatch() !void {
    const allocator = std.heap.page_allocator;

    // Configure debugger
    const config = DispatchDebugger.DebugConfig{
        .trace_all_dispatches = false,
        .trace_hot_paths_only = true,
        .break_on_slow_dispatch = true,
        .slow_dispatch_threshold_ns = 5000,
        .verbose_output = true,
        .show_resolution_steps = true,
    };

    var debugger = DispatchDebugger.init(allocator, config);
    defer debugger.deinit();

    // Start debug session
    debugger.startSession();

    // Add breakpoints and watches
    // ... (breakpoint setup)

    // Trace dispatch execution
    const call_site = DispatchProfiler.CallSiteId{
        .source_file = "main.jan",
        .line = 42,
        .column = 10,
        .signature_name = "process_data",
    };

    var frame = try debugger.traceDispatch(call_site, &.{ int_type, string_type });

    // Add resolution steps
    try frame.addResolutionStep(allocator, .signature_lookup, "Looking up signature 'process_data'", "Found 3 candidates");
    try frame.addResolutionStep(allocator, .type_filtering, "Filtering by argument types", "2 candidates remain");
    try frame.addResolutionStep(allocator, .specificity_analysis, "Analyzing specificity", "Selected most specific");

    // Check for breakpoints
    if (debugger.shouldBreak(frame)) {
        std.debug.print("Breakpoint hit at {}:{}\n", .{ frame.call_site.source_file, frame.call_site.line });

        // Interactive debugging session
        try debugger.generateDebugReport(std.io.getStdOut().writer());
    }

    debugger.endSession();
}
```

### Debug Reports

Comprehensive analysis of debugging sessions:

```
Dispatch Debug Report
====================

Session ID: 1640995200000000000
Duration: 1250.5ms
Dispatches traced: 1547
Breakpoints hit: 3
Errors encountered: 0

Execution History (10 frames):
--------------------------------
Frame 1: main.jan:42 (process_data)
  Selected: process_data_impl_1 (2.1μs)

Frame 2: utils.jan:15 (transform)
  Selected: transform_impl_2 (1.2μs)

Frame 3: main.jan:42 (process_data)
  Selected: process_data_impl_1 (2.3μs)
  Warnings: 1

... and 1544 more frames

Breakpoints (2):
------------------
  call_site (enabled): 2 hits
  slow_dispatch (enabled): 1 hits

Watch Expressions (3):
------------------------
  Process Data Frequency: 1547
  Average Dispatch Time: 1.85
  Cache Hit Ratio: 0.82
```

## Integration Examples

### Command Line Tools

```bash
# Generate visualizations from profiling data
janus visualize profile.data --output-dir=viz --format=all

# Interactive debugging session
janus debug --profile=profile.data --break-on-slow=5us

# Generate specific visualization types
janus visualize profile.data --type=heatmap --format=svg

# Export debug report
janus debug-report session.debug --format=html --output=report.html
```

### Build System Integration

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = .{ .path = "src/main.jan" },
    });

    // Enable visualization generation
    if (b.option(bool, "visualize", "Generate dispatch visualizations") orelse false) {
        exe.addBuildOption(bool, "enable_visualization", true);

        const viz_step = b.addSystemCommand(&.{
            "janus", "visualize", "profile.data",
            "--output-dir", "build/visualizations",
            "--format", "html,svg",
        });
        viz_step.step.dependOn(&exe.step);

        const viz_install = b.addInstallDirectory(.{
            .source_dir = "build/visualizations",
            .install_dir = .prefix,
            .install_subdir = "share/visualizations",
        });
        viz_install.step.dependOn(&viz_step.step);

        b.getInstallStep().dependOn(&viz_install.step);
    }

    // Enable debugging support
    if (b.option(bool, "debug-dispatch", "Enable dispatch debugging") orelse false) {
        exe.addBuildOption(bool, "enable_dispatch_debugging", true);
    }
}
```

### IDE Integration

```typescript
// VS Code extension example
import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
    // Register visualization command
    const visualizeCommand = vscode.commands.registerCommand('janus.visualizeDispatch', async () => {
        const panel = vscode.window.createWebviewPanel(
            'janusVisualization',
            'Dispatch Visualization',
            vscode.ViewColumn.One,
            { enableScripts: true }
        );

        // Load HTML visualization
        const htmlContent = await generateVisualization();
        panel.webview.html = htmlContent;
    });

    // Register debug provider
    const debugProvider = new JanusDispatchDebugProvider();
    vscode.debug.registerDebugConfigurationProvider('janus-dispatch', debugProvider);

    context.subscriptions.push(visualizeCommand);
}

async function generateVisualization(): Promise<string> {
    // Execute janus visualize command and return HTML
    const { exec } = require('child_process');
    return new Promise((resolve, reject) => {
        exec('janus visualize profile.data --format=html', (error, stdout) => {
            if (error) reject(error);
            else resolve(stdout);
        });
    });
}
```

## Configuration Options

### Visualization Configuration

```zig
const config = DispatchVisualizer.VisualizationConfig{
    // Output formats
    .generate_svg = true,
    .generate_html = true,
    .generate_dot = false,
    .generate_ascii = true,

    // Visual styling
    .color_scheme = .performance_heatmap,  // .default, .high_contrast, .colorblind_friendly
    .layout_algorithm = .hierarchical,     // .force_directed, .circular, .tree
    .show_performance_data = true,
    .show_type_information = true,
    .show_source_locations = false,

    // Filtering options
    .min_call_frequency = 10,              // Minimum calls to include
    .max_nodes = 100,                      // Maximum nodes to display
    .focus_hot_paths = true,               // Emphasize hot paths
};
```

### Debug Configuration

```zig
const config = DispatchDebugger.DebugConfig{
    // Tracing options
    .trace_all_dispatches = false,
    .trace_hot_paths_only = true,
    .trace_failed_dispatches = true,
    .trace_ambiguous_dispatches = true,

    // Breakpoint options
    .break_on_slow_dispatch = true,
    .slow_dispatch_threshold_ns = 10000,   // 10μs
    .break_on_cache_miss = false,
    .break_on_ambiguity = true,

    // Output options
    .verbose_output = false,
    .show_resolution_steps = true,
    .show_type_information = true,
    .show_performance_data = true,

    // Analysis options
    .enable_profiling = true,
    .enable_visualization = true,
    .auto_generate_reports = false,
};
```

## Performance Considerations

### Visualization Performance

- **ASCII Generation**: ~1ms per 100 call sites
- **SVG Generation**: ~5ms per 100 call sites
- **HTML Generation**: ~10ms per 100 call sites
- **Memory Usage**: ~50KB per 1000 call sites

### Debug Performance Impact

- **Disabled**: 0% overhead
- **Breakpoints only**: <1% overhead
- **Full tracing**: 5-15% overhead
- **Memory Usage**: ~1KB per traced dispatch

### Optimization Tips

1. **Use filtering**: Limit visualizations to relevant data
2. **Selective tracing**: Only trace hot paths or specific signatures
3. **Batch generation**: Generate multiple visualizations together
4. **Async processing**: Generate visualizations in background

## Best Practices

### Visualization Workflow

1. **Start with ASCII**: Quick overview of dispatch behavior
2. **Use HTML for analysis**: Interactive exploration of data
3. **Generate SVG for documentation**: High-quality graphics for reports
4. **Export DOT for complex graphs**: Professional layouts with Graphviz

### Debugging Workflow

1. **Profile first**: Identify performance issues with profiling
2. **Set targeted breakpoints**: Focus on specific problems
3. **Use watch expressions**: Monitor key metrics
4. **Analyze execution traces**: Understand dispatch resolution
5. **Generate reports**: Document findings and solutions

### Development Integration

1. **Continuous visualization**: Generate visualizations in CI/CD
2. **Performance regression detection**: Compare visualizations over time
3. **Code review integration**: Include visualizations in reviews
4. **Documentation**: Use visualizations in technical documentation

## Troubleshooting

### Common Issues

#### Visualization Generation Fails
**Symptoms**: Empty or corrupted visualizations
**Causes**: Insufficient profiling data, memory issues
**Solutions**: Increase profiling duration, check memory limits

#### Debug Breakpoints Not Triggering
**Symptoms**: Breakpoints never hit despite matching conditions
**Causes**: Tracing disabled, incorrect conditions
**Solutions**: Enable tracing, verify breakpoint conditions

#### Performance Impact Too High
**Symptoms**: Significant slowdown with debugging enabled
**Causes**: Full tracing enabled, too many breakpoints
**Solutions**: Use selective tracing, reduce breakpoint count

#### Large Memory Usage
**Symptoms**: High memory consumption during visualization
**Causes**: Large datasets, memory leaks
**Solutions**: Use filtering, check for memory leaks

### Debugging Tips

Enable verbose output:
```bash
export JANUS_DEBUG_VERBOSE=1
janus debug --profile=profile.data
```

Check visualization generation:
```zig
const stats = visualizer.getVisualizations();
for (stats) |viz| {
    std.debug.print("Generated: {s} ({} bytes)\n", .{ viz.title, viz.content.len });
}
```

Validate debug session:
```zig
if (debugger.current_session) |session| {
    std.debug.print("Session active: {} dispatches traced\n", .{session.dispatches_traced});
}
```

## Future Enhancements

### Planned Features

- **Real-time visualization**: Live updates during execution
- **3D visualizations**: Complex relationship visualization
- **Machine learning insights**: AI-powered optimization suggestions
- **Collaborative debugging**: Multi-developer debugging sessions

### Research Areas

- **VR/AR visualization**: Immersive dispatch analysis
- **Predictive debugging**: Anticipate issues before they occur
- **Cross-language visualization**: Multi-language dispatch analysis
- **Performance prediction**: Model performance impact of changes

## Conclusion

The dispatch visualization and debugging tools provide comprehensive insights into Janus's multiple dispatch system, enabling developers to:

- **Understand dispatch behavior** through clear visualizations
- **Identify performance bottlenecks** with detailed analysis
- **Debug complex issues** with interactive tools
- **Optimize performance** based on data-driven insights

These tools are essential for developing high-performance Janus applications and understanding the behavior of complex dispatch systems.

For more information, see:
- [Dispatch Profiling and Optimization Guide](dispatch-profiling-and-optimization.md)
- [Multiple Dispatch System Documentation](multiple-dispatch-guide.md)
- [Performance Optimization Guide](dispatch-performance-guide.md)
