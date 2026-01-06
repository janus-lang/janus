<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# **Grafting Guide: Foreign Code Integration in Janus** 🚀

*Injecting the world's code into your AI-first applications*

---

## **What is Grafting?**

**Grafting** is Janus' approach to foreign code integration. Unlike traditional "bindings" or "wrappers", grafting allows you to **seamlessly inject** foreign libraries and runtimes directly into your Janus code while maintaining:

- ⚡ **Zero-cost abstraction** - No runtime overhead
- 🔐 **Cryptographic security** - Capability-based access control
- 🤖 **AI tooling integration** - Self-documenting code with UTCP manuals
- 🧬 **Namespace hygiene** - Contained under `std.graft.*`

**Result**: You can use **any Zig library** or **Python module** as if it were native Janus code.

---

---

## **Native Zig Integration: The Home Ground** ⚡

Janus is built on Zig. You are not just grafting; you are **extending the compiler substrate**.

### **Inline Zig Blocks**

Write native Zig code directly inside Janus files. It is compiled alongside your Janus code with zero overhead.

```janus
foreign "zig" as substrate {
    const std = @import("std");

    pub fn optimized_sort(ptr: [*]i32, len: usize) void {
        const slice = ptr[0..len];
        std.sort.block(i32, slice, {}, std.sort.asc(i32));
    }
}

func sortData(data: []i32) do
    // Direct call into the Zig substrate
    substrate.optimized_sort(data.ptr, data.len);
end
```

### **Local File Grafting**

Import any `.zig` file from your project structure.

```janus
// Graft a local Zig file
graft math = zig "./vendor/math_utils.zig";

func compute() f64 do
    return math.fast_inverse_sqrt(16.0);
end
```

---

## **Quick Start: Injecting Zig Libraries**

### **Step 1: The Graft Declaration**

```janus
// Inject the popular zig-clap CLI library
graft clap = zig "https://github.com/Hejsil/zig-clap/archive/refs/tags/0.9.1.tar.gz";

// Now use it as native Janus code!
func main(args: []string) do
    let parsed = clap.parse(args, clap.parsers(...));
    processCommand(parsed);
end
```

That's it! The foreign Zig library is now available as `clap` in your scope.

### **Step 2: Capability-Based Security**

```janus
func secureProcess(path: string, ctx: Context) !Result do
    // Janus enforces capability checks automatically
    let data = std.fs.readFile(path, ctx.fs_read_capability);
    let result = my_zig_library.process(data);
    return result;
end
```

Foreign code cannot access your filesystem without explicit capability grants.

---

## **Python Integration: Scripting Superpowers**

### **Foreign Blocks for Python**

```janus
// Create a Python runtime instance
foreign "python" as py do
    import numpy as np
    import matplotlib.pyplot as plt

    def analyze_data(data):
        return {
            'mean': np.mean(data),
            'std': np.std(data),
            'plot': plt.histogram(data)
        }
end

// Use it seamlessly in Janus
func processSensorData(raw_data: []f64, ctx: Context) !Analysis do
    using py := try std.graft.python.open(ctx, cap: ctx.foreign.python.ipc) do

        // Convert Janus arrays to Python
        let py_array = py.call("numpy.array", [raw_data]);

        // Call our custom Python function
        let analysis = try py.call("analyze_data", [py_array]);

        // Extract results back to Janus types
        return Analysis{
            mean: try analysis.get("mean").to_number(),
            std: try analysis.get("std").to_number(),
            histogram_data: try analysis.get("plot").to_array()
        };
    end
end
```

**Holy cow!** You just seamlessly called **Python's NumPy** and **Matplotlib** from Janus code!

---

## **C Integration: The Universal Glue** 🔌

### **Direct Shared Object Grafting**

Janus treats C as the "lingua franca" of the system. You can graft shared objects (`.so`, `.dll`, `.dylib`) directly.

```janus
// Graft a standard C library
graft libc = c "libc.so.6";

func getCurrentTime() i64 do
    // Call C functions directly with zero overhead
    return libc.time(null);
end
```

### **Header Definitions**

For complex C libraries, you can provide inline C definitions to help the Janus compiler understand types.

```janus
foreign "c" as raylib {
    #include "raylib.h"
    // Janus automatically parses the header AST
}

func drawGame() do
    raylib.InitWindow(800, 600, "Janus Window");
    while !raylib.WindowShouldClose() do
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.RAYWHITE);
        raylib.DrawText("Hello C-Realms!", 190, 200, 20, raylib.LIGHTGRAY);
        raylib.EndDrawing();
    end
    raylib.CloseWindow();
end
```

---

## **Rust Integration: Oxidized Safety** 🦀

### **Cargo Crate Grafting**

Janus can drink directly from the Cargo stream. This requires `cargo` to be available in the build environment.

```janus
// Graft a Rust crate directly from a git repo
graft rocket = cargo "https://github.com/rwf2/Rocket";

// Or specify a crate version (uses crates.io)
graft serde = cargo "serde:1.0";
```

### **The Safety Bridge**

Janus respects Rust's safety guarantees.

```janus
// Using the grafted Rust library
func handleRequest(req: Request) !Response do
    // Rust's Results are mapped to Janus error unions automatically
    let processed = try rocket.process(req);
    return processed;
end
```

*Note: The first time you build, Janus will invoke Cargo to compile the grafted crate as a static library, then link it.*

---

## **Julia Integration: Scientific Sovereignty** 🟢

For high-performance numerical computing, nothing beats Julia.

### **Foreign Blocks for Julia**

```janus
foreign "julia" as flux do
    using Flux
    using LinearAlgebra

    function train_model(x_data, y_data)
        model = Chain(Dense(10, 5, relu), Dense(5, 2))
        loss(x, y) = Flux.mse(model(x), y)
        Flux.train!(loss, Flux.params(model), [(x_data, y_data)], ADAM())
        return model
    end
end
```

### **Tensor Bridging**

Janus Arrays (`[]f64`) map directly to Julia Arrays with zero checking.

```janus
func runTraining() !Model do
    // Capability: Requires 'julia.embed' capability
    using jl := try std.graft.julia.open(ctx, cap: ctx.foreign.julia.embed) do
        let x = std.tensor.random([10, 100]);
        let y = std.tensor.random([2, 100]);
        
        // Pass Janus tensors to Julia
        // Memory is shared, not copied!
        let model = jl.call("train_model", [x, y]); 
        
        return model;
    end
end
```

---

## **Complete Examples**

### **Example 1: High-Performance Math**

```janus
// Graft BLAS library for linear algebra
graft blas = zig "https://github.com/kooparse/zig-blases/archive/main.tar.gz";

func matrixMultiply(a: Matrix, b: Matrix) Matrix do
    // Direct call to optimized BLAS
    return blas.gemm(a, b, 1.0, 0.0);
end
```

### **Example 2: Web Scraping with Python**

```janus
foreign "python" as scraper do
    import requests
    from bs4 import BeautifulSoup

    def extract_titles(url):
        response = requests.get(url)
        soup = BeautifulSoup(response.text, 'html.parser')
        return [h1.text for h1 in soup.find_all('h1')]
end

func scrapeHeadlines(url: string, ctx: Context) ![]string do
    using scraper := try std.graft.python.open(ctx, cap: ctx.foreign.python.ipc) do
        let titles = try scraper.call("extract_titles", [url]);
        return titles.to_array(); // Automatic conversion
    end
end
```

### **Example 3: Cryptographic Operations**

```janus
// Graft a crypto library
graft crypto = zig "https://github.com/pornin/monocypher-zig/archive/main.tar.gz";

// Janus handles capability verification automatically
func encryptData(data: []u8, key: Key) ![]u8 do
    return crypto.aead_encrypt(data, key, "JanusData");
end
```

---

## **The Janus Advantage**

### **🚀 Performance**
- **Zero-copy** data transfer where possible
- **Native compilation** of grafted Zig code
- **Profile optimization** (:core vs :sovereign performance modes)

### **🔒 Security**
- **Capability tokens** required for sensitive operations
- **Sandboxing** prevents foreign code escape
- **Audit trails** track all foreign function calls
- **Memory Safety**: Rust grafts retain borrow checker guarantees at the boundary

### **🧪 Scientific Sovereignty**
- **Julia & Python**: Direct memory mapping for tensors (Zero-Copy)
- **Unified Logic**: One language (Janus) to orchestrate C, Rust, Python, and Julia

### **🤖 AI Integration**
```janus
// UTCP manuals make foreign code discoverable
func discoverCapabilities() ![]UTCPManual do
    // AI tools can explore all grafted capabilities
    return std.graft.enumerateAll();
end
```

---

## **Grafting Patterns**

### **Pattern 1: Zig Library Integration**

```janus
// For algorithm-heavy code
graft algorithm = zig "path/to/zig-algorithm-lib";

func processLargeDataset(data: Dataset) Result do
    // Use optimized parallel algorithms
    return algorithm.parallel_process(data);
end
```

### **Pattern 2: Python Ecosystem Access**

```janus
foreign "python" as ecosystem do
    import scikit-learn
    import pandas as pd
    # ... ML pipeline code ...
end

func trainModel(training_data: Dataset) Model do
    using ecosystem := std.graft.python.open(...) do
        let df = ecosystem.call("pandas.DataFrame", [training_data]);
        return ecosystem.call("train_ml_model", [df]);
    end
end
```

### **Pattern 3: Legacy System Integration**

```janus
// Connect to existing C libraries
graft legacy = c "legacy_system.so";

func migrateLegacyData() MigrationResult do
    let raw_data = legacy.fetch_records();
    return transformToModernFormat(raw_data);
end
```

---

## **Advanced Features**

### **Resource Management**

```janus
// Automatic cleanup
using py := std.graft.python.open(ctx, cap: ctx.foreign.python.ipc) do
    let result = py.call("process_data", [data]);
    // py.close() called automatically here
end
```

### **Error Handling**

```janus
let result = py.call("risky_operation", [args]) or do |err|
    // Handle Python exceptions in Janus
    match err.kind {
        .ForeignError => log.warn("Foreign code error: {err.message}");
        .CapabilityMissing => return Error.InsufficientPrivileges;
        .Timeout => return Error.OperationTimeout;
    }
end
```

### **Foreign Data Types**

```janus
// Automatic marshalling
let python_dict = py.eval("{'key': 'value'}");
let janus_table = python_dict.to_table();  // Converts Python dict to Janus table

// Zero-copy for arrays (where supported)
let numpy_array = py.call("numpy.linspace", [0, 100, 50]);
let janus_array = numpy_array.to_ndarray("f64");  // Direct memory mapping
```

---

## **Configuration & Profiles**

### **Profile-Specific Grafting**

```janus
// :core profile - IPC only
using py := std.graft.python.open(ctx, cap: ctx.foreign.python.ipc);

// :sovereign profile - Embed Python VM
using py := std.graft.python.open(ctx, cap: ctx.foreign.python.embed);
```

### **Policy-Based Governance**

```janus
// janus.policy.kdl
foreign {
    python {
        deterministic = false  // Allow non-deterministic ops in trusted contexts
        timeout_ms = 5000
        allowed_modules = ["numpy", "scipy", "matplotlib"]
    }
}
```

---

## **Troubleshooting**

### **Common Issues**

1. **Capability Missing**
   ```janus
   // Add to function parameters
   func myFunc(ctx: Context) do  // Context provides capabilities
       let py = std.graft.python.open(ctx, cap: ctx.foreign.python.ipc);
   end
   ```

2. **Timeout Errors**
   ```janus
   let result = py.call("long_running", args, timeout_ms: 30000);
   ```

3. **Type Conversion Issues**
   ```janus
   // Explicit conversions
   let py_obj = py.eval("some_python_expression");
   let janus_value = py_obj.to_number() or do return Error.ConversionFailed; end
   ```

---

## **What's Next?**

**Grafting is just getting started!**

- **More Languages**: Rust, Lua, JavaScript, R integration
- **Performance**: Direct memory mapping for tensor operations
- **AI Integration**: Automatic code generation from UTCP manuals
- **Cloud**: Distributed grafting across Janus clusters

---

**Welcome to the future of polyglot programming.** 🌍✨

*With Janus grafting, your code can leverage the entire world's software ecosystem while maintaining security, performance, and AI-first design principles.*</content>
